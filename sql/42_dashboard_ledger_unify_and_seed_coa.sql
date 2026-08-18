-- ============================================================
-- الدفعة 42:
-- (أ) الداشبورد بقى بياخد "الإجمالي" لكارت الخزنة من نفس دفتر
--     الأستاذ اللي ميزان المراجعة والميزانية العمومية بيقروا منه
--     (حساب "الخزينة")، بدل ما يكون ليه مصدر منفصل (treasury_accounts)
--     ممكن يختلف عنه. تقسيم كاش/بنك التفصيلي فضل زي ما هو من
--     treasury_accounts لأن دفتر الأستاذ مش بيسجلهم منفصلين.
--     (شجرة الحسابات وميزان المراجعة والميزانية العمومية نفسهم
--     مالهمش أي تعديل هنا خالص)
-- (ب) شجرة حسابات كاملة تتعمل تلقائيًا لوحدها لو ناقصة (قابلة
--     لإعادة التشغيل بأمان، وبتتنفذ تلقائيًا كل ما البرنامج يفتح)
-- ============================================================

-- ------------------------------------------------------------
-- أ) الداشبورد
-- ------------------------------------------------------------
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

  -- ✅ إصلاح 42: الإجمالي من دفتر الأستاذ (حساب "الخزينة") — نفس
  -- المصدر بالظبط اللي ميزان المراجعة والميزانية العمومية بيستخدموه
  select coalesce(sum(amount) filter (where debit_account_id in (select id from accounts where name = 'الخزينة')),0)
       - coalesce(sum(amount) filter (where credit_account_id in (select id from accounts where name = 'الخزينة')),0)
  into v_treasury_total from journal_entries;

  select coalesce(sum(current_balance) filter (where type='كاش'), 0) into v_treasury_cash from treasury_accounts where active = true;
  select coalesce(sum(current_balance) filter (where type='بنك'), 0) into v_treasury_bank from treasury_accounts where active = true;

  select coalesce(sum(amount) filter (where direction='داخل'),0) - coalesce(sum(amount) filter (where direction='خارج'),0)
  into v_legacy_cash from cash_flow where treasury_account_id is null;

  v_treasury_cash := v_treasury_cash + coalesce(v_legacy_cash, 0);

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
-- ب) شجرة حسابات كاملة تلقائيًا (idempotent — تضيف بس الناقص)
-- ------------------------------------------------------------
create or replace function rpc_seed_default_chart_of_accounts()
returns void language plpgsql security definer as $$
declare v_id uuid;
  v_1 uuid; v_11 uuid; v_12 uuid; v_2 uuid; v_21 uuid;
begin
  -- المستوى الأول (لو مش موجود أصلاً)
  insert into accounts (code, name, type, is_group)
  select code, name, type, true from (values
    ('1','الأصول','أصول'), ('2','الخصوم','خصوم'), ('3','حقوق الملكية','حقوق ملكية'),
    ('4','الإيرادات','إيرادات'), ('5','المصروفات','مصروفات')
  ) as t(code, name, type)
  where not exists (select 1 from accounts a where a.code = t.code);

  select id into v_1 from accounts where code = '1';
  select id into v_2 from accounts where code = '2';

  insert into accounts (code, name, type, is_group, parent_id)
  select '1.1', 'أصول متداولة', 'أصول', true, v_1 where not exists (select 1 from accounts where code = '1.1');
  insert into accounts (code, name, type, is_group, parent_id)
  select '1.2', 'أصول ثابتة', 'أصول', true, v_1 where not exists (select 1 from accounts where code = '1.2');
  insert into accounts (code, name, type, is_group, parent_id)
  select '2.1', 'خصوم متداولة', 'خصوم', true, v_2 where not exists (select 1 from accounts where code = '2.1');
  insert into accounts (code, name, type, is_group, parent_id)
  select '2.2', 'خصوم طويلة الأجل', 'خصوم', true, v_2 where not exists (select 1 from accounts where code = '2.2');

  select id into v_11 from accounts where code = '1.1';
  select id into v_12 from accounts where code = '1.2';
  select id into v_21 from accounts where code = '2.1';

  -- حسابات تفصيلية أساسية (لو مش موجودة بالاسم أصلاً)
  insert into accounts (code, name, type, is_group, parent_id, sub_group)
  select v.code, v.name, v.type, false, v.parent_id, v.sub_group from (values
    ('1.1.001', 'الخزينة', 'أصول', v_11, 'أصول متداولة'),
    ('1.1.002', 'العملاء (مدينون)', 'أصول', v_11, 'أصول متداولة'),
    ('1.1.003', 'العهدة', 'أصول', v_11, 'أصول متداولة'),
    ('1.1.004', 'المخزون', 'أصول', v_11, 'أصول متداولة'),
    ('1.2.001', 'الأصول الثابتة', 'أصول', v_12, null),
    ('1.2.002', 'مجمع إهلاك الأصول', 'أصول', v_12, null),
    ('2.1.001', 'الموردون', 'خصوم', v_21, 'خصوم متداولة'),
    ('3.001', 'رأس المال', 'حقوق ملكية', null, null),
    ('3.002', 'رصيد افتتاحي', 'حقوق ملكية', null, null),
    ('4.001', 'المبيعات', 'إيرادات', null, null),
    ('4.002', 'إيرادات أخرى', 'إيرادات', null, null),
    ('5.001', 'تكلفة البضاعة المباعة', 'مصروفات', null, null),
    ('5.002', 'المرتبات', 'مصروفات', null, null),
    ('5.003', 'المصروفات: إيجار', 'مصروفات', null, null),
    ('5.004', 'المصروفات: كهرباء ومياه', 'مصروفات', null, null),
    ('5.005', 'المصروفات: مواصلات', 'مصروفات', null, null),
    ('5.006', 'المصروفات: صيانة', 'مصروفات', null, null),
    ('5.007', 'المصروفات: تسويق وإعلان', 'مصروفات', null, null),
    ('5.008', 'المصروفات: أخرى', 'مصروفات', null, null)
  ) as v(code, name, type, parent_id, sub_group)
  where not exists (select 1 from accounts a where a.name = v.name);
end;
$$;

grant execute on all functions in schema public to authenticated;

select rpc_seed_default_chart_of_accounts();
