-- ============================================================
-- الدفعة 21: إصلاح كارت الخزنة في الداشبورد — كان بيحسب كاش/بنك
-- بطريقة تخمينية من نوع الحركة (is_cash) بدل الأرصدة الفعلية في
-- treasury_accounts، فكان ممكن يظهر رقم سالب غلط للبنك
-- ============================================================

create or replace function rpc_get_dashboard_data()
returns jsonb language plpgsql security definer as $$
declare
  v_month_start date := date_trunc('month', now());
  v_month_end date := (date_trunc('month', now()) + interval '1 month - 1 day')::date;
  v_sales_total numeric; v_sales_online numeric; v_sales_store numeric; v_sales_count int;
  v_cogs numeric; v_expenses_total numeric; v_other_revenue numeric;
  v_treasury_total numeric; v_treasury_cash numeric; v_treasury_bank numeric; v_legacy_cash numeric;
  v_petty_cash numeric; v_low_stock jsonb; v_recent_ops jsonb; v_partners jsonb;
  v_receivables numeric; v_payables numeric; v_low_stock_count int;
begin
  select coalesce(sum(total),0), coalesce(sum(total) filter (where source='أونلاين'),0),
         coalesce(sum(total) filter (where source='محل'),0), count(*)
  into v_sales_total, v_sales_online, v_sales_store, v_sales_count
  from sales where sale_date::date between v_month_start and v_month_end and status <> 'مرتجع كلي';

  declare v_sales_acc uuid; v_cogs_acc uuid;
  begin
    select id into v_sales_acc from accounts where name = 'المبيعات';
    select id into v_cogs_acc from accounts where name = 'تكلفة البضاعة المباعة';

    select coalesce(sum(amount) filter (where debit_account_id = v_cogs_acc),0) - coalesce(sum(amount) filter (where credit_account_id = v_cogs_acc),0)
    into v_cogs from journal_entries where entry_date::date between v_month_start and v_month_end;

    select coalesce(sum(amount) filter (where debit_account_id in (select id from accounts where name ilike 'المصروفات%')),0)
         - coalesce(sum(amount) filter (where credit_account_id in (select id from accounts where name ilike 'المصروفات%')),0)
    into v_expenses_total from journal_entries where entry_date::date between v_month_start and v_month_end;

    select coalesce(sum(amount) filter (where credit_account_id in (select id from accounts where name ilike '%إيرادات أخرى%')),0)
    into v_other_revenue from journal_entries where entry_date::date between v_month_start and v_month_end;
  end;

  -- ✅ الجزء المُصلَح: الكاش والبنك بيتحسبوا من الأرصدة الفعلية في treasury_accounts
  -- + أي فلوس قديمة اتسجلت قبل ما تتضاف حسابات خزنة (treasury_account_id فاضي) بتتحسب كاش
  select coalesce(sum(current_balance) filter (where type='كاش'), 0) into v_treasury_cash from treasury_accounts where active = true;
  select coalesce(sum(current_balance) filter (where type='بنك'), 0) into v_treasury_bank from treasury_accounts where active = true;

  select coalesce(sum(amount) filter (where direction='داخل'),0) - coalesce(sum(amount) filter (where direction='خارج'),0)
  into v_legacy_cash from cash_flow where treasury_account_id is null;

  v_treasury_cash := v_treasury_cash + coalesce(v_legacy_cash, 0);
  v_treasury_total := v_treasury_cash + v_treasury_bank;

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

grant execute on all functions in schema public to authenticated;
