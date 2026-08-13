-- ============================================================
-- الدفعة 31: خانة "نشط / غير نشط" للشريك
-- بدل حذف الشريك (وده بيكسر تاريخ حركاته وقيوده)، دلوقتي تقدري
-- تعلّمي الشريك اللي مشى كـ"غير نشط" — تاريخه وكل قيوده يفضلوا
-- زي ما هما، بس بيتميّز بصريًا في الشاشة إنه سابق مش حالي.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

alter table partners add column if not exists active boolean not null default true;

create or replace function rpc_set_partner_active(p_partner_name text, p_active boolean)
returns void language plpgsql security definer as $$
begin
  if not fn_has_permission('Capital', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  update partners set active = p_active where name = p_partner_name;
  if not found then raise exception 'الشريك غير موجود'; end if;
  perform fn_log_operation('SET_PARTNER_ACTIVE', jsonb_build_object('partner', p_partner_name, 'active', p_active));
end;
$$;

grant execute on function rpc_set_partner_active(text, boolean) to authenticated;
