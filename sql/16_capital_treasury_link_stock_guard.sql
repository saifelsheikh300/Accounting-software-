-- ============================================================
-- الدفعة 16: إصلاحان مهمان
-- 1) إضافة/سحب رأس المال دلوقتي بيأثر فعليًا على رصيد الخزنة/البنك
--    اللي تختاريه (بدل ما يفضل رصيد الشريك بس من غير أي تأثير مالي)
-- 2) منع البيع (من الكاشير/المبيعات/الفواتير) بكمية أكبر من
--    المتاح فعليًا في المخزون — بيوقف برسالة واضحة بدل ما يدخل بالسالب
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

-- ------------------------------------------------------------
-- 1) رأس المال: ربطه بحساب خزنة/بنك حقيقي
-- ------------------------------------------------------------
create or replace function rpc_add_capital_movement(
  p_partner_name text, p_type text, p_amount numeric, p_notes text default '', p_treasury_account_id uuid default null
)
returns numeric language plpgsql security definer as $$
declare
  v_partner_id uuid; v_last_balance numeric; v_new_balance numeric; v_total_capital numeric;
  v_treasury_name text; v_is_cash boolean; v_direction text;
begin
  if not fn_has_permission('Capital', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select id, balance into v_partner_id, v_last_balance from partners where name = p_partner_name;
  if v_partner_id is null then
    insert into partners (name, balance) values (p_partner_name, 0) returning id, balance into v_partner_id, v_last_balance;
  end if;

  v_new_balance := v_last_balance + (case when p_type = 'سحب رأس مال' then -abs(p_amount) else abs(p_amount) end);

  insert into capital_movements (partner_id, type, amount, balance_after, notes) values (v_partner_id, p_type, abs(p_amount), v_new_balance, p_notes);
  update partners set balance = v_new_balance where id = v_partner_id;

  -- إعادة حساب نسبة الملكية لكل الشركاء (where true عشان Supabase محتاج شرط WHERE دايمًا)
  select sum(balance) into v_total_capital from partners;
  update partners set ownership_percent = case when v_total_capital > 0 then round((balance / v_total_capital) * 100, 2) else 0 end
  where true;

  -- تأثير الخزنة الفعلي: إضافة رأس مال بتزوّد الخزنة، سحب رأس مال بيقلل منها
  v_direction := case when p_type = 'سحب رأس مال' then 'خارج' else 'داخل' end;

  if p_treasury_account_id is not null then
    select name, (type = 'كاش') into v_treasury_name, v_is_cash from treasury_accounts where id = p_treasury_account_id;
    if v_treasury_name is null then raise exception 'حساب الخزنة/البنك غير موجود'; end if;

    update treasury_accounts set current_balance = current_balance + (case when v_direction = 'داخل' then abs(p_amount) else -abs(p_amount) end)
    where id = p_treasury_account_id;

    insert into cash_flow (direction, source, amount, treasury_account_id, is_cash, reconciliation_note)
    values (v_direction, p_type || ' — ' || p_partner_name, abs(p_amount), p_treasury_account_id, v_is_cash, p_notes);
  else
    -- لو مفيش حساب خزنة محدد، تتسجل كحركة كاش عامة (نظام الخزنة الموحد القديم)
    perform fn_append_cash_flow(v_direction, p_type || ' — ' || p_partner_name, abs(p_amount), true);
  end if;

  perform fn_journal_entry(
    case when v_direction = 'داخل' then 'الخزينة' else 'رأس المال — ' || p_partner_name end,
    case when v_direction = 'داخل' then 'رأس المال — ' || p_partner_name else 'الخزينة' end,
    abs(p_amount), p_partner_name, p_type || ' — ' || p_partner_name
  );

  perform fn_log_operation('ADD_CAPITAL_MOVEMENT', jsonb_build_object('partner', p_partner_name, 'type', p_type, 'amount', p_amount));
  return v_new_balance;
end;
$$;

-- ------------------------------------------------------------
-- 2) البيع العادي (كاشير/مبيعات): رفض البيع لو الكمية المطلوبة
-- أكبر من المتاح فعليًا في أي صنف — قبل ما يتسجل أي حاجة خالص
-- ------------------------------------------------------------
create or replace function rpc_record_sale(
  p_source text, p_items jsonb, p_discount numeric default 0, p_payment_method text default null,
  p_invoice_id uuid default null, p_customer_name text default '', p_customer_phone text default '',
  p_warehouse_id uuid default null, p_sale_date timestamptz default now()
)
returns table(sale_id uuid, sale_number text, total numeric) language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_cost numeric; v_price numeric; v_qty numeric; v_avail_qty numeric;
  v_subtotal numeric := 0; v_total numeric; v_sale_id uuid; v_sale_number text;
  v_is_cash boolean;
