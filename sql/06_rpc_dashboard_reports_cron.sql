-- ============================================================
-- الجزء 6: الداشبورد المجمّع (نداء واحد بس للسرعة) + التقارير
-- + الجدولة التلقائية (pg_cron) بدل Triggers يدوية زي Apps Script
-- ============================================================

-- ------------------------------------------------------------
-- كل بيانات الداشبورد في نداء واحد (Batch حقيقي على مستوى الداتابيز)
-- ده بديل getDashboardData() القديمة، وبيرجع JSON واحد جاهز للعرض
-- ------------------------------------------------------------
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
begin
  select coalesce(sum(total),0), coalesce(sum(total) filter (where source='أونلاين'),0),
         coalesce(sum(total) filter (where source='محل'),0), count(*)
  into v_sales_total, v_sales_online, v_sales_store, v_sales_count
  from sales where sale_date::date between v_month_start and v_month_end and status <> 'مرتجع كلي';

  select coalesce(sum(si.qty * si.unit_cost),0) into v_cogs
  from sale_items si join sales s on s.id = si.sale_id
  where s.sale_date::date between v_month_start and v_month_end and s.status <> 'مرتجع كلي';

  select coalesce(sum(amount),0) into v_expenses_total from expenses where expense_date::date between v_month_start and v_month_end;
  select coalesce(sum(amount),0) into v_other_revenue from other_revenue where revenue_date::date between v_month_start and v_month_end;

  select balance_after into v_treasury_total from cash_flow order by flow_date desc, id desc limit 1;
  v_treasury_total := coalesce(v_treasury_total, 0);
  select coalesce(sum(amount),0) into v_treasury_cash from cash_flow where is_cash = true and direction='داخل';
  v_treasury_cash := v_treasury_cash - coalesce((select sum(amount) from cash_flow where is_cash=true and direction='خارج'),0);
  v_treasury_bank := v_treasury_total - v_treasury_cash;

  select balance_after into v_petty_cash from petty_cash order by movement_date desc, id desc limit 1;
  v_petty_cash := coalesce(v_petty_cash, 0);

  select coalesce(sum(remaining), 0) into v_receivables from invoices;
  select coalesce(sum(remaining), 0) into v_payables from purchase_orders;

  select count(*) into v_low_stock_count from product_variants where status = 'نشط' and quantity <= low_stock_threshold;

  select coalesce(jsonb_agg(jsonb_build_object(
      'productName', p.name, 'variantCode', pv.code, 'color', pv.color, 'size', pv.size, 'quantity', pv.quantity
    )), '[]'::jsonb) into v_low_stock
  from product_variants pv join products p on p.id = pv.product_id
  where pv.status = 'نشط' and pv.quantity <= pv.low_stock_threshold limit 15;

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
-- قائمة الدخل لفترة معيّنة
-- ------------------------------------------------------------
create or replace function rpc_income_statement(p_start date, p_end date)
returns jsonb language plpgsql security definer as $$
declare v_sales numeric; v_cogs numeric; v_expenses numeric; v_other numeric; v_tax_enabled text; v_tax_rate numeric;
begin
  select coalesce(sum(total),0) into v_sales from sales where sale_date::date between p_start and p_end and status <> 'مرتجع كلي';
  select coalesce(sum(si.qty*si.unit_cost),0) into v_cogs from sale_items si join sales s on s.id=si.sale_id
    where s.sale_date::date between p_start and p_end and s.status <> 'مرتجع كلي';
  select coalesce(sum(amount),0) into v_expenses from expenses where expense_date::date between p_start and p_end;
  select coalesce(sum(amount),0) into v_other from other_revenue where revenue_date::date between p_start and p_end;
  select value into v_tax_enabled from settings where key='taxEnabled';
  select value::numeric into v_tax_rate from settings where key='taxRate';

  return jsonb_build_object(
    'totalSales', v_sales, 'cogs', v_cogs, 'grossProfit', v_sales - v_cogs,
    'operatingExpenses', v_expenses, 'otherRevenue', v_other,
    'netProfitBeforeTax', v_sales - v_cogs - v_expenses + v_other,
    'taxEnabled', v_tax_enabled = 'true',
    'tax', case when v_tax_enabled='true' then round(v_sales * (coalesce(v_tax_rate,0)/100), 2) else 0 end,
    'netProfitAfterTax', (v_sales - v_cogs - v_expenses + v_other) - (case when v_tax_enabled='true' then round(v_sales*(coalesce(v_tax_rate,0)/100),2) else 0 end)
  );
end;
$$;

-- ------------------------------------------------------------
-- الجدولة التلقائية — pg_cron (بديل Time-Driven Triggers بتاع Apps Script)
-- لازم تفعّلي Extension "pg_cron" من Database > Extensions في Supabase الأول
-- ------------------------------------------------------------
-- select cron.schedule('monthly-admin-fee', '0 2 1 * *', $$select rpc_run_monthly_admin_fee()$$);

-- ------------------------------------------------------------
-- Grants — السماح للمستخدمين المسجّلين (authenticated) باستدعاء الدوال
-- ------------------------------------------------------------
grant execute on all functions in schema public to authenticated;

-- ============================================================
-- تعديلات إضافية: حقول ديناميكية للمصروفات (قاعدة "مرتبات")
-- ============================================================
alter table expenses add column if not exists employee_id uuid references employees(id);
alter table expenses add column if not exists bonus numeric(12,2);

-- ------------------------------------------------------------
-- كشف حساب مورد كامل (بيانات + مشتريات + مدين/دائن)
-- ------------------------------------------------------------
create or replace function rpc_get_supplier_statement(p_supplier_id uuid)
returns jsonb language plpgsql security definer as $$
declare
  v_supplier jsonb; v_purchases jsonb; v_total numeric; v_paid numeric; v_remaining numeric;
begin
  select to_jsonb(s) into v_supplier from suppliers s where id = p_supplier_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'orderNumber', order_number, 'date', order_date, 'total', total,
    'paymentStatus', payment_status, 'amountPaid', amount_paid, 'remaining', remaining
  ) order by order_date desc), '[]'::jsonb),
  coalesce(sum(total), 0), coalesce(sum(amount_paid), 0), coalesce(sum(remaining), 0)
  into v_purchases, v_total, v_paid, v_remaining
  from purchase_orders where supplier_id = p_supplier_id;

  return jsonb_build_object(
    'supplier', v_supplier, 'purchases', v_purchases,
    'totalPurchases', v_total, 'totalPaid', v_paid, 'totalRemaining', v_remaining
  );
end;
$$;

grant execute on all functions in schema public to authenticated;
