-- ============================================================
-- الدفعة 21: إصلاح جذري — تضارب الدوال المكررة (Overloading)
-- كل مرة كانت باراميترات دالة بتتغير (إضافة p_treasury_account_id
-- أو p_currency_code وغيره)، Postgres كان بيسيب النسخة القديمة
-- شغالة جنب الجديدة بدل ما يستبدلها بالكامل — لأنه "استبدال" فعلي
-- بس لو نفس البصمة (Signature) بالظبط. النتيجة: أكتر من نسخة لنفس
-- الدالة، والنظام مش عارف يختار مين وقت التنفيذ.
-- الحل: نمسح كل نسخ كل دالة من الدوال دي، ونعيد إنشاء النسخة
-- الصحيحة النهائية بس لكل واحدة فيهم.
-- ============================================================

do $$
declare v_func text;
declare v_sig record;
begin
  foreach v_func in array array[
    'rpc_record_sale', 'rpc_create_purchase_order', 'rpc_add_expense',
    'rpc_add_petty_cash', 'rpc_pay_invoice_installment', 'rpc_pay_supplier_installment',
    'rpc_update_check_status', 'rpc_add_capital_movement'
  ]
  loop
    for v_sig in select oid::regprocedure as sig from pg_proc where proname = v_func
    loop
      execute 'drop function if exists ' || v_sig.sig || ' cascade';
    end loop;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 1) rpc_record_sale — النسخة النهائية (خزنة حقيقية + COGS + عملات + قفل فترات)
-- ------------------------------------------------------------
create or replace function rpc_record_sale(
  p_source text, p_items jsonb, p_discount numeric default 0, p_payment_method text default null,
  p_invoice_id uuid default null, p_customer_name text default '', p_customer_phone text default '',
  p_warehouse_id uuid default null, p_sale_date timestamptz default now(), p_treasury_account_id uuid default null,
  p_currency_code text default 'EGP'
)
returns table(sale_id uuid, sale_number text, total numeric) language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_cost numeric; v_price numeric; v_qty numeric; v_avail_qty numeric;
  v_subtotal numeric := 0; v_total numeric; v_sale_id uuid; v_sale_number text;
  v_is_cash boolean; v_total_cogs numeric := 0; v_rate numeric; v_base_total numeric;
begin
  perform fn_check_period_open(p_sale_date);
  if not fn_has_permission('Sales', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم منتج واحد على الأقل'; end if;

  v_sale_number := 'S-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || floor(random()*900+100)::text;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost, quantity into v_variant_id, v_cost, v_avail_qty from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    if v_avail_qty < v_qty then raise exception 'الكمية غير كافية للصنف % — المتاح فعليًا: %', v_item->>'variant_code', v_avail_qty; end if;
    v_price := coalesce((v_item->>'price')::numeric, 0);
    v_subtotal := v_subtotal + (v_price * v_qty);
    v_total_cogs := v_total_cogs + (coalesce(v_cost, 0) * v_qty);
  end loop;

  v_total := v_subtotal - coalesce(p_discount, 0);

  if p_currency_code = 'EGP' then
    v_base_total := v_total;
  else
    select rate_to_base into v_rate from exchange_rates where currency_code = p_currency_code and rate_date <= p_sale_date::date order by rate_date desc limit 1;
    if v_rate is null then raise exception 'سعر الصرف غير محدد للعملة %', p_currency_code; end if;
    v_base_total := round(v_total * v_rate, 2);
  end if;

  v_is_cash := p_payment_method is not null and p_payment_method <> 'آجل';

  insert into sales (sale_number, sale_date, source, subtotal, discount, total, payment_method, invoice_id, customer_name, customer_phone, warehouse_id, created_by, currency_code)
  values (v_sale_number, p_sale_date, p_source, v_subtotal, coalesce(p_discount,0), v_total, p_payment_method, p_invoice_id, p_customer_name, p_customer_phone, p_warehouse_id, auth.uid(), p_currency_code)
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost into v_variant_id, v_cost from product_variants where code = v_item->>'variant_code';
    v_qty := (v_item->>'qty')::numeric;
    v_price := coalesce((v_item->>'price')::numeric, 0);

    insert into sale_items (sale_id, variant_id, qty, unit_price, unit_cost) values (v_sale_id, v_variant_id, v_qty, v_price, v_cost);
    update product_variants set quantity = quantity - v_qty where id = v_variant_id;
  end loop;

  perform fn_journal_entry(case when v_is_cash then 'الخزينة' else 'العملاء (مدينون)' end, 'المبيعات', v_base_total, v_sale_number, 'بيعة رقم ' || v_sale_number);
  if v_total_cogs > 0 then
    perform fn_journal_entry('تكلفة البضاعة المباعة', 'المخزون', v_total_cogs, v_sale_number, 'تكلفة بضاعة بيعة ' || v_sale_number);
  end if;
  if v_is_cash then perform fn_move_treasury('داخل', v_base_total, p_treasury_account_id, 'بيعة ' || v_sale_number); end if;

  if p_customer_phone is not null and p_customer_phone <> '' then
    insert into customers (phone, name, order_count, total_purchases, first_order_at)
    values (p_customer_phone, p_customer_name, 1, v_total, now())
    on conflict (phone) do update set
      order_count = customers.order_count + 1,
      total_purchases = customers.total_purchases + v_total,
      name = coalesce(nullif(excluded.name, ''), customers.name);
  end if;

  perform fn_log_operation('RECORD_SALE', jsonb_build_object('sale_number', v_sale_number, 'total', v_total, 'currency', p_currency_code));
  return query select v_sale_id, v_sale_number, v_total;
end;
$$;

-- ------------------------------------------------------------
-- 2) rpc_create_purchase_order — النسخة النهائية
-- ------------------------------------------------------------
create or replace function rpc_create_purchase_order(
  p_supplier_name text, p_items jsonb, p_payment_status text default 'مدفوع بالكامل',
  p_amount_paid numeric default 0, p_warehouse_id uuid default null, p_treasury_account_id uuid default null
)
returns table(order_id uuid, order_number text, total numeric) language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_old_cost numeric; v_old_qty numeric; v_qty numeric; v_price numeric;
  v_new_avg_cost numeric; v_total numeric := 0; v_supplier_id uuid; v_order_id uuid; v_order_number text;
  v_paid numeric; v_remaining numeric; v_method text;
