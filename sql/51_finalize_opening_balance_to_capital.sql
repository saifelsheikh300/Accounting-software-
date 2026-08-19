-- ============================================================
-- الدفعة 51: قفل رصيد أول مدة ونقله لرأس المال باسم صاحب المحل.
--
-- بعد ما تخلصي إدخال كل أرصدة أول مدة (خزنة، عملاء، مخزون،
-- موردين)، رصيدهم بيتجمع في حساب مؤقت اسمه "رصيد افتتاحي". الخطوة
-- دي بتاخد الرصيد ده وتنقله بالكامل لحساب "رأس المال" الحقيقي
-- باسم صاحب المحل، وتصفّر "رصيد افتتاحي" — من غير ما تتحرك أي
-- فلوس فعلية أو يتضاف أي حاجة جديدة، هو مجرد إعادة تصنيف.
-- (قابلة لإعادة التشغيل بأمان — تاخد الرصيد الموجود وقت التنفيذ
-- أيًا كان، مش رقم ثابت)
-- ============================================================

create or replace function rpc_finalize_opening_balance_to_capital(p_owner_name text)
returns numeric language plpgsql security definer as $$
declare v_ob_id uuid; v_balance numeric; v_capital_account text;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_owner_name is null or trim(p_owner_name) = '' then raise exception 'اسم صاحب رأس المال مطلوب'; end if;

  select id into v_ob_id from accounts where name = 'رصيد افتتاحي';
  if v_ob_id is null then raise exception 'مفيش حساب "رصيد افتتاحي" أصلاً'; end if;

  select coalesce(sum(amount) filter (where credit_account_id = v_ob_id),0) - coalesce(sum(amount) filter (where debit_account_id = v_ob_id),0)
  into v_balance from journal_entries;

  if v_balance = 0 then raise exception 'رصيد "رصيد افتتاحي" صفر أصلاً — مفيش حاجة تتنقل'; end if;

  v_capital_account := 'رأس المال — ' || p_owner_name;

  if v_balance > 0 then
    perform fn_journal_entry('رصيد افتتاحي', v_capital_account, v_balance, 'CLOSE-OB-' || extract(epoch from now())::bigint::text, 'قفل رصيد أول مدة لرأس المال — ' || p_owner_name);
  else
    perform fn_journal_entry(v_capital_account, 'رصيد افتتاحي', abs(v_balance), 'CLOSE-OB-' || extract(epoch from now())::bigint::text, 'قفل رصيد أول مدة لرأس المال — ' || p_owner_name);
  end if;

  perform fn_log_operation('FINALIZE_OPENING_BALANCE', jsonb_build_object('owner', p_owner_name, 'amount', v_balance));
  return v_balance;
end;
$$;

grant execute on all functions in schema public to authenticated;
