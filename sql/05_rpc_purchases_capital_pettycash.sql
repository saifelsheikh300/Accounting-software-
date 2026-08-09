-- ============================================================
-- الجزء 5: المشتريات، رأس المال والشركاء، العهدة، الفواتير
-- ============================================================

-- ------------------------------------------------------------
-- تسجيل أوردر شراء جديد — بيحدّث Latest Cost + المخزون تلقائيًا
-- p_items: [{"variant_code":"...","qty":10,"price":80}, ...]
-- ------------------------------------------------------------
create or replace function rpc_create_purchase_order(
  p_supplier_name text, p_items jsonb, p_payment_status text default 'مدفوع بالكامل',
  p_amount_paid numeric default 0, p_warehouse_id uuid default null
)
returns table(order_id uuid, order_number text, total numeric) language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_old_cost numeric; v_qty numeric; v_price numeric;
  v_total numeric := 0; v_supplier_id uuid; v_order_id uuid; v_order_number text;
  v_paid numeric; v_remaining numeric; v_is_cash boolean;
begin
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

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
    select id, cost into v_variant_id, v_old_cost from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المتغير غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    v_price := (v_item->>'price')::numeric;

    insert into purchase_order_items (purchase_order_id, variant_id, qty, unit_price) values (v_order_id, v_variant_id, v_qty, v_price);

    -- تحديث Latest Cost + سجل تغير التكلفة + إضافة الكمية للمخزون
    update product_variants set quantity = quantity + v_qty, cost = v_price where id = v_variant_id;
    insert into cost_history (variant_id, old_cost, new_cost, quantity, source_ref) values (v_variant_id, v_old_cost, v_price, v_qty, v_order_number);
  end loop;

  v_is_cash := p_payment_status = 'مدفوع بالكامل';
  perform fn_journal_entry('المخزون', case when v_is_cash then 'الخزينة' else 'الموردون' end, v_total, v_order_number, 'أوردر شراء رقم ' || v_order_number);
  if v_paid > 0 then perform fn_append_cash_flow('خارج', 'أوردر شراء ' || v_order_number, v_paid); end if;

  perform fn_log_operation('CREATE_PURCHASE_ORDER', jsonb_build_object('order_number', v_order_number, 'total', v_total));
  return query select v_order_id, v_order_number, v_total;
end;
$$;

create or replace function rpc_pay_supplier_installment(p_order_id uuid, p_amount numeric)
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

  perform fn_append_cash_flow('خارج', 'دفعة أوردر شراء ' || v_order_number, p_amount);
  perform fn_log_operation('PAY_SUPPLIER_INSTALLMENT', jsonb_build_object('order_id', p_order_id, 'amount', p_amount));
end;
$$;