begin
  perform fn_check_period_open(now());
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

  select value into v_method from settings where key = 'inventoryValuationMethod';
  v_method := coalesce(v_method, 'متوسط مرجح');

  select id into v_supplier_id from suppliers where name = p_supplier_name;
  if v_supplier_id is null then raise exception 'المورد غير موجود'; end if;

  v_order_number := 'PO-' || to_char(now(), 'YYYYMMDDHH24MISS');

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_total := v_total + ((v_item->>'price')::numeric * (v_item->>'qty')::numeric);
  end loop;

  v_paid := case when p_payment_status = 'مدفوع بالكامل' then v_total else coalesce(p_amount_paid, 0) end;
  v_remaining := v_total - v_paid;

  insert into purchase_orders (order_number, supplier_id, total, payment_status, amount_paid, remaining, warehouse_id)
  values (v_order_number, v_supplier_id, v_total, p_payment_status, v_paid, v_remaining, p_warehouse_id)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost, quantity into v_variant_id, v_old_cost, v_old_qty from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المتغير غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    v_price := (v_item->>'price')::numeric;

    insert into purchase_order_items (purchase_order_id, variant_id, qty, unit_price) values (v_order_id, v_variant_id, v_qty, v_price);

    if v_method = 'متوسط مرجح' and (coalesce(v_old_qty,0) + v_qty) > 0 then
      v_new_avg_cost := ((coalesce(v_old_qty,0) * coalesce(v_old_cost,0)) + (v_qty * v_price)) / (coalesce(v_old_qty,0) + v_qty);
    else
      v_new_avg_cost := v_price;
    end if;

    update product_variants set quantity = quantity + v_qty, cost = v_new_avg_cost where id = v_variant_id;
    insert into cost_history (variant_id, old_cost, new_cost, quantity, source_ref) values (v_variant_id, v_old_cost, v_new_avg_cost, v_qty, v_order_number);
  end loop;

  if v_paid > 0 then
    perform fn_journal_entry('المخزون', 'الخزينة', v_paid, v_order_number, 'دفعة فورية أوردر شراء ' || v_order_number);
  end if;
  if v_remaining > 0 then
    perform fn_journal_entry('المخزون', 'الموردون', v_remaining, v_order_number, 'رصيد آجل أوردر شراء ' || v_order_number);
  end if;
  if v_paid > 0 then perform fn_move_treasury('خارج', v_paid, p_treasury_account_id, 'أوردر شراء ' || v_order_number); end if;

  perform fn_log_operation('CREATE_PURCHASE_ORDER', jsonb_build_object('order_number', v_order_number, 'total', v_total));
  return query select v_order_id, v_order_number, v_total;
end;
$$;

