-- ============================================================
-- الدفعة 59:
-- (أ) حذف قيد محاسبي غلط بالكامل (المدين والدائن مع بعض) —
--     لو غلطتي وسجلتي حاجة بالغلط.
-- (ب) حذف حساب من شجرة الحسابات — بيرفض لو فيه أي قيود مسجلة
--     عليه (رصيده مش صفر) أو لو فيه حسابات فرعية تحته، عشان
--     محدش يمسح حساب فيه فلوس بالغلط.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

create or replace function rpc_delete_journal_entry(p_id uuid)
returns void language plpgsql security definer as $$
declare v_entry record;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select * into v_entry from journal_entries where id = p_id;
  if v_entry is null then raise exception 'القيد غير موجود'; end if;

  delete from journal_entries where id = p_id;
  perform fn_log_operation('DELETE_JOURNAL_ENTRY', jsonb_build_object(
    'entry_number', v_entry.entry_number, 'debit', v_entry.debit_account, 'credit', v_entry.credit_account,
    'amount', v_entry.amount, 'description', v_entry.description
  ));
end;
$$;

create or replace function rpc_delete_account(p_account_id uuid)
returns void language plpgsql security definer as $$
declare v_name text; v_has_children int; v_balance numeric;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select name into v_name from accounts where id = p_account_id;
  if v_name is null then raise exception 'الحساب غير موجود'; end if;

  select count(*) into v_has_children from accounts where parent_id = p_account_id;
  if v_has_children > 0 then raise exception 'الحساب ده فيه % حساب فرعي تحته — امسحيهم أو انقليهم الأول', v_has_children; end if;

  select coalesce(sum(amount) filter (where debit_account_id = p_account_id),0) - coalesce(sum(amount) filter (where credit_account_id = p_account_id),0)
  into v_balance from journal_entries;
  if abs(coalesce(v_balance,0)) > 0.009 then
    raise exception 'الحساب ده فيه فلوس مسجلة عليه (الرصيد مش صفر) — البرنامج بيرفض يمسح حساب فيه حركة مالية';
  end if;

  delete from accounts where id = p_account_id;
  perform fn_log_operation('DELETE_ACCOUNT', jsonb_build_object('name', v_name));
end;
$$;

grant execute on all functions in schema public to authenticated;
