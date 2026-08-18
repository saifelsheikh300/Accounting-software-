-- ============================================================
-- الدفعة 46: منع إضافة رصيد افتتاحي على حساب "تجميعي" (Group)
-- زي "الأصول" أو "رأس المال" أو "أصول متداولة" — دي حسابات
-- تجميع بس، مينفعش يتسجل عليها رصيد مباشر، لازم يتسجل على
-- الحساب التفصيلي (الفرعي) اللي جواها.
--
-- القائمة في الواجهة بقت بتفلترهم أصلاً، وده حماية إضافية على
-- مستوى قاعدة البيانات نفسها عشان الغلطة دي متتكررش من أي مكان
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

create or replace function rpc_add_opening_balance(
  p_account_id uuid, p_amount numeric, p_description text default '', p_as_of_date date default current_date
)
returns uuid language plpgsql security definer as $$
declare v_id uuid; v_account_name text; v_account_type text; v_is_group boolean; v_equity_account text := 'رصيد افتتاحي';
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'المبلغ مطلوب'; end if;

  select name, type, is_group into v_account_name, v_account_type, v_is_group from accounts where id = p_account_id;
  if v_account_name is null then raise exception 'الحساب غير موجود'; end if;
  if v_is_group then raise exception 'الحساب ده تجميعي (مجموعة) — اختاري الحساب الفرعي التفصيلي اللي جواه بدل ما تسجلي عليه مباشرة'; end if;

  insert into opening_balances (as_of_date, account_id, amount, description, locked)
  values (p_as_of_date, p_account_id, p_amount, p_description, true)
  returning id into v_id;

  if v_account_type in ('أصول','مصروفات') then
    perform fn_journal_entry(v_account_name, v_equity_account, p_amount, 'OB-' || v_id::text, 'رصيد افتتاحي — ' || coalesce(p_description,''));
  else
    perform fn_journal_entry(v_equity_account, v_account_name, p_amount, 'OB-' || v_id::text, 'رصيد افتتاحي — ' || coalesce(p_description,''));
  end if;

  perform fn_log_operation('ADD_OPENING_BALANCE', jsonb_build_object('account', v_account_name, 'amount', p_amount));
  return v_id;
end;
$$;

grant execute on all functions in schema public to authenticated;