-- ------------------------------------------------------------
-- 3) rpc_add_expense — النسخة النهائية
-- ------------------------------------------------------------
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

  insert into expenses (expense_date, main_category, sub_category, description, amount, is_recurring, recurrence_days, is_fixed_asset, payment_method, employee_id, bonus, created_by)
  values (p_expense_date, p_main_category, coalesce(p_sub_category,''), coalesce(p_description,''), p_amount, p_is_recurring, p_recurrence_days, p_is_fixed_asset, p_payment_method, p_employee_id, p_bonus, auth.uid())
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

-- ------------------------------------------------------------
-- 4) rpc_add_petty_cash — النسخة النهائية
-- ------------------------------------------------------------
create or replace function rpc_add_petty_cash(p_type text, p_amount numeric, p_description text default '', p_treasury_account_id uuid default null)
returns numeric language plpgsql security definer as $$
declare v_last numeric; v_new numeric; v_ref text;
begin
  perform fn_check_period_open(now());
  if not fn_has_permission('PettyCash', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select balance_after into v_last from petty_cash order by movement_date desc, id desc limit 1;
  v_last := coalesce(v_last, 0);
  v_new := case when p_type = 'إيداع' then v_last + p_amount else v_last - p_amount end;
  if v_new < 0 then raise exception 'رصيد العهدة لا يكفي'; end if;

  insert into petty_cash (type, amount, description, balance_after, created_by) values (p_type, p_amount, p_description, v_new, auth.uid());
  v_ref := 'PC-' || to_char(now(), 'YYYYMMDDHH24MISS');

  if p_type = 'مصروف' then
    perform fn_journal_entry('المصروفات', 'العهدة', p_amount, v_ref, p_description);
  elsif p_type = 'إيداع' then
    perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, 'تمويل العهدة');
    perform fn_journal_entry('العهدة', 'الخزينة', p_amount, v_ref, 'تمويل العهدة');
  elsif p_type = 'سحب' then
    perform fn_move_treasury('داخل', p_amount, p_treasury_account_id, 'استرجاع من العهدة');
    perform fn_journal_entry('الخزينة', 'العهدة', p_amount, v_ref, 'استرجاع من العهدة');
  end if;

  perform fn_log_operation('PETTY_CASH_MOVEMENT', jsonb_build_object('type', p_type, 'amount', p_amount));
  return v_new;
end;
$$;

-- ------------------------------------------------------------
-- 5) rpc_pay_invoice_installment — النسخة النهائية
-- ------------------------------------------------------------
create or replace function rpc_pay_invoice_installment(p_invoice_id uuid, p_amount numeric, p_treasury_account_id uuid default null)
returns void language plpgsql security definer as $$
declare v_total numeric; v_paid numeric; v_new_paid numeric; v_new_remaining numeric; v_number text;
begin
  if not fn_has_permission('Invoices', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select total, paid, invoice_number into v_total, v_paid, v_number from invoices where id = p_invoice_id;
  v_new_paid := v_paid + p_amount;
  v_new_remaining := v_total - v_new_paid;
  if v_new_remaining < 0 then raise exception 'المبلغ أكبر من المتبقي'; end if;

  update invoices set paid = v_new_paid, remaining = v_new_remaining,
    status = case when v_new_remaining = 0 then 'مدفوعة بالكامل' else 'مدفوعة جزئيًا' end
    where id = p_invoice_id;

  perform fn_move_treasury('داخل', p_amount, p_treasury_account_id, 'تحصيل فاتورة ' || v_number);
  perform fn_journal_entry('الخزينة', 'العملاء (مدينون)', p_amount, v_number, 'تحصيل فاتورة ' || v_number);
  perform fn_log_operation('PAY_INVOICE_INSTALLMENT', jsonb_build_object('invoice_id', p_invoice_id, 'amount', p_amount));
end;
$$;

-- ------------------------------------------------------------
-- 6) rpc_pay_supplier_installment — النسخة النهائية
-- ------------------------------------------------------------
create or replace function rpc_pay_supplier_installment(p_order_id uuid, p_amount numeric, p_treasury_account_id uuid default null)
returns void language plpgsql security definer as $$
declare v_total numeric; v_paid numeric; v_new_paid numeric; v_new_remaining numeric; v_order_number text;
begin
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select total, amount_paid, order_number into v_total, v_paid, v_order_number from purchase_orders where id = p_order_id;
  v_new_paid := v_paid + p_amount;
  v_new_remaining := v_total - v_new_paid;
  if v_new_remaining < 0 then raise exception 'المبلغ أكبر من المتبقي'; end if;

  update purchase_orders set amount_paid = v_new_paid, remaining = v_new_remaining,
    payment_status = case when v_new_remaining = 0 then 'مدفوع بالكامل' else 'مدفوع جزئيًا' end
    where id = p_order_id;

  perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, 'دفعة أوردر شراء ' || v_order_number);
  perform fn_journal_entry('الموردون', 'الخزينة', p_amount, v_order_number, 'دفعة أوردر شراء ' || v_order_number);
  perform fn_log_operation('PAY_SUPPLIER_INSTALLMENT', jsonb_build_object('order_id', p_order_id, 'amount', p_amount));
