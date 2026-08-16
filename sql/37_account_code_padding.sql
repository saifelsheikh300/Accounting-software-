-- ============================================================
-- الدفعة 37: تنسيق كود الحسابات الفرعية بأرقام مبطّنة بالأصفار
-- المجموعات نفسها فضلت زي ما هي (1، 1.1، 1.2...)، بس الحسابات
-- الفعلية (اللي بيتقيد عليها مباشرة) بقى كودها بصيغة 001، 002...
-- مثال: الخزينة = 1.1.001، العملاء = 1.1.002، الأصول الثابتة = 1.2.001
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

do $$
declare v_group record; v_row record; v_n int;
begin
  for v_group in select id, code from accounts where is_group = true order by code
  loop
    v_n := 0;
    for v_row in select id from accounts where parent_id = v_group.id and is_group = false order by code
    loop
      v_n := v_n + 1;
      update accounts set code = v_group.code || '.' || lpad(v_n::text, 3, '0') where id = v_row.id;
    end loop;
  end loop;
end $$;

-- تحديث توليد الكود التلقائي عشان يتبع نفس الصيغة بعد كده
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
    else '1.1'
  end;
  select id into v_parent_id from accounts where code = v_parent_code;

  select count(*) into v_next_n from accounts where parent_id = v_parent_id;
  v_new_code := v_parent_code || '.' || lpad((v_next_n + 1)::text, 3, '0');

  insert into accounts (code, name, type, is_group, parent_id, sub_group)
  values (v_new_code, p_name, v_type, false, v_parent_id, case when v_parent_code = '1.1' then 'أصول متداولة' else null end)
  returning id into v_id;
  return v_id;
end;
$$;

grant execute on all functions in schema public to authenticated;
