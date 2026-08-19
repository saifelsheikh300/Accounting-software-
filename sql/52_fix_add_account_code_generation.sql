-- ============================================================
-- الدفعة 52: إصلاح خطأ "invalid input syntax for type integer:
-- .001" اللي كان بيظهر عند إضافة حساب جديد يدوي من شجرة الحسابات.
--
-- السبب: الدالة كانت بتحسب رقم الحساب الجديد بافتراض إن كود
-- الابن = كود الأب + رقم مباشرة من غير نقطة فاصلة (زي "1.1001")،
-- لكن كل الأكواد الفعلية في النظام بصيغة "1.1.001" (بنقطة فاصلة).
-- فكانت بتحاول تحول ".001" لرقم صحيح فيحصل خطأ.
--
-- الإصلاح: بقت بتحسب أعلى رقم فعلي بنفس طريقة باقي الدوال
-- (استخراج آخر أرقام في الكود، مش قص بالطول)، وبتبني الكود
-- الجديد بصيغة "الأب.رقم" الصحيحة.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

create or replace function rpc_add_account(p_name text, p_type text, p_parent_code text default null, p_is_group boolean default false)
returns table(code text) language plpgsql security definer as $$
declare v_code text; v_max int; v_parent_id uuid;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  if p_parent_code is null then
    select coalesce(max(a.code::int), 0) into v_max from accounts a where a.parent_id is null and a.code ~ '^[0-9]+$';
    v_code := (v_max + 1)::text;
  else
    select id into v_parent_id from accounts where accounts.code = p_parent_code;
    if v_parent_id is null then raise exception 'الحساب الأب غير موجود'; end if;
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
