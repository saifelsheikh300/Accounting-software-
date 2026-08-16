-- ============================================================
-- الدفعة 36: إعادة هيكلة شجرة الحسابات بتكويد هرمي حقيقي
--
-- قبل كده، كل الحسابات كانت "مسطّحة" (Flat) — كلها تحت تصنيف واحد
-- عام زي "أصول" من غير أي تفريق بين أصول متداولة (خزينة، مخزون،
-- عملاء...) وأصول ثابتة (المعدات...)، ومن غير أي تكويد هرمي حقيقي.
-- دلوقتي بقى فيه شجرة فعلية بكود متسلسل:
--   1 الأصول → 1.1 أصول متداولة / 1.2 أصول ثابتة
--   2 الخصوم
--   3 حقوق الملكية
--   4 الإيرادات
--   5 المصروفات
-- وكل حساب موجود فعليًا اتنقل تحت المجموعة الصح بتاعته بكود فرعي.
-- أي حساب جديد يتعمل تلقائيًا بعد كده (fn_resolve_account) هيتحط
-- في المجموعة الصح من نفس الشجرة أوتوماتيك.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

alter table accounts add column if not exists sub_group text;

-- ------------------------------------------------------------
-- 1) المجموعات الرئيسية الخمسة (لو مش موجودة)
-- ------------------------------------------------------------
insert into accounts (code, name, type, is_group)
select code, name, type, true from (values
  ('1', 'الأصول', 'أصول'), ('2', 'الخصوم', 'خصوم'), ('3', 'حقوق الملكية', 'حقوق ملكية'),
  ('4', 'الإيرادات', 'إيرادات'), ('5', 'المصروفات', 'مصروفات')
) as t(code, name, type)
where not exists (select 1 from accounts where accounts.code = t.code and accounts.is_group);

-- ------------------------------------------------------------
-- 2) المجموعات الفرعية تحت الأصول
-- ------------------------------------------------------------
insert into accounts (code, name, type, is_group, parent_id)
select '1.1', 'أصول متداولة', 'أصول', true, id from accounts where code = '1'
and not exists (select 1 from accounts where code = '1.1');

insert into accounts (code, name, type, is_group, parent_id)
select '1.2', 'أصول ثابتة', 'أصول', true, id from accounts where code = '1'
and not exists (select 1 from accounts where code = '1.2');

-- ------------------------------------------------------------
-- 3) نقل الحسابات الموجودة فعليًا لمكانها الصح + كود فرعي متسلسل
-- ------------------------------------------------------------
do $$
declare
  v_current_group_id uuid; v_fixed_group_id uuid; v_liab_group_id uuid; v_equity_group_id uuid;
  v_rev_group_id uuid; v_exp_group_id uuid;
  v_row record; v_n int;
begin
  select id into v_current_group_id from accounts where code = '1.1';
  select id into v_fixed_group_id from accounts where code = '1.2';
  select id into v_liab_group_id from accounts where code = '2';
  select id into v_equity_group_id from accounts where code = '3';
  select id into v_rev_group_id from accounts where code = '4';
  select id into v_exp_group_id from accounts where code = '5';

  -- أصول متداولة
  v_n := 0;
  for v_row in select id from accounts where is_group = false and name in
    ('الخزينة', 'العملاء (مدينون)', 'المخزون', 'العهدة', 'سلف الموظفين') order by name
  loop
    v_n := v_n + 1;
    update accounts set parent_id = v_current_group_id, sub_group = 'أصول متداولة', code = '1.1.' || v_n where id = v_row.id;
  end loop;

  -- أصول ثابتة
  v_n := 0;
  for v_row in select id from accounts where is_group = false and name in ('الأصول الثابتة', 'مجمع إهلاك الأصول') order by name
  loop
    v_n := v_n + 1;
    update accounts set parent_id = v_fixed_group_id, sub_group = 'أصول ثابتة', code = '1.2.' || v_n where id = v_row.id;
  end loop;

  -- الخصوم (الموردون، دائنون آخرون، مستحقات إدارة الشركاء...)
  v_n := 0;
  for v_row in select id from accounts where is_group = false and type = 'خصوم' order by name
  loop
    v_n := v_n + 1;
    update accounts set parent_id = v_liab_group_id, code = '2.' || v_n where id = v_row.id;
  end loop;

  -- حقوق الملكية (رأس المال لكل شريك، رصيد افتتاحي)
  v_n := 0;
  for v_row in select id from accounts where is_group = false and type = 'حقوق ملكية' order by name
  loop
    v_n := v_n + 1;
    update accounts set parent_id = v_equity_group_id, code = '3.' || v_n where id = v_row.id;
  end loop;

  -- الإيرادات
  v_n := 0;
  for v_row in select id from accounts where is_group = false and type = 'إيرادات' order by name
  loop
    v_n := v_n + 1;
    update accounts set parent_id = v_rev_group_id, code = '4.' || v_n where id = v_row.id;
  end loop;

  -- المصروفات
  v_n := 0;
  for v_row in select id from accounts where is_group = false and type = 'مصروفات' order by name
  loop
    v_n := v_n + 1;
    update accounts set parent_id = v_exp_group_id, code = '5.' || v_n where id = v_row.id;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 4) أي حساب جديد يتعمل تلقائيًا بعد كده يتحط في مكانه الصح فورًا
-- ------------------------------------------------------------
create or replace function fn_resolve_account(p_name text)
returns uuid language plpgsql security definer as $$
declare v_id uuid; v_type text; v_parent_code text; v_parent_id uuid; v_next_n int; v_new_code text;
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

  v_parent_code := case v_type
    when 'مصروفات' then '5' when 'إيرادات' then '4' when 'حقوق ملكية' then '3' when 'خصوم' then '2'
    else '1.1' -- أي أصل جديد غير معروف بيتحط تحت "أصول متداولة" افتراضيًا
  end;
  select id into v_parent_id from accounts where code = v_parent_code;

  select count(*) into v_next_n from accounts where parent_id = v_parent_id;
  v_new_code := v_parent_code || '.' || (v_next_n + 1);

  insert into accounts (code, name, type, is_group, parent_id, sub_group)
  values (v_new_code, p_name, v_type, false, v_parent_id, case when v_parent_code = '1.1' then 'أصول متداولة' else null end)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on all functions in schema public to authenticated;
