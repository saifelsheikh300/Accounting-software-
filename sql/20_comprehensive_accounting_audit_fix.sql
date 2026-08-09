-- ============================================================
-- الدفعة 20: فحص محاسبي شامل — إصلاح كل الثغرات الجوهرية
-- 1) تفعيل شجرة الحسابات فعليًا داخل كل قيد محاسبي
-- 2) تقارير مالية مبنية على دفتر اليومية الحقيقي (ميزان مراجعة + ميزانية)
-- 3) مرتجع جزئي بيعكس الإيراد والتكلفة معًا وبدقة
-- 4) الإيرادات الأخرى بقت RPC كامل بقيد وأثر خزنة
-- 5) نسبة إدارة الشركاء بقى ليها قيد + التزام حقيقي + دالة سحب
-- 6) قيد المشتريات الجزئية بينقسم صح بين المدفوع والآجل
-- 7) نقل المخزون بيعيد حساب متوسط التكلفة في المخزن المستقبِل
-- 8) دعم فعلي لتحويل العملات وقت تسجيل البيعة
-- + إهلاك أصول ثابتة، ترحيل أرصدة أول مدة، تقرير مراكز تكلفة،
--   قفل فترات محاسبية، حد أدنى لأرصدة الخزنة
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

-- ------------------------------------------------------------
-- الجزء 1: ربط شجرة الحسابات فعليًا بكل قيد — دالة توليد/إيجاد
-- حساب تلقائيًا حسب الاسم، وتعديل fn_journal_entry عشان تستخدمها
-- ------------------------------------------------------------
create or replace function fn_resolve_account(p_name text)
returns uuid language plpgsql security definer as $$
declare v_id uuid; v_type text;
begin
  if p_name is null or trim(p_name) = '' then return null; end if;
  select id into v_id from accounts where name = p_name;
  if v_id is not null then return v_id; end if;

  v_type := case
    when p_name ilike 'المصروفات%' or p_name ilike 'تكلفة البضاعة%' or p_name ilike '%اهلاك%' or p_name ilike '%إهلاك%' or p_name ilike 'المرتبات%' then 'مصروفات'
    when p_name ilike 'المبيعات%' or p_name ilike '%إيرادات%' then 'إيرادات'
    when p_name ilike '%رأس المال%' then 'حقوق ملكية'
    when p_name ilike '%الموردون%' or p_name ilike '%دائن%' or p_name ilike 'شيكات دفع%' or p_name ilike 'مستحقات%' then 'خصوم'
    else 'أصول'
  end;

  insert into accounts (code, name, type, is_group)
  values ('AUTO-' || substr(md5(p_name || clock_timestamp()::text), 1, 8), p_name, v_type, false)
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function fn_journal_entry(p_debit text, p_credit text, p_amount numeric, p_reference text, p_description text)
returns text language plpgsql security definer as $$
declare v_number text; v_debit_id uuid; v_credit_id uuid;
begin
  v_number := 'JE-' || lpad(nextval('journal_entry_seq')::text, 6, '0');
  v_debit_id := fn_resolve_account(p_debit);
  v_credit_id := fn_resolve_account(p_credit);
  insert into journal_entries (entry_number, description, debit_account, credit_account, debit_account_id, credit_account_id, amount, reference)
  values (v_number, p_description, p_debit, p_credit, v_debit_id, v_credit_id, p_amount, p_reference);
  return v_number;
end;
$$;

-- ------------------------------------------------------------
-- الجزء 2: قفل الفترات المحاسبية — منع أي تعديل على شهر اتقفل
-- ------------------------------------------------------------
create table if not exists accounting_periods (
  id uuid primary key default gen_random_uuid(),
  period_label text unique not null,
  closed boolean not null default false,
  closed_by uuid references profiles(id),
  closed_at timestamptz
);

alter table accounting_periods enable row level security;
drop policy if exists "قراءة عامة periods" on accounting_periods;
create policy "قراءة عامة periods" on accounting_periods for select using (auth.role() = 'authenticated');
drop policy if exists "تعديل بصلاحية periods" on accounting_periods;
create policy "تعديل بصلاحية periods" on accounting_periods for all using (fn_has_permission('Reports','تعديل'));

create or replace function fn_check_period_open(p_date timestamptz)
returns void language plpgsql stable as $$
declare v_closed boolean;
begin
  select closed into v_closed from accounting_periods where period_label = to_char(p_date, 'YYYY-MM');
  if v_closed then raise exception 'الفترة المحاسبية % مقفولة، مينفعش تضيفي عليها', to_char(p_date,'YYYY-MM'); end if;