end;
$$;

-- ------------------------------------------------------------
-- 7) rpc_update_check_status — النسخة النهائية
-- ------------------------------------------------------------
create or replace function rpc_update_check_status(p_check_id uuid, p_status text, p_treasury_account_id uuid default null)
returns void language plpgsql security definer as $$
declare v_check record;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  select * into v_check from checks where id = p_check_id;
  if v_check.id is null then raise exception 'الشيك غير موجود'; end if;

  update checks set status = p_status where id = p_check_id;

  if p_status = 'تم التحصيل' then
    perform fn_move_treasury(case when v_check.direction = 'واردة' then 'داخل' else 'خارج' end, v_check.amount, p_treasury_account_id,
      'شيك ' || v_check.check_number || ' — ' || v_check.party_name);
    perform fn_journal_entry(
      case when v_check.direction = 'واردة' then 'الخزينة' else 'شيكات دفع' end,
      case when v_check.direction = 'واردة' then 'شيكات تحصيل' else 'الخزينة' end,
      v_check.amount, v_check.check_number, 'تحصيل شيك ' || v_check.check_number
    );
  end if;

  perform fn_log_operation('UPDATE_CHECK_STATUS', jsonb_build_object('check_id', p_check_id, 'status', p_status));
end;
$$;

-- ------------------------------------------------------------
-- 8) rpc_add_capital_movement — النسخة النهائية (مع تصحيح balance_after)
-- ------------------------------------------------------------
create or replace function rpc_add_capital_movement(
  p_partner_name text, p_type text, p_amount numeric, p_notes text default '', p_treasury_account_id uuid default null
)
returns numeric language plpgsql security definer as $$
declare
  v_partner_id uuid; v_last_balance numeric; v_new_balance numeric; v_total_capital numeric; v_direction text;
begin
  if not fn_has_permission('Capital', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select id, balance into v_partner_id, v_last_balance from partners where name = p_partner_name;
  if v_partner_id is null then
    insert into partners (name, balance) values (p_partner_name, 0) returning id, balance into v_partner_id, v_last_balance;
  end if;

  v_new_balance := v_last_balance + (case when p_type = 'سحب رأس مال' then -abs(p_amount) else abs(p_amount) end);

  insert into capital_movements (partner_id, type, amount, balance_after, notes) values (v_partner_id, p_type, abs(p_amount), v_new_balance, p_notes);
  update partners set balance = v_new_balance where id = v_partner_id;

  select sum(balance) into v_total_capital from partners;
  update partners set ownership_percent = case when v_total_capital > 0 then round((balance / v_total_capital) * 100, 2) else 0 end
  where true;

  v_direction := case when p_type = 'سحب رأس مال' then 'خارج' else 'داخل' end;
  perform fn_move_treasury(v_direction, abs(p_amount), p_treasury_account_id, p_type || ' — ' || p_partner_name);

  perform fn_journal_entry(
    case when v_direction = 'داخل' then 'الخزينة' else 'رأس المال — ' || p_partner_name end,
    case when v_direction = 'داخل' then 'رأس المال — ' || p_partner_name else 'الخزينة' end,
    abs(p_amount), p_partner_name, p_type || ' — ' || p_partner_name
  );

  perform fn_log_operation('ADD_CAPITAL_MOVEMENT', jsonb_build_object('partner', p_partner_name, 'type', p_type, 'amount', p_amount));
  return v_new_balance;
end;
$$;

grant execute on all functions in schema public to authenticated;

-- ------------------------------------------------------------
-- فحص نهائي: تأكيد إن كل دالة من الـ8 بقت نسخة واحدة بس
-- (شغّليه بعد الدفعة دي، المفروض كل دالة تظهر مرة واحدة بس)
-- ------------------------------------------------------------
-- select proname, count(*) from pg_proc where proname in (
--   'rpc_record_sale','rpc_create_purchase_order','rpc_add_expense','rpc_add_petty_cash',
--   'rpc_pay_invoice_installment','rpc_pay_supplier_installment','rpc_update_check_status','rpc_add_capital_movement'
-- ) group by proname;
