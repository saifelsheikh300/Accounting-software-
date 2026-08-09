-- ============================================================
-- الدفعة 3: الربحية الحقيقية + طرق تقييم المخزون + عملات متعددة
-- + دورة الشيكات
-- ============================================================

-- ------------------------------------------------------------
-- 1) طريقة تقييم المخزون — إعداد عام (متوسط التكلفة المرجح افتراضيًا،
-- وهو أساسًا اللي rpc_create_purchase_order بيطبقه من قبل)
-- بنضيف خيار واضح في الإعدادات + رصيد متوسط مُحسوب لكل متغير
-- ------------------------------------------------------------
insert into settings (key, value) values ('inventoryValuationMethod', 'متوسط مرجح')
  on conflict (key) do nothing;

-- إعادة حساب دالة الشراء عشان تطبّق "متوسط مرجح" فعليًا بدل استبدال آخر تكلفة بالكامل
create or replace function rpc_create_purchase_order(
  p_supplier_name text, p_items jsonb, p_payment_status text default 'مدفوع بالكامل',
  p_amount_paid numeric default 0, p_warehouse_id uuid default null
)
returns table(order_id uuid, order_number text, total numeric) language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_old_cost numeric; v_old_qty numeric; v_qty numeric; v_price numeric;
  v_new_avg_cost numeric; v_total numeric := 0; v_supplier_id uuid; v_order_id uuid; v_order_number text;
  v_paid numeric; v_remaining numeric; v_is_cash boolean; v_method text;
begin
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
      v_new_avg_cost := v_price; -- آخر تكلفة (LIFO-ish بسيط) لو الإعداد مختلف
    end if;

    update product_variants set quantity = quantity + v_qty, cost = v_new_avg_cost where id = v_variant_id;
    insert into cost_history (variant_id, old_cost, new_cost, quantity, source_ref) values (v_variant_id, v_old_cost, v_new_avg_cost, v_qty, v_order_number);
  end loop;

  v_is_cash := p_payment_status = 'مدفوع بالكامل';
  perform fn_journal_entry('المخزون', case when v_is_cash then 'الخزينة' else 'الموردون' end, v_total, v_order_number, 'أوردر شراء رقم ' || v_order_number);
  if v_paid > 0 then perform fn_append_cash_flow('خارج', 'أوردر شراء ' || v_order_number, v_paid); end if;

  perform fn_log_operation('CREATE_PURCHASE_ORDER', jsonb_build_object('order_number', v_order_number, 'total', v_total));
  return query select v_order_id, v_order_number, v_total;
end;
$$;

-- ------------------------------------------------------------
-- 2) الربحية الحقيقية — لكل صنف / فاتورة / عميل
-- ------------------------------------------------------------
create or replace function rpc_profitability_by_product(p_start date, p_end date)
returns jsonb language plpgsql security definer as $$
declare v_result jsonb;
begin
  if not fn_has_permission('Reports', 'عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'productName', p.name, 'variantCode', pv.code,
    'qtySold', t.qty_sold, 'revenue', t.revenue, 'cost', t.cost,
    'profit', t.revenue - t.cost,
    'marginPercent', case when t.revenue > 0 then round(((t.revenue - t.cost) / t.revenue) * 100, 2) else 0 end
  ) order by (t.revenue - t.cost) desc), '[]'::jsonb) into v_result
  from (
    select si.variant_id, sum(si.qty) qty_sold, sum(si.qty * si.unit_price) revenue, sum(si.qty * si.unit_cost) cost
    from sale_items si join sales s on s.id = si.sale_id
    where s.sale_date::date between p_start and p_end and s.status <> 'مرتجع كلي'
    group by si.variant_id
  ) t
  join product_variants pv on pv.id = t.variant_id
  join products p on p.id = pv.product_id;

  return v_result;
end;
$$;

create or replace function rpc_profitability_by_customer(p_start date, p_end date)
returns jsonb language plpgsql security definer as $$
declare v_result jsonb;
begin
  if not fn_has_permission('Reports', 'عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'customerName', t.customer_name, 'customerPhone', t.customer_phone,
    'ordersCount', t.orders_count, 'revenue', t.revenue, 'cost', t.cost, 'profit', t.revenue - t.cost
  ) order by (t.revenue - t.cost) desc), '[]'::jsonb) into v_result
  from (
    select coalesce(nullif(s.customer_name,''), 'عميل نقدي') customer_name, s.customer_phone,
      count(distinct s.id) orders_count, sum(si.qty * si.unit_price) revenue, sum(si.qty * si.unit_cost) cost
    from sales s join sale_items si on si.sale_id = s.id
    where s.sale_date::date between p_start and p_end and s.status <> 'مرتجع كلي'
    group by 1, 2
  ) t;

  return v_result;