end;
$$;

create or replace function rpc_close_period(p_period_label text)
returns void language plpgsql security definer as $$
begin
  if not fn_has_permission('Reports','تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  insert into accounting_periods (period_label, closed, closed_by, closed_at) values (p_period_label, true, auth.uid(), now())
    on conflict (period_label) do update set closed = true, closed_by = auth.uid(), closed_at = now();
  perform fn_log_operation('CLOSE_PERIOD', jsonb_build_object('period', p_period_label));
end;
$$;

create or replace function rpc_reopen_period(p_period_label text)
returns void language plpgsql security definer as $$
begin
  if not fn_has_permission('Reports','تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  update accounting_periods set closed = false where period_label = p_period_label;
  perform fn_log_operation('REOPEN_PERIOD', jsonb_build_object('period', p_period_label));
end;
$$;

-- ------------------------------------------------------------
-- الجزء 3: تقارير مالية حقيقية من دفتر اليومية — ميزان المراجعة
-- والميزانية العمومية (كانا مش موجودين خالص من قبل)
-- ------------------------------------------------------------
create or replace function rpc_trial_balance(p_end_date date default current_date)
returns jsonb language plpgsql security definer as $$
declare v_result jsonb;
begin
  if not fn_has_permission('Reports','عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'accountCode', a.code, 'accountName', a.name, 'accountType', a.type,
    'debit', coalesce(d.total,0), 'credit', coalesce(c.total,0),
    'balance', coalesce(d.total,0) - coalesce(c.total,0)
  ) order by a.code), '[]'::jsonb) into v_result
  from accounts a
  left join (select debit_account_id acc, sum(amount) total from journal_entries where entry_date::date <= p_end_date group by 1) d on d.acc = a.id
  left join (select credit_account_id acc, sum(amount) total from journal_entries where entry_date::date <= p_end_date group by 1) c on c.acc = a.id
  where coalesce(d.total,0) <> 0 or coalesce(c.total,0) <> 0;

  return v_result;
end;
$$;

