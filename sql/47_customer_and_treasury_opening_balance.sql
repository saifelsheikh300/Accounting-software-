-- ============================================================
-- الدفعة 47:
-- (أ) "فاتورة سريعة بإجمالي يدوي" كانت بتتسجل في جدول invoices
--     بس من غير أي قيد محاسبي — يعني كانت بتظهر في الداشبورد
--     (المديونيات) لكن غايبة تمامًا عن ميزان المراجعة والميزانية
--     العمومية وحساب "العملاء (مدينون)". اتصلحت تبقى بتعمل قيد
--     محاسبي حقيقي زي أي عملية تانية.
-- (ب) رصيد افتتاحي لعميل بعينه (مديونية سابقة قبل استخدام
--     البرنامج): بيتسجل كفاتورة مفتوحة باسم العميل (تظهر في
--     شاشة الفواتير) + قيد محاسبي مقابل "رصيد افتتاحي" مش
--     "المبيعات" (عشان ميدخلش في إيرادات الفترة الحالية غلط).
-- (ج) رصيد افتتاحي للخزنة/البنك: بيسألك أنهي حساب خزنة أو بنك
--     بالظبط (لو عندك أكتر من واحد)، وبيحدّث رصيد الحساب ده
--     تحديدًا + القيد المحاسبي في نفس الوقت.
-- (قابلة لإعادة التشغيل بأمان بالكامل)
-- ============================================================

-- ------------------------------------------------------------
-- أ) فاتورة سريعة — بقيد محاسبي حقيقي
-- ------------------------------------------------------------
create or replace function rpc_create_quick_invoice(
  p_customer_name text, p_total numeric, p_paid numeric default 0, p_is_cod boolean default false
)
returns text language plpgsql security definer as $$
declare v_remaining numeric; v_status text; v_number text := 'INV-' || extract(epoch from now())::bigint::text;
begin
  if not fn_has_permission('Sales', 'إضافة') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_customer_name is null or trim(p_customer_name) = '' then raise exception 'اسم العميل مطلوب'; end if;
  if p_total is null or p_total <= 0 then raise exception 'الإجمالي مطلوب'; end if;

  v_remaining := p_total - coalesce(p_paid, 0);
  v_status := case
    when p_is_cod then 'تم التحصيل COD'
    when v_remaining <= 0 then 'مدفوعة بالكامل'
    when p_paid > 0 then 'مدفوعة جزئيًا'
    else 'متأخرة'
  end;

  insert into invoices (invoice_number, customer_name, total, paid, remaining, status)
  values (v_number, p_customer_name, p_total, coalesce(p_paid,0), v_remaining, v_status);

  -- القيد المحاسبي: كل الإجمالي مبيعات، والمدفوع بس اللي يدخل الخزينة فورًا
  perform fn_journal_entry('العملاء (مدينون)', 'المبيعات', p_total, v_number, 'فاتورة سريعة — ' || p_customer_name);
  if coalesce(p_paid, 0) > 0 then
    perform fn_journal_entry('الخزينة', 'العملاء (مدينون)', p_paid, v_number, 'تحصيل فوري فاتورة ' || v_number);
  end if;

  perform fn_log_operation('CREATE_QUICK_INVOICE', jsonb_build_object('customer', p_customer_name, 'total', p_total));
  return v_number;
end;
$$;

-- ------------------------------------------------------------
-- ب) رصيد افتتاحي لعميل بعينه
-- ------------------------------------------------------------
create or replace function rpc_add_customer_opening_balance(
  p_customer_name text, p_customer_phone text default '', p_amount numeric default 0,
  p_as_of_date date default current_date, p_description text default ''
)
returns text language plpgsql security definer as $$
declare v_number text := 'INV-OB-' || extract(epoch from now())::bigint::text;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_customer_name is null or trim(p_customer_name) = '' then raise exception 'اسم العميل مطلوب'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'المبلغ مطلوب'; end if;

  insert into invoices (invoice_number, customer_name, total, paid, remaining, status)
  values (v_number, p_customer_name || case when p_customer_phone <> '' then ' — ' || p_customer_phone else '' end,
          p_amount, 0, p_amount, 'مفتوحة');

  perform fn_journal_entry('العملاء (مدينون)', 'رصيد افتتاحي', p_amount, v_number,
    'رصيد افتتاحي (مديونية سابقة) — ' || p_customer_name || coalesce(' — ' || nullif(p_description,''), ''));

  perform fn_log_operation('ADD_CUSTOMER_OPENING_BALANCE', jsonb_build_object('customer', p_customer_name, 'amount', p_amount));
  return v_number;
end;
$$;

-- ------------------------------------------------------------
-- ج) رصيد افتتاحي لحساب خزنة/بنك محدد
-- ------------------------------------------------------------
create or replace function rpc_add_treasury_opening_balance(
  p_treasury_account_id uuid, p_amount numeric, p_as_of_date date default current_date, p_description text default ''
)
returns uuid language plpgsql security definer as $$
declare v_id uuid; v_name text; v_equity_account text := 'رصيد افتتاحي';
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'المبلغ مطلوب'; end if;

  select name into v_name from treasury_accounts where id = p_treasury_account_id and active = true;
  if v_name is null then raise exception 'حساب الخزنة/البنك ده مش موجود'; end if;

  update treasury_accounts set current_balance = current_balance + p_amount, opening_balance = opening_balance + p_amount
  where id = p_treasury_account_id;

  insert into cash_flow (flow_date, treasury_account_id, direction, amount, source, balance_after)
  values (p_as_of_date, p_treasury_account_id, 'داخل', p_amount, 'رصيد افتتاحي — ' || v_name,
    (select current_balance from treasury_accounts where id = p_treasury_account_id))
  returning id into v_id;

  perform fn_journal_entry('الخزينة', v_equity_account, p_amount, 'OB-TR-' || v_id::text,
    'رصيد افتتاحي — ' || v_name || coalesce(' — ' || nullif(p_description,''), ''));

  perform fn_log_operation('ADD_TREASURY_OPENING_BALANCE', jsonb_build_object('treasury_account', v_name, 'amount', p_amount));
  return v_id;
end;
$$;

grant execute on all functions in schema public to authenticated;
