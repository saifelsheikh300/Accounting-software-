-- ============================================================
-- الدفعة 44:
-- (أ) حسابات رأس المال بتاعة كل شريك (زي "رأس المال — جهاد")
--     كانت بتتعمل كحساب منفصل مستقل تحت "حقوق الملكية" مباشرة،
--     مش تحت "رأس المال" الأساسي. دلوقتي بقى "رأس المال" (3.001)
--     تجميعي، وأي شريك جديد بيضاف كفرع تحته.
-- (ب) تصحيح ربط الحسابات الأساسية (3.001، 3.002، 4.001، 4.002،
--     5.001–5.008) بالمجموعة الأب بتاعتها في دالة تعمير شجرة
--     الحسابات، عشان لو حد شغّلها على قاعدة بيانات جديدة تمامًا
--     (براند تاني) تتبني صح من الأول.
-- (قابلة لإعادة التشغيل بأمان بالكامل، مش بتمسح أو تعيد تسمية
-- أي حساب موجود، بس بتظبط الربط الأب/الابن)
-- ============================================================

-- ------------------------------------------------------------
-- أ) رأس المال كمجموعة، وترحيل حسابات الشركاء تحتها
-- ------------------------------------------------------------
do $$
declare v_capital_group_id uuid; v_root3_id uuid;
begin
  select id into v_root3_id from accounts where code = '3';

  select id into v_capital_group_id from accounts where name = 'رأس المال';
  if v_capital_group_id is null then
    insert into accounts (code, name, type, is_group, parent_id) values ('3.001', 'رأس المال', 'حقوق ملكية', true, v_root3_id)
    returning id into v_capital_group_id;
  else
    update accounts set is_group = true, parent_id = coalesce(parent_id, v_root3_id) where id = v_capital_group_id;
  end if;

  -- رحّلي أي حساب شريك موجود بالفعل (زي "رأس المال — جهاد") ليبقى تحت المجموعة دي
  update accounts set parent_id = v_capital_group_id
  where name ilike 'رأس المال —%' and id <> v_capital_group_id and (parent_id is null or parent_id = v_root3_id);
end $$;

-- ------------------------------------------------------------
-- تعديل fn_resolve_account: أي حساب شريك جديد ("رأس المال — X")
-- يتولد تلقائيًا تحت مجموعة "رأس المال" مش تحت "حقوق الملكية" مباشرة
-- ------------------------------------------------------------
create or replace function fn_resolve_account(p_name text)
returns uuid language plpgsql security definer as $$
declare
  v_id uuid; v_type text; v_parent_code text; v_parent_id uuid;
  v_max_n int; v_new_code text; v_sub_group text; v_attempt int;
begin
  if p_name is null or trim(p_name) = '' then return null; end if;

  select id into v_id from accounts where name = p_name;
  if v_id is not null then return v_id; end if;

  v_type := case
    when p_name ilike 'المصروفات%' or p_name ilike 'تكلفة البضاعة%' or p_name ilike '%اهلاك%' or p_name ilike '%إهلاك%' or p_name ilike 'المرتبات%' then 'مصروفات'
    when p_name ilike 'المبيعات%' or p_name ilike '%إيرادات%' then 'إيرادات'
    when p_name ilike '%رأس المال%' then 'حقوق ملكية'
    when p_name ilike '%الموردون%' or p_name ilike '%دائن%' or p_name ilike 'شيكات دفع%' or p_name ilike 'مستحقات%' then 'خصوم'
    else 'أصول'
  end;

  -- ✅ حساب شريك خاص برأس المال يتعمل تحت مجموعة "رأس المال" نفسها
  if p_name ilike 'رأس المال —%' then
    select id into v_parent_id from accounts where name = 'رأس المال';
    if v_parent_id is null then
      select id into v_parent_id from accounts where code = '3';
      insert into accounts (code, name, type, is_group, parent_id) values ('3.001', 'رأس المال', 'حقوق ملكية', true, v_parent_id) returning id into v_parent_id;
    end if;
    select code into v_parent_code from accounts where id = v_parent_id;
  else
    v_parent_code := case v_type
      when 'مصروفات' then '5' when 'إيرادات' then '4' when 'حقوق ملكية' then '3'
      when 'خصوم' then '2.1'
      else '1.1'
    end;
    select id into v_parent_id from accounts where code = v_parent_code;
  end if;

  v_sub_group := case v_parent_code when '1.1' then 'أصول متداولة' when '2.1' then 'خصوم متداولة' else null end;

  v_attempt := 0;
  loop
    v_attempt := v_attempt + 1;

    select coalesce(max(substring(code from '([0-9]+)$')::int), 0)
      into v_max_n
      from accounts where parent_id = v_parent_id;

    v_new_code := v_parent_code || '.' || lpad((v_max_n + 1 + (v_attempt - 1))::text, 3, '0');

    begin
      insert into accounts (code, name, type, is_group, parent_id, sub_group)
      values (v_new_code, p_name, v_type, false, v_parent_id, v_sub_group)
      returning id into v_id;
      return v_id;
    exception when unique_violation then
      if v_attempt >= 20 then raise; end if;
    end;
  end loop;