create or replace function rpc_balance_sheet(p_as_of date default current_date)
returns jsonb language plpgsql security definer as $$
declare v_assets jsonb; v_liabilities jsonb; v_equity jsonb; v_net_income numeric;
begin
  if not fn_has_permission('Reports','عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('name', a.name, 'balance', coalesce(d.total,0)-coalesce(c.total,0))), '[]'::jsonb) into v_assets
  from accounts a
  left join (select debit_account_id acc, sum(amount) total from journal_entries where entry_date::date <= p_as_of group by 1) d on d.acc=a.id
  left join (select credit_account_id acc, sum(amount) total from journal_entries where entry_date::date <= p_as_of group by 1) c on c.acc=a.id
  where a.type = 'أصول' and (coalesce(d.total,0)-coalesce(c.total,0)) <> 0;

  select coalesce(jsonb_agg(jsonb_build_object('name', a.name, 'balance', coalesce(c.total,0)-coalesce(d.total,0))), '[]'::jsonb) into v_liabilities
  from accounts a
  left join (select debit_account_id acc, sum(amount) total from journal_entries where entry_date::date <= p_as_of group by 1) d on d.acc=a.id
  left join (select credit_account_id acc, sum(amount) total from journal_entries where entry_date::date <= p_as_of group by 1) c on c.acc=a.id
  where a.type = 'خصوم' and (coalesce(c.total,0)-coalesce(d.total,0)) <> 0;

  select coalesce(jsonb_agg(jsonb_build_object('name', a.name, 'balance', coalesce(c.total,0)-coalesce(d.total,0))), '[]'::jsonb) into v_equity
  from accounts a
  left join (select debit_account_id acc, sum(amount) total from journal_entries where entry_date::date <= p_as_of group by 1) d on d.acc=a.id
  left join (select credit_account_id acc, sum(amount) total from journal_entries where entry_date::date <= p_as_of group by 1) c on c.acc=a.id
  where a.type = 'حقوق ملكية' and (coalesce(c.total,0)-coalesce(d.total,0)) <> 0;

  select coalesce(sum(case when a.type='إيرادات' then coalesce(c.total,0)-coalesce(d.total,0) when a.type='مصروفات' then -(coalesce(d.total,0)-coalesce(c.total,0)) else 0 end), 0)
  into v_net_income
  from accounts a
  left join (select debit_account_id acc, sum(amount) total from journal_entries where entry_date::date <= p_as_of group by 1) d on d.acc=a.id
  left join (select credit_account_id acc, sum(amount) total from journal_entries where entry_date::date <= p_as_of group by 1) c on c.acc=a.id
  where a.type in ('إيرادات','مصروفات');

  return jsonb_build_object('assets', v_assets, 'liabilities', v_liabilities, 'equity', v_equity, 'retainedEarnings', round(v_net_income,2));
end;
$$;

create or replace function rpc_income_statement(p_start date, p_end date)
returns jsonb language plpgsql security definer as $$
declare
  v_sales_acc uuid; v_cogs_acc uuid;
  v_sales numeric; v_cogs numeric; v_expenses numeric; v_other numeric;
  v_tax_enabled text; v_tax_rate numeric;
begin
  if not fn_has_permission('Reports','عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select id into v_sales_acc from accounts where name = 'المبيعات';
  select id into v_cogs_acc from accounts where name = 'تكلفة البضاعة المباعة';

  select coalesce(sum(amount) filter (where credit_account_id = v_sales_acc),0) - coalesce(sum(amount) filter (where debit_account_id = v_sales_acc),0)
  into v_sales from journal_entries where entry_date::date between p_start and p_end;

  select coalesce(sum(amount) filter (where debit_account_id = v_cogs_acc),0) - coalesce(sum(amount) filter (where credit_account_id = v_cogs_acc),0)
  into v_cogs from journal_entries where entry_date::date between p_start and p_end;

  select coalesce(sum(amount) filter (where debit_account_id in (select id from accounts where name ilike 'المصروفات%')),0)
       - coalesce(sum(amount) filter (where credit_account_id in (select id from accounts where name ilike 'المصروفات%')),0)
  into v_expenses from journal_entries where entry_date::date between p_start and p_end;

  select coalesce(sum(amount) filter (where credit_account_id in (select id from accounts where name ilike '%إيرادات أخرى%')),0)
  into v_other from journal_entries where entry_date::date between p_start and p_end;

  select value into v_tax_enabled from settings where key='taxEnabled';
  select value::numeric into v_tax_rate from settings where key='taxRate';

  return jsonb_build_object(
    'totalSales', round(v_sales,2), 'cogs', round(v_cogs,2), 'grossProfit', round(v_sales - v_cogs,2),
    'operatingExpenses', round(v_expenses,2), 'otherRevenue', round(v_other,2),
    'netProfitBeforeTax', round(v_sales - v_cogs - v_expenses + v_other,2),
    'taxEnabled', v_tax_enabled = 'true',
    'tax', case when v_tax_enabled='true' then round(v_sales*(coalesce(v_tax_rate,0)/100),2) else 0 end,
    'netProfitAfterTax', round((v_sales - v_cogs - v_expenses + v_other) - (case when v_tax_enabled='true' then round(v_sales*(coalesce(v_tax_rate,0)/100),2) else 0 end),2)
  );
end;
$$;

-- تحديث بيانات الأرباح في الداشبورد الشهري لتُبنى بنفس منطق دفتر اليومية
create or replace function rpc_get_dashboard_data()
returns jsonb language plpgsql security definer as $$
declare
  v_month_start date := date_trunc('month', now());
  v_month_end date := (date_trunc('month', now()) + interval '1 month - 1 day')::date;
  v_sales_total numeric; v_sales_online numeric; v_sales_store numeric; v_sales_count int;
  v_cogs numeric; v_expenses_total numeric; v_other_revenue numeric;
  v_treasury_total numeric; v_treasury_cash numeric; v_treasury_bank numeric;
  v_petty_cash numeric; v_low_stock jsonb; v_recent_ops jsonb; v_partners jsonb;
  v_receivables numeric; v_payables numeric; v_low_stock_count int;
  v_sales_acc uuid; v_cogs_acc uuid;
begin
  select coalesce(sum(total),0), coalesce(sum(total) filter (where source='أونلاين'),0),
         coalesce(sum(total) filter (where source='محل'),0), count(*)
  into v_sales_total, v_sales_online, v_sales_store, v_sales_count
  from sales where sale_date::date between v_month_start and v_month_end and status <> 'مرتجع كلي';

  select id into v_sales_acc from accounts where name = 'المبيعات';
  select id into v_cogs_acc from accounts where name = 'تكلفة البضاعة المباعة';

  select coalesce(sum(amount) filter (where debit_account_id = v_cogs_acc),0) - coalesce(sum(amount) filter (where credit_account_id = v_cogs_acc),0)
  into v_cogs from journal_entries where entry_date::date between v_month_start and v_month_end;

  select coalesce(sum(amount) filter (where debit_account_id in (select id from accounts where name ilike 'المصروفات%')),0)
       - coalesce(sum(amount) filter (where credit_account_id in (select id from accounts where name ilike 'المصروفات%')),0)
  into v_expenses_total from journal_entries where entry_date::date between v_month_start and v_month_end;

  select coalesce(sum(amount) filter (where credit_account_id in (select id from accounts where name ilike '%إيرادات أخرى%')),0)
  into v_other_revenue from journal_entries where entry_date::date between v_month_start and v_month_end;

  select balance_after into v_treasury_total from cash_flow order by flow_date desc, id desc limit 1;
  v_treasury_total := coalesce(v_treasury_total, 0);
  select coalesce(sum(amount),0) into v_treasury_cash from cash_flow where is_cash = true and direction='داخل';
  v_treasury_cash := v_treasury_cash - coalesce((select sum(amount) from cash_flow where is_cash=true and direction='خارج'),0);
  v_treasury_bank := v_treasury_total - v_treasury_cash;

  select balance_after into v_petty_cash from petty_cash order by movement_date desc, id desc limit 1;
  v_petty_cash := coalesce(v_petty_cash, 0);

  select coalesce(sum(remaining), 0) into v_receivables from invoices;
  select coalesce(sum(remaining), 0) into v_payables from purchase_orders;

  select count(*) into v_low_stock_count from product_variants where status = 'نشط' and quantity <= low_stock_threshold and deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
      'productName', p.name, 'variantCode', pv.code, 'color', pv.color, 'size', pv.size, 'quantity', pv.quantity
    )), '[]'::jsonb) into v_low_stock
  from product_variants pv join products p on p.id = pv.product_id
  where pv.status = 'نشط' and pv.quantity <= pv.low_stock_threshold and pv.deleted_at is null limit 15;

  select coalesce(jsonb_agg(jsonb_build_object('time', logged_at, 'username', actor, 'operation', operation) order by logged_at desc), '[]'::jsonb)
    into v_recent_ops from (select * from operations_log order by logged_at desc limit 10) t;

  select coalesce(jsonb_agg(jsonb_build_object(
      'name', name, 'ownershipPercent', ownership_percent, 'profitSharePercent', profit_share_percent,
      'share', case when profit_share_percent is not null then
        ((v_sales_total - v_cogs - v_expenses_total + v_other_revenue) * (profit_share_percent/100)) else 0 end
    )), '[]'::jsonb) into v_partners from partners;

  return jsonb_build_object(
    'sales', jsonb_build_object('total', v_sales_total, 'online', v_sales_online, 'store', v_sales_store, 'count', v_sales_count),
    'expenses', jsonb_build_object('total', v_expenses_total),
    'profit', jsonb_build_object(
      'grossProfit', v_sales_total - v_cogs,
      'netProfit', v_sales_total - v_cogs - v_expenses_total + v_other_revenue,
      'gpMargin', case when v_sales_total>0 then round(((v_sales_total-v_cogs)/v_sales_total)*100,2) else 0 end,
      'npMargin', case when v_sales_total>0 then round(((v_sales_total-v_cogs-v_expenses_total+v_other_revenue)/v_sales_total)*100,2) else 0 end
    ),
    'partnersShares', v_partners,
    'treasury', jsonb_build_object('total', v_treasury_total, 'cash', v_treasury_cash, 'bank', v_treasury_bank),
    'pettyCash', v_petty_cash,
    'receivables', v_receivables,
    'payables', v_payables,
    'lowStockAlerts', v_low_stock,
    'lowStockCount', v_low_stock_count,
    'recentOperations', v_recent_ops,
    'couponImpact', jsonb_build_object('totalDiscount', 0, 'ordersWithCoupon', 0)
  );