end;
$$;

-- ------------------------------------------------------------
-- 3) عملات متعددة — سعر صرف يومي + عملة لكل بيعة/فاتورة
-- ------------------------------------------------------------
create table if not exists currencies (
  code text primary key, -- 'EGP','USD',...
  name text not null,
  is_base boolean not null default false
);
insert into currencies (code, name, is_base) values ('EGP', 'جنيه مصري', true) on conflict do nothing;

create table if not exists exchange_rates (
  id uuid primary key default gen_random_uuid(),
  currency_code text not null references currencies(code),
  rate_date date not null default current_date,
  rate_to_base numeric(14,6) not null,
  unique (currency_code, rate_date)
);

alter table sales add column if not exists currency_code text not null default 'EGP' references currencies(code);
alter table invoices add column if not exists currency_code text not null default 'EGP' references currencies(code);

alter table currencies enable row level security;
alter table exchange_rates enable row level security;
drop policy if exists "قراءة عامة currencies" on currencies;
create policy "قراءة عامة currencies" on currencies for select using (auth.role() = 'authenticated');
drop policy if exists "تعديل بصلاحية currencies" on currencies;
create policy "تعديل بصلاحية currencies" on currencies for all using (fn_has_permission('Settings','تعديل'));
drop policy if exists "قراءة عامة exchange_rates" on exchange_rates;
create policy "قراءة عامة exchange_rates" on exchange_rates for select using (auth.role() = 'authenticated');
drop policy if exists "تعديل بصلاحية exchange_rates" on exchange_rates;
create policy "تعديل بصلاحية exchange_rates" on exchange_rates for all using (fn_has_permission('Settings','تعديل'));

create or replace function rpc_set_exchange_rate(p_currency_code text, p_rate numeric, p_date date default current_date)
returns void language plpgsql security definer as $$
begin
  if not fn_has_permission('Settings', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  insert into exchange_rates (currency_code, rate_date, rate_to_base) values (p_currency_code, p_date, p_rate)
    on conflict (currency_code, rate_date) do update set rate_to_base = p_rate;
  perform fn_log_operation('SET_EXCHANGE_RATE', jsonb_build_object('currency', p_currency_code, 'rate', p_rate));
end;
$$;

-- ------------------------------------------------------------
-- 4) دورة الشيكات — واردة وصادرة، بحالة تتغير
-- ------------------------------------------------------------
create table if not exists checks (
  id uuid primary key default gen_random_uuid(),
  check_number text not null,
  direction text not null check (direction in ('واردة','صادرة')),
  party_name text not null, -- اسم العميل أو المورد
  amount numeric(14,2) not null,
  due_date date not null,
  bank_name text default '',
  status text not null default 'تحت التحصيل' check (status in ('تحت التحصيل','تم التحصيل','مرتجعة/مرفوضة','ملغاة')),
  notes text default '',
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
create index idx_checks_due on checks(due_date);

alter table checks enable row level security;
drop policy if exists "قراءة بصلاحية checks" on checks;
create policy "قراءة بصلاحية checks" on checks for select using (fn_has_permission('Reports','عرض'));
drop policy if exists "تعديل بصلاحية checks" on checks;
create policy "تعديل بصلاحية checks" on checks for all using (fn_has_permission('Reports','تعديل'));

create or replace function rpc_update_check_status(p_check_id uuid, p_status text)
returns void language plpgsql security definer as $$
declare v_check record;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  select * into v_check from checks where id = p_check_id;
  if v_check.id is null then raise exception 'الشيك غير موجود'; end if;

  update checks set status = p_status where id = p_check_id;

  if p_status = 'تم التحصيل' then
    perform fn_append_cash_flow(case when v_check.direction = 'واردة' then 'داخل' else 'خارج' end,
      'شيك ' || v_check.check_number || ' — ' || v_check.party_name, v_check.amount);
  end if;

  perform fn_log_operation('UPDATE_CHECK_STATUS', jsonb_build_object('check_id', p_check_id, 'status', p_status));
end;
$$;

grant execute on all functions in schema public to authenticated;