-- ------------------------------------------------------------
-- رأس المال والشركاء — إضافة/سحب + إعادة حساب نسبة الملكية تلقائيًا
-- ------------------------------------------------------------
create or replace function rpc_add_capital_movement(p_partner_name text, p_type text, p_amount numeric, p_notes text default '')
returns numeric language plpgsql security definer as $$
declare v_partner_id uuid; v_last_balance numeric; v_new_balance numeric; v_total_capital numeric;
begin
  if not fn_has_permission('Capital', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select id, balance into v_partner_id, v_last_balance from partners where name = p_partner_name;
  if v_partner_id is null then
    insert into partners (name, balance) values (p_partner_name, 0) returning id, balance into v_partner_id, v_last_balance;
  end if;

  v_new_balance := v_last_balance + (case when p_type = 'سحب رأس مال' then -abs(p_amount) else abs(p_amount) end);

  insert into capital_movements (partner_id, type, amount, balance_after, notes) values (v_partner_id, p_type, abs(p_amount), v_new_balance, p_notes);
  update partners set balance = v_new_balance where id = v_partner_id;

  -- إعادة حساب نسبة الملكية لكل الشركاء
  select sum(balance) into v_total_capital from partners;
  update partners set ownership_percent = case when v_total_capital > 0 then round((balance / v_total_capital) * 100, 2) else 0 end;

  perform fn_log_operation('ADD_CAPITAL_MOVEMENT', jsonb_build_object('partner', p_partner_name, 'type', p_type, 'amount', p_amount));
  return v_new_balance;
end;
$$;

create or replace function rpc_set_partner_rates(p_partner_name text, p_profit_share numeric, p_admin_rate numeric, p_admin_rate_type text)
returns void language plpgsql security definer as $$
begin
  if not fn_has_permission('Capital', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  update partners set profit_share_percent = p_profit_share, admin_rate = p_admin_rate, admin_rate_type = p_admin_rate_type
  where name = p_partner_name;
  perform fn_log_operation('SET_PARTNER_RATES', jsonb_build_object('partner', p_partner_name));
end;
$$;

-- نسبة الإدارة الشهرية التلقائية (تُشغَّل عن طريق Cron شهري — راجع ملف 06)
create or replace function rpc_run_monthly_admin_fee()
returns void language plpgsql security definer as $$
declare
  v_partner record; v_month text := to_char(now(), 'YYYY-MM'); v_fee numeric; v_sales_total numeric;
  v_admin_enabled text;
begin
  select value into v_admin_enabled from settings where key = 'adminFeeEnabled';
  if v_admin_enabled is distinct from 'true' then return; end if;

  select coalesce(sum(total), 0) into v_sales_total from sales where to_char(sale_date, 'YYYY-MM') = v_month and status <> 'مرتجع كلي';

  for v_partner in select * from partners where admin_rate is not null and admin_rate > 0 loop
    v_fee := case when v_partner.admin_rate_type = 'نسبة %' then v_sales_total * (v_partner.admin_rate / 100) else v_partner.admin_rate end;

    insert into expenses (main_category, sub_category, description, amount, is_recurring, recurrence_days, payment_method)
    values ('إدارية', 'نسبة إدارة شريك: ' || v_partner.name, 'نسبة إدارة شهرية — ' || v_month, v_fee, true, 30, 'داخلي');

    insert into admin_rights (partner_id, month_label, earned, available)
    values (v_partner.id, v_month, v_fee, v_fee)
    on conflict (partner_id, month_label) do update set earned = v_fee, available = v_fee - admin_rights.withdrawn;
  end loop;

  perform fn_log_operation('RUN_MONTHLY_ADMIN_FEE', jsonb_build_object('month', v_month));
end;
$$;

-- ------------------------------------------------------------
-- العهدة (Petty Cash)
-- ------------------------------------------------------------
create or replace function rpc_add_petty_cash(p_type text, p_amount numeric, p_description text default '')
returns numeric language plpgsql security definer as $$
declare v_last numeric; v_new numeric;
begin
  if not fn_has_permission('PettyCash', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select balance_after into v_last from petty_cash order by movement_date desc, id desc limit 1;
  v_last := coalesce(v_last, 0);
  v_new := case when p_type = 'إيداع' then v_last + p_amount else v_last - p_amount end;
  if v_new < 0 then raise exception 'رصيد العهدة لا يكفي'; end if;

  insert into petty_cash (type, amount, description, balance_after, created_by) values (p_type, p_amount, p_description, v_new, auth.uid());

  if p_type = 'مصروف' then
    perform fn_journal_entry('المصروفات', 'الخزينة', p_amount, 'PC-' || to_char(now(),'YYYYMMDDHH24MISS'), p_description);
  end if;

  perform fn_log_operation('PETTY_CASH_MOVEMENT', jsonb_build_object('type', p_type, 'amount', p_amount));
  return v_new;
end;
$$;

-- ------------------------------------------------------------
-- الفواتير
-- ------------------------------------------------------------
create or replace function rpc_pay_invoice_installment(p_invoice_id uuid, p_amount numeric)
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

  perform fn_append_cash_flow('داخل', 'تحصيل فاتورة ' || v_number, p_amount);
  perform fn_log_operation('PAY_INVOICE_INSTALLMENT', jsonb_build_object('invoice_id', p_invoice_id, 'amount', p_amount));
end;
$$;