end;
$$;

-- ------------------------------------------------------------
-- الجزء 4: حد أدنى لأرصدة الخزنة/البنوك (زي العهدة بالظبط)
-- ------------------------------------------------------------
alter table treasury_accounts add column if not exists allow_negative boolean not null default false;

create or replace function fn_move_treasury(p_direction text, p_amount numeric, p_treasury_account_id uuid, p_source text)
returns void language plpgsql security definer as $$
declare v_is_cash boolean; v_name text; v_last_balance numeric; v_new_balance numeric; v_current numeric; v_allow_neg boolean;
begin
  if p_amount is null or p_amount <= 0 then return; end if;

  select balance_after into v_last_balance from cash_flow order by flow_date desc, id desc limit 1;
  v_last_balance := coalesce(v_last_balance, 0);
  v_new_balance := case when p_direction = 'داخل' then v_last_balance + p_amount else v_last_balance - p_amount end;

  if p_treasury_account_id is not null then
    select (type = 'كاش'), name, current_balance, allow_negative into v_is_cash, v_name, v_current, v_allow_neg from treasury_accounts where id = p_treasury_account_id;
    if v_name is null then raise exception 'حساب الخزنة/البنك غير موجود'; end if;

    if p_direction = 'خارج' and not v_allow_neg and (v_current - p_amount) < 0 then
      raise exception 'رصيد حساب % لا يكفي — المتاح: %', v_name, v_current;
    end if;

    update treasury_accounts set current_balance = current_balance + (case when p_direction = 'داخل' then p_amount else -p_amount end)
    where id = p_treasury_account_id;

    insert into cash_flow (direction, source, amount, treasury_account_id, is_cash, balance_after)
    values (p_direction, p_source, p_amount, p_treasury_account_id, v_is_cash, v_new_balance);
  else
    perform fn_append_cash_flow(p_direction, p_source, p_amount, true);
  end if;