end;
$$;

-- ------------------------------------------------------------
-- ب) إصلاح الأب/الابن الناقص في دالة تعمير الشجرة الافتراضية
-- (لتركيبات جديدة تمامًا في المستقبل — مفيش تأثير على بياناتك الحالية)
-- ------------------------------------------------------------
create or replace function rpc_seed_default_chart_of_accounts()
returns void language plpgsql security definer as $$
declare
  v_1 uuid; v_11 uuid; v_12 uuid; v_2 uuid; v_21 uuid; v_3 uuid; v_4 uuid; v_5 uuid;
begin
  insert into accounts (code, name, type, is_group)
  select code, name, type, true from (values
    ('1','الأصول','أصول'), ('2','الخصوم','خصوم'), ('3','حقوق الملكية','حقوق ملكية'),
    ('4','الإيرادات','إيرادات'), ('5','المصروفات','مصروفات')
  ) as t(code, name, type)
  where not exists (select 1 from accounts a where a.code = t.code or a.name = t.name);

  select id into v_1 from accounts where code = '1';
  select id into v_2 from accounts where code = '2';
  select id into v_3 from accounts where code = '3';
  select id into v_4 from accounts where code = '4';
  select id into v_5 from accounts where code = '5';

  insert into accounts (code, name, type, is_group, parent_id)
  select '1.1', 'أصول متداولة', 'أصول', true, v_1 where not exists (select 1 from accounts where code = '1.1' or name = 'أصول متداولة');
  insert into accounts (code, name, type, is_group, parent_id)
  select '1.2', 'أصول ثابتة', 'أصول', true, v_1 where not exists (select 1 from accounts where code = '1.2' or name = 'أصول ثابتة');
  insert into accounts (code, name, type, is_group, parent_id)
  select '2.1', 'خصوم متداولة', 'خصوم', true, v_2 where not exists (select 1 from accounts where code = '2.1' or name = 'خصوم متداولة');
  insert into accounts (code, name, type, is_group, parent_id)
  select '2.2', 'خصوم طويلة الأجل', 'خصوم', true, v_2 where not exists (select 1 from accounts where code = '2.2' or name = 'خصوم طويلة الأجل');

  select id into v_11 from accounts where code = '1.1';
  select id into v_12 from accounts where code = '1.2';
  select id into v_21 from accounts where code = '2.1';

  insert into accounts (code, name, type, is_group, parent_id, sub_group)
  select v.code, v.name, v.type, v.is_grp, v.parent_id, v.sub_group from (values
    ('1.1.001', 'الخزينة', 'أصول', false, v_11, 'أصول متداولة'),
    ('1.1.002', 'العملاء (مدينون)', 'أصول', false, v_11, 'أصول متداولة'),
    ('1.1.003', 'العهدة', 'أصول', false, v_11, 'أصول متداولة'),
    ('1.1.004', 'المخزون', 'أصول', false, v_11, 'أصول متداولة'),
    ('1.2.001', 'الأصول الثابتة', 'أصول', false, v_12, null),
    ('1.2.002', 'مجمع إهلاك الأصول', 'أصول', false, v_12, null),
    ('2.1.001', 'الموردون', 'خصوم', false, v_21, 'خصوم متداولة'),
    ('3.001', 'رأس المال', 'حقوق ملكية', true, v_3, null),
    ('3.002', 'رصيد افتتاحي', 'حقوق ملكية', false, v_3, null),
    ('4.001', 'المبيعات', 'إيرادات', false, v_4, null),
    ('4.002', 'إيرادات أخرى', 'إيرادات', false, v_4, null),
    ('5.001', 'تكلفة البضاعة المباعة', 'مصروفات', false, v_5, null),
    ('5.002', 'المرتبات', 'مصروفات', false, v_5, null),
    ('5.003', 'المصروفات: إيجار', 'مصروفات', false, v_5, null),
    ('5.004', 'المصروفات: كهرباء ومياه', 'مصروفات', false, v_5, null),
    ('5.005', 'المصروفات: مواصلات', 'مصروفات', false, v_5, null),
    ('5.006', 'المصروفات: صيانة', 'مصروفات', false, v_5, null),
    ('5.007', 'المصروفات: تسويق وإعلان', 'مصروفات', false, v_5, null),
    ('5.008', 'المصروفات: أخرى', 'مصروفات', false, v_5, null)
  ) as v(code, name, type, is_grp, parent_id, sub_group)
  where not exists (select 1 from accounts a where a.code = v.code or a.name = v.name);

  -- تصحيح أي حساب اتعمل قبل كده بربط أب ناقص (parent_id فاضي) لنفس الأسماء دي
  update accounts a set parent_id = v_3 where a.code in ('3.002') and a.parent_id is null;
  update accounts a set parent_id = v_4 where a.code in ('4.001','4.002') and a.parent_id is null;
  update accounts a set parent_id = v_5 where a.code like '5.0%' and a.parent_id is null;
end;
$$;

grant execute on all functions in schema public to authenticated;

select rpc_seed_default_chart_of_accounts();
