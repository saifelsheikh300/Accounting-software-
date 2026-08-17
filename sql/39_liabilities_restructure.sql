-- ============================================================
-- الدفعة 39: تقسيم الخصوم زي الأصول بالظبط
-- 2.1 خصوم متداولة (مستحقة خلال سنة) — الموردون، دائنون آخرون،
--     مستحقات الشركاء، شيكات الدفع...
-- 2.2 خصوم طويلة الأجل (قروض وما شابه — فاضية دلوقتي، جاهزة لو
--     احتجتيها بعدين)
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

insert into accounts (code, name, type, is_group, parent_id)
select '2.1', 'خصوم متداولة', 'خصوم', true, id from accounts where code = '2'
and not exists (select 1 from accounts where code = '2.1');

insert into accounts (code, name, type, is_group, parent_id)
select '2.2', 'خصوم طويلة الأجل', 'خصوم', true, id from accounts where code = '2'
and not exists (select 1 from accounts where code = '2.2');

do $$
declare v_current_group_id uuid; v_row record; v_n int;
begin
  select id into v_current_group_id from accounts where code = '2.1';

  v_n := 0;
  for v_row in select id from accounts where is_group = false and type = 'خصوم' and (parent_id is null or parent_id <> v_current_group_id) order by name
  loop
    v_n := v_n + 1;
    update accounts set parent_id = v_current_group_id, sub_group = 'خصوم متداولة', code = '2.1.' || lpad(v_n::text, 3, '0') where id = v_row.id;
  end loop;
end $$;

-- أي حساب خصوم جديد يتحط تلقائيًا تحت "خصوم متداولة" افتراضيًا
-- (هي الحالة الشائعة فعليًا — الموردين ومستحقات الشركاء دايمًا قصيرة الأجل)
create or replace function fn_resolve_account(p_name text)
returns uuid language plpgsql security definer as $$
declare v_id uuid; v_type text; v_parent_code text; v_parent_id uuid; v_next_n int; v_new_code text; v_sub_group text;
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
    when 'مصروفات' then '5' when 'إيرادات' then '4' when 'حقوق ملكية' then '3'
    when 'خصوم' then '2.1'
    else '1.1'
  end;
  v_sub_group := case v_parent_code when '1.1' then 'أصول متداولة' when '2.1' then 'خصوم متداولة' else null end;
  select id into v_parent_id from accounts where code = v_parent_code;

  select count(*) into v_next_n from accounts where parent_id = v_parent_id;
  v_new_code := v_parent_code || '.' || lpad((v_next_n + 1)::text, 3, '0');

  insert into accounts (code, name, type, is_group, parent_id, sub_group)
  values (v_new_code, p_name, v_type, false, v_parent_id, v_sub_group)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on all functions in schema public to authenticated;