end;
$$;

-- ------------------------------------------------------------
-- الجزء 5: البيع — قفل فترة + دعم عملة حقيقي (تحويل للعملة
-- الأساسية وقت التسجيل بدل ما يفضل الرقم بالعملة الأجنبية زي ما هو)
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
-- الجزء 6: مرتجع البيعة — بيعكس الإيراد والتكلفة معًا بدقة
-- (كان بيعكس الإيراد بس، والتكلفة (COGS) مكانتش بترجع خالص)
-- ------------------------------------------------------------
create or replace function rpc_record_return(p_sale_id uuid, p_items jsonb, p_is_full boolean default true, p_treasury_account_id uuid default null)
returns void language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_qty numeric; v_total numeric := 0; v_total_cogs numeric := 0;
  v_sale_number text; v_payment_method text; v_is_cash boolean; v_unit_cost numeric; v_sale_date timestamptz;
begin
  if not fn_has_permission('Sales', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select sale_number, payment_method, sale_date into v_sale_number, v_payment_method, v_sale_date from sales where id = p_sale_id;
  if v_sale_number is null then raise exception 'البيعة غير موجودة'; end if;
  perform fn_check_period_open(now());
  v_is_cash := v_payment_method is not null and v_payment_method <> 'آجل';

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id into v_variant_id from product_variants where code = v_item->>'variant_code';
    v_qty := (v_item->>'qty')::numeric;

    select unit_cost into v_unit_cost from sale_items where sale_id = p_sale_id and variant_id = v_variant_id limit 1;
    v_unit_cost := coalesce(v_unit_cost, 0);

    update product_variants set quantity = quantity + v_qty where id = v_variant_id;
    v_total := v_total + (coalesce((v_item->>'price')::numeric, 0) * v_qty);
    v_total_cogs := v_total_cogs + (v_unit_cost * v_qty);
  end loop;

  update sales set status = case when p_is_full then 'مرتجع كلي' else 'مرتجع جزئي' end where id = p_sale_id;

  perform fn_journal_entry('المبيعات', case when v_is_cash then 'الخزينة' else 'العملاء (مدينون)' end, v_total, v_sale_number, 'مرتجع بيعة ' || v_sale_number);
  if v_total_cogs > 0 then
    perform fn_journal_entry('المخزون', 'تكلفة البضاعة المباعة', v_total_cogs, v_sale_number, 'عكس تكلفة بضاعة مرتجع ' || v_sale_number);
  end if;

  if v_is_cash then
    perform fn_move_treasury('خارج', v_total, p_treasury_account_id, 'مرتجع بيعة ' || v_sale_number);
  end if;

  perform fn_log_operation('RECORD_RETURN', jsonb_build_object('sale_number', v_sale_number, 'was_cash', v_is_cash, 'cogs_reversed', v_total_cogs));
end;
$$;

-- ------------------------------------------------------------
-- الجزء 7: فاتورة الحساب المفتوح — نفس حماية الفترة
-- ------------------------------------------------------------
create or replace function rpc_add_items_to_invoice(p_invoice_id uuid, p_items jsonb, p_warehouse_id uuid default null)
returns jsonb language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_cost numeric; v_price numeric; v_qty numeric; v_avail_qty numeric;
  v_subtotal numeric := 0; v_total_cogs numeric := 0; v_sale_id uuid; v_sale_number text;
  v_customer_name text; v_customer_phone text; v_paid numeric;
  v_new_total numeric; v_new_remaining numeric; v_new_status text;
begin
  perform fn_check_period_open(now());
  if not fn_has_permission('Invoices', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

  select customer_name, customer_phone, paid into v_customer_name, v_customer_phone, v_paid from invoices where id = p_invoice_id;
  if v_customer_name is null then raise exception 'الفاتورة غير موجودة'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, quantity into v_variant_id, v_avail_qty from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    if v_avail_qty < v_qty then raise exception 'الكمية غير كافية للصنف % — المتاح فعليًا: %', v_item->>'variant_code', v_avail_qty; end if;
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
    v_total_cogs := v_total_cogs + (coalesce(v_cost, 0) * v_qty);
  end loop;

  perform fn_journal_entry('العملاء (مدينون)', 'المبيعات', v_subtotal, v_sale_number, 'إضافة أصناف لفاتورة');
  if v_total_cogs > 0 then
    perform fn_journal_entry('تكلفة البضاعة المباعة', 'المخزون', v_total_cogs, v_sale_number, 'تكلفة بضاعة فاتورة');
  end if;

  select coalesce(sum(total), 0) into v_new_total from sales where invoice_id = p_invoice_id;
  v_new_remaining := v_new_total - v_paid;
  v_new_status := case when v_new_remaining <= 0 then 'مدفوعة بالكامل' when v_paid > 0 then 'مدفوعة جزئيًا' else 'مفتوحة' end;

  update invoices set total = v_new_total, remaining = v_new_remaining, status = v_new_status where id = p_invoice_id;

  perform fn_log_operation('ADD_ITEMS_TO_INVOICE', jsonb_build_object('invoice_id', p_invoice_id, 'sale_number', v_sale_number, 'added', v_subtotal));
  return jsonb_build_object('saleNumber', v_sale_number, 'addedTotal', v_subtotal, 'invoiceTotal', v_new_total, 'invoiceRemaining', v_new_remaining);
end;
$$;

-- ------------------------------------------------------------
-- الجزء 8: الإيرادات الأخرى — كانت جدول فاضي من غير أي دالة
-- ولا قيد محاسبي ولا أثر على الخزنة خالص
-- ------------------------------------------------------------
create or replace function rpc_add_other_revenue(p_source text, p_amount numeric, p_description text default '', p_treasury_account_id uuid default null)
returns uuid language plpgsql security definer as $$
declare v_id uuid;
begin
  perform fn_check_period_open(now());
  if not fn_has_permission('Expenses', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'المبلغ لازم يكون أكبر من صفر'; end if;

  insert into other_revenue (source, description, amount, created_by) values (p_source, coalesce(p_description,''), p_amount, auth.uid())
  returning id into v_id;

  perform fn_move_treasury('داخل', p_amount, p_treasury_account_id, coalesce(nullif(p_description,''), p_source));
  perform fn_journal_entry('الخزينة', 'إيرادات أخرى — ' || p_source, p_amount, p_source, coalesce(nullif(p_description,''), p_source));

  perform fn_log_operation('ADD_OTHER_REVENUE', jsonb_build_object('source', p_source, 'amount', p_amount));
  return v_id;
end;
$$;

-- ------------------------------------------------------------
-- الجزء 9: نسبة إدارة الشركاء — كانت بتتسجل كمصروف من غير أي
-- أثر خزنة أو قيد محاسبي، ومفيش دالة أصلًا تسحبها فعليًا
-- ------------------------------------------------------------
create or replace function rpc_run_monthly_admin_fee()
returns void language plpgsql security definer as $$
declare
  v_partner record; v_month text := to_char(now(), 'YYYY-MM'); v_fee numeric; v_sales_total numeric; v_admin_enabled text;
begin
  select value into v_admin_enabled from settings where key = 'adminFeeEnabled';
  if v_admin_enabled is distinct from 'true' then return; end if;

  select coalesce(sum(total), 0) into v_sales_total from sales where to_char(sale_date, 'YYYY-MM') = v_month and status <> 'مرتجع كلي';

  for v_partner in select * from partners where admin_rate is not null and admin_rate > 0 loop
    v_fee := case when v_partner.admin_rate_type = 'نسبة %' then v_sales_total * (v_partner.admin_rate / 100) else v_partner.admin_rate end;

    insert into expenses (main_category, sub_category, description, amount, is_recurring, recurrence_days, payment_method)
    values ('إدارية', 'نسبة إدارة شريك: ' || v_partner.name, 'نسبة إدارة شهرية — ' || v_month, v_fee, true, 30, 'آجل');

    perform fn_journal_entry('المصروفات: نسبة إدارة', 'مستحقات إدارة — ' || v_partner.name, v_fee, v_partner.name, 'نسبة إدارة شهرية — ' || v_month);

    insert into admin_rights (partner_id, month_label, earned, available)
    values (v_partner.id, v_month, v_fee, v_fee)
    on conflict (partner_id, month_label) do update set earned = v_fee, available = v_fee - admin_rights.withdrawn;
  end loop;

  perform fn_log_operation('RUN_MONTHLY_ADMIN_FEE', jsonb_build_object('month', v_month));
end;
$$;

create or replace function rpc_withdraw_admin_right(p_partner_name text, p_amount numeric, p_treasury_account_id uuid default null)
returns void language plpgsql security definer as $$
declare v_partner_id uuid; v_available numeric; v_oldest_id uuid;
begin
  if not fn_has_permission('Capital','تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  select id into v_partner_id from partners where name = p_partner_name;
  if v_partner_id is null then raise exception 'الشريك غير موجود'; end if;

  select coalesce(sum(available),0) into v_available from admin_rights where partner_id = v_partner_id;
  if p_amount > v_available then raise exception 'المبلغ أكبر من المستحق المتاح'; end if;

  select id into v_oldest_id from admin_rights where partner_id = v_partner_id and available > 0 order by month_label limit 1;
  update admin_rights set withdrawn = withdrawn + p_amount, available = available - p_amount, last_withdrawal_at = now() where id = v_oldest_id;

  perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, 'سحب نسبة إدارة — ' || p_partner_name);
  perform fn_journal_entry('مستحقات إدارة — ' || p_partner_name, 'الخزينة', p_amount, p_partner_name, 'سحب نسبة إدارة');
  perform fn_log_operation('WITHDRAW_ADMIN_RIGHT', jsonb_build_object('partner', p_partner_name, 'amount', p_amount));
end;
$$;

-- ------------------------------------------------------------
-- الجزء 10: قيد المشتريات الجزئية — كان بيسجل كل المبلغ على
-- "الموردون" حتى لو جزء اتدفع فعليًا من الخزنة وقت الإنشاء
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
-- الجزء 11: نقل المخزون — بقى بيعيد حساب متوسط التكلفة في
-- المخزن المستقبِل بدل ما يزوّد الكمية بس ويسيب التكلفة القديمة
-- ------------------------------------------------------------
create or replace function rpc_transfer_stock(p_from_warehouse_id uuid, p_to_warehouse_id uuid, p_items jsonb, p_notes text default '')
returns table(transfer_id uuid, transfer_number text) language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_qty numeric; v_transfer_id uuid; v_transfer_number text;
  v_variant record; v_dest_variant_id uuid; v_dest_qty numeric; v_dest_cost numeric; v_new_avg_cost numeric;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;
  if p_from_warehouse_id = p_to_warehouse_id then raise exception 'اختاري مخزنين مختلفين'; end if;

  v_transfer_number := 'TR-' || to_char(now(), 'YYYYMMDDHH24MISS');
  insert into stock_transfers (transfer_number, from_warehouse_id, to_warehouse_id, notes, created_by)
  values (v_transfer_number, p_from_warehouse_id, p_to_warehouse_id, p_notes, auth.uid())
  returning id into v_transfer_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_variant from product_variants where code = v_item->>'variant_code' and warehouse_id = p_from_warehouse_id;
    if v_variant.id is null then raise exception 'المتغير غير موجود في المخزن المصدر: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    if v_variant.quantity < v_qty then raise exception 'الكمية غير كافية للصنف: %', v_item->>'variant_code'; end if;

    insert into stock_transfer_items (transfer_id, variant_id, qty) values (v_transfer_id, v_variant.id, v_qty);
    update product_variants set quantity = quantity - v_qty where id = v_variant.id;

    select id, quantity, cost into v_dest_variant_id, v_dest_qty, v_dest_cost
    from product_variants where code = v_variant.code || '-' || (select left(w.name,3) from warehouses w where w.id = p_to_warehouse_id);

    if v_dest_variant_id is not null then
      v_new_avg_cost := ((coalesce(v_dest_qty,0) * coalesce(v_dest_cost,0)) + (v_qty * v_variant.cost)) / nullif(coalesce(v_dest_qty,0) + v_qty, 0);
      update product_variants set quantity = quantity + v_qty, cost = coalesce(v_new_avg_cost, v_variant.cost) where id = v_dest_variant_id;
      insert into cost_history (variant_id, old_cost, new_cost, quantity, source_ref) values (v_dest_variant_id, v_dest_cost, coalesce(v_new_avg_cost, v_variant.cost), v_qty, v_transfer_number);
    else
      insert into product_variants (code, product_id, color, size, quantity, cost, special_price, warehouse_id, low_stock_threshold)
      values (v_variant.code || '-' || (select left(w.name,3) from warehouses w where w.id = p_to_warehouse_id),
              v_variant.product_id, v_variant.color, v_variant.size, v_qty, v_variant.cost, v_variant.special_price, p_to_warehouse_id, v_variant.low_stock_threshold);
    end if;
  end loop;

  perform fn_log_operation('TRANSFER_STOCK', jsonb_build_object('transfer_number', v_transfer_number));
  return query select v_transfer_id, v_transfer_number;
end;
$$;

-- ------------------------------------------------------------
-- الجزء 12: إهلاك الأصول الثابتة — الجدول كان موجود من غير أي
-- آلية إهلاك خالص
-- ------------------------------------------------------------
alter table fixed_assets add column if not exists useful_life_months int default 36;
alter table fixed_assets add column if not exists accumulated_depreciation numeric(12,2) not null default 0;

create or replace function rpc_run_monthly_depreciation()
returns void language plpgsql security definer as $$
declare v_asset record; v_monthly numeric; v_month text := to_char(now(),'YYYY-MM');
begin
  if not fn_has_permission('Reports','تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  for v_asset in select * from fixed_assets where accumulated_depreciation < amount loop
    v_monthly := least(round(v_asset.amount / greatest(v_asset.useful_life_months,1), 2), v_asset.amount - v_asset.accumulated_depreciation);
    if v_monthly > 0 then
      update fixed_assets set accumulated_depreciation = accumulated_depreciation + v_monthly where id = v_asset.id;
      perform fn_journal_entry('المصروفات: إهلاك', 'مجمع إهلاك الأصول', v_monthly, v_asset.id::text, 'إهلاك شهري — ' || coalesce(v_asset.description,'') || ' — ' || v_month);
    end if;
  end loop;

  perform fn_log_operation('RUN_MONTHLY_DEPRECIATION', jsonb_build_object('month', v_month));
end;
$$;

-- ------------------------------------------------------------
-- الجزء 13: ترحيل أرصدة أول مدة فعليًا لدفتر اليومية — كانت
-- بتتسجل في جدولها بس من غير أي أثر محاسبي حقيقي
-- ------------------------------------------------------------
create or replace function rpc_post_opening_balances()
returns void language plpgsql security definer as $$
declare v_row record; v_equity_account text := 'رصيد افتتاحي';
begin
  if not fn_has_permission('Reports','تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  for v_row in select ob.*, a.name as account_name, a.type as account_type from opening_balances ob join accounts a on a.id = ob.account_id where ob.locked = false loop
    if v_row.account_type in ('أصول','مصروفات') then
      perform fn_journal_entry(v_row.account_name, v_equity_account, v_row.amount, 'OB-' || v_row.id::text, 'رصيد افتتاحي — ' || coalesce(v_row.description,''));
    else
      perform fn_journal_entry(v_equity_account, v_row.account_name, v_row.amount, 'OB-' || v_row.id::text, 'رصيد افتتاحي — ' || coalesce(v_row.description,''));
    end if;
  end loop;

  update opening_balances set locked = true where locked = false;
  perform fn_log_operation('POST_OPENING_BALANCES', '{}'::jsonb);
end;
$$;

-- ------------------------------------------------------------
-- الجزء 14: تقرير مراكز التكلفة — كانت مربوطة بالجداول من غير
-- أي تقرير فعلي يستخدمها
-- ------------------------------------------------------------
create or replace function rpc_cost_center_report(p_start date, p_end date)
returns jsonb language plpgsql security definer as $$
declare v_result jsonb;
begin
  if not fn_has_permission('Reports','عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'costCenter', cc.name, 'sales', coalesce(s.total,0), 'expenses', coalesce(e.total,0), 'net', coalesce(s.total,0)-coalesce(e.total,0)
  )), '[]'::jsonb) into v_result
  from cost_centers cc
  left join (select cost_center_id, sum(total) total from sales where sale_date::date between p_start and p_end and status <> 'مرتجع كلي' group by 1) s on s.cost_center_id = cc.id
  left join (select cost_center_id, sum(amount) total from expenses where expense_date::date between p_start and p_end group by 1) e on e.cost_center_id = cc.id;

  return v_result;
end;
$$;

-- ------------------------------------------------------------
-- الجزء 15: قفل الفترات على المصروفات والعهدة كمان
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

grant execute on all functions in schema public to authenticated;