begin
  if not fn_has_permission('Sales', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم منتج واحد على الأقل'; end if;

  v_sale_number := 'S-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || floor(random()*900+100)::text;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost, quantity into v_variant_id, v_cost, v_avail_qty from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    if v_avail_qty < v_qty then
      raise exception 'الكمية غير كافية للصنف % — المتاح فعليًا: %', v_item->>'variant_code', v_avail_qty;
    end if;
    v_price := coalesce((v_item->>'price')::numeric, 0);
    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  v_total := v_subtotal - coalesce(p_discount, 0);
  v_is_cash := p_payment_method is not null and p_payment_method <> 'آجل';

  insert into sales (sale_number, sale_date, source, subtotal, discount, total, payment_method, invoice_id, customer_name, customer_phone, warehouse_id, created_by)
  values (v_sale_number, p_sale_date, p_source, v_subtotal, coalesce(p_discount,0), v_total, p_payment_method, p_invoice_id, p_customer_name, p_customer_phone, p_warehouse_id, auth.uid())
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost into v_variant_id, v_cost from product_variants where code = v_item->>'variant_code';
    v_qty := (v_item->>'qty')::numeric;
    v_price := coalesce((v_item->>'price')::numeric, 0);

    insert into sale_items (sale_id, variant_id, qty, unit_price, unit_cost) values (v_sale_id, v_variant_id, v_qty, v_price, v_cost);

    update product_variants set quantity = quantity - v_qty where id = v_variant_id;
  end loop;

  perform fn_journal_entry(case when v_is_cash then 'الخزينة' else 'العملاء (مدينون)' end, 'المبيعات', v_total, v_sale_number, 'بيعة رقم ' || v_sale_number);
  if v_is_cash then perform fn_append_cash_flow('داخل', 'بيعة ' || v_sale_number, v_total, p_payment_method = 'كاش'); end if;

  if p_customer_phone is not null and p_customer_phone <> '' then
    insert into customers (phone, name, order_count, total_purchases, first_order_at)
    values (p_customer_phone, p_customer_name, 1, v_total, now())
    on conflict (phone) do update set
      order_count = customers.order_count + 1,
      total_purchases = customers.total_purchases + v_total,
      name = coalesce(nullif(excluded.name, ''), customers.name);
  end if;

  perform fn_log_operation('RECORD_SALE', jsonb_build_object('sale_number', v_sale_number, 'total', v_total));
  return query select v_sale_id, v_sale_number, v_total;
end;
$$;

-- ------------------------------------------------------------
-- 3) إضافة أصناف لفاتورة عميل: نفس الحماية بالظبط
-- ------------------------------------------------------------
create or replace function rpc_add_items_to_invoice(p_invoice_id uuid, p_items jsonb, p_warehouse_id uuid default null)
returns jsonb language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_cost numeric; v_price numeric; v_qty numeric; v_avail_qty numeric;
  v_subtotal numeric := 0; v_sale_id uuid; v_sale_number text;
  v_customer_name text; v_customer_phone text; v_paid numeric;
  v_new_total numeric; v_new_remaining numeric; v_new_status text;
begin
  if not fn_has_permission('Invoices', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

  select customer_name, customer_phone, paid into v_customer_name, v_customer_phone, v_paid from invoices where id = p_invoice_id;
  if v_customer_name is null then raise exception 'الفاتورة غير موجودة'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, quantity into v_variant_id, v_avail_qty from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    if v_avail_qty < v_qty then
      raise exception 'الكمية غير كافية للصنف % — المتاح فعليًا: %', v_item->>'variant_code', v_avail_qty;
    end if;
    v_price := coalesce((v_item->>'price')::numeric, 0);
    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  v_sale_number := 'S-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || floor(random() * 900 + 100)::text;

  insert into sales (sale_number, source, subtotal, discount, total, payment_method, invoice_id, customer_name, customer_phone, warehouse_id, created_by)
  values (v_sale_number, 'محل', v_subtotal, 0, v_subtotal, 'آجل', p_invoice_id, v_customer_name, v_customer_phone, p_warehouse_id, auth.uid())
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost into v_variant_id, v_cost from product_variants where code = v_item->>'variant_code';
    v_qty := (v_item->>'qty')::numeric;
    v_price := coalesce((v_item->>'price')::numeric, 0);

    insert into sale_items (sale_id, variant_id, qty, unit_price, unit_cost) values (v_sale_id, v_variant_id, v_qty, v_price, v_cost);
    update product_variants set quantity = quantity - v_qty where id = v_variant_id;
  end loop;

  perform fn_journal_entry('العملاء (مدينون)', 'المبيعات', v_subtotal, v_sale_number, 'إضافة أصناف لفاتورة');

  select coalesce(sum(total), 0) into v_new_total from sales where invoice_id = p_invoice_id;
  v_new_remaining := v_new_total - v_paid;
  v_new_status := case when v_new_remaining <= 0 then 'مدفوعة بالكامل' when v_paid > 0 then 'مدفوعة جزئيًا' else 'مفتوحة' end;

  update invoices set total = v_new_total, remaining = v_new_remaining, status = v_new_status where id = p_invoice_id;

  perform fn_log_operation('ADD_ITEMS_TO_INVOICE', jsonb_build_object('invoice_id', p_invoice_id, 'sale_number', v_sale_number, 'added', v_subtotal));
  return jsonb_build_object('saleNumber', v_sale_number, 'addedTotal', v_subtotal, 'invoiceTotal', v_new_total, 'invoiceRemaining', v_new_remaining);
end;
$$;

grant execute on all functions in schema public to authenticated;
