-- ============================================================
-- الدفعة 53: خانة اختيارية "كود الحساب نفسه" في شاشة إضافة
-- حساب جديد — لو كتبتيها هيستخدمها بالظبط زي ما هي، ولو
-- سيبتيها فاضية هيحسب أعلى رقم متاح تلقائي زي ما كان بيعمل.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

create or replace function rpc_add_account(
  p_name text, p_type text, p_parent_code text default null, p_is_group boolean default false, p_manual_code text default null
)
returns table(code text) language plpgsql security definer as $$
declare v_code text; v_max int; v_parent_id uuid;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  if p_parent_code is not null then
    select id into v_parent_id from accounts where accounts.code = p_parent_code;
    if v_parent_id is null then raise exception 'الحساب الأب غير موجود'; end if;
  end if;

  if p_manual_code is not null and trim(p_manual_code) <> '' then
    if exists (select 1 from accounts where accounts.code = p_manual_code) then
      raise exception 'الكود ده مستخدم بالفعل — اختاري رقم تاني';
    end if;
    v_code := p_manual_code;
  elsif p_parent_code is null then
    select coalesce(max(a.code::int), 0) into v_max from accounts a where a.parent_id is null and a.code ~ '^[0-9]+$';
    v_code := (v_max + 1)::text;
  else
    select coalesce(max(substring(a.code from '([0-9]+)$')::int), 0) into v_max
    from accounts a where a.parent_id = v_parent_id;
    v_code := p_parent_code || '.' || lpad((v_max + 1)::text, 3, '0');
  end if;

  insert into accounts (code, name, type, parent_id, is_group) values (v_code, p_name, p_type, v_parent_id, p_is_group);
  perform fn_log_operation('ADD_ACCOUNT', jsonb_build_object('code', v_code, 'name', p_name));
  return query select v_code;
end;
$$;

grant execute on all functions in schema public to authenticated;
