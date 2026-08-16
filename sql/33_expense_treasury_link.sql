-- ============================================================
-- الدفعة 33: ربط كل مصروف بالحساب (الخزنة/البنك) اللي اتخصم منه فعليًا
-- كان بيتخصم صح من الخزنة فعليًا (القيد المحاسبي سليم من الأول)،
-- بس رقم الحساب مكانش بيتخزن على صف المصروف نفسه، فمكانش فيه طريقة
-- تشوفي بيها "المصروف ده خرج من فين" لاحقًا من غير رجوع لسجل الخزنة
-- وتخمين بالتاريخ والمبلغ.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

alter table expenses add column if not exists treasury_account_id uuid references treasury_accounts(id);

do $$
declare v_sig record;
begin
  for v_sig in select oid::regprocedure as sig from pg_proc where proname = 'rpc_add_expense'
  loop
    execute 'drop function if exists ' || v_sig.sig || ' cascade';
  end loop;
end $$;

create or replace function rpc_add_expense(
  p_main_category text, p_amount numeric, p_sub_category text default '', p_description text default '',
  p_is_recurring boolean default false, p_recurrence_days int default null, p_is_fixed_asset boolean default false,
  p_payment_method text default 'كاش', p_employee_id uuid default null, p_bonus numeric default null,
  p_expense_date timestamptz default now(), p_treasury_account_id uuid default null
)
returns uuid language plpgsql security definer as $$
declare v_expense_id uuid;
begin
  perform fn_check_period_open(p_expense_date);
  if not fn_has_permission('Expenses', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'المبلغ لازم يكون أكبر من صفر'; end if;
  if p_main_category is null or trim(p_main_category) = '' then raise exception 'الفئة الرئيسية مطلوبة'; end if;

  insert into expenses (expense_date, main_category, sub_category, description, amount, is_recurring, recurrence_days, is_fixed_asset, payment_method, employee_id, bonus, treasury_account_id, created_by)
  values (p_expense_date, p_main_category, coalesce(p_sub_category,''), coalesce(p_description,''), p_amount, p_is_recurring, p_recurrence_days, p_is_fixed_asset, p_payment_method, p_employee_id, p_bonus, p_treasury_account_id, auth.uid())
  returning id into v_expense_id;

  if p_payment_method <> 'آجل' then
    perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, coalesce(nullif(p_description,''), p_main_category));
  end if;

  perform fn_journal_entry('المصروفات: ' || p_main_category, case when p_payment_method = 'آجل' then 'دائنون آخرون' else 'الخزينة' end,
    p_amount, p_main_category, coalesce(nullif(p_description,''), p_main_category));

  perform fn_log_operation('ADD_EXPENSE', jsonb_build_object('category', p_main_category, 'amount', p_amount));
  return v_expense_id;
end;
$$;

grant execute on all functions in schema public to authenticated;
