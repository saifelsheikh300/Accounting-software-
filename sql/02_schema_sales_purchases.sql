-- ============================================================
-- الجزء 2: المبيعات، المصروفات، الموردون، الأوردرات، الفواتير
-- ============================================================

-- ------------------------------------------------------------
-- المبيعات (Header) + بنود البيعة (Lines) — مطبّعة بدل JSON
-- ------------------------------------------------------------
create table sales (
  id uuid primary key default gen_random_uuid(),
  sale_number text unique not null,
  sale_date timestamptz not null default now(),
  source text not null check (source in ('أونلاين','محل')),
  subtotal numeric(12,2) not null default 0,
  discount numeric(12,2) not null default 0,
  total numeric(12,2) not null default 0,
  payment_method text,
  invoice_id uuid,
  customer_name text default '',
  customer_phone text default '',
  warehouse_id uuid references warehouses(id),
  status text not null default 'مكتملة' check (status in ('مكتملة','مرتجع كلي','مرتجع جزئي')),
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create table sale_items (
  id uuid primary key default gen_random_uuid(),
  sale_id uuid not null references sales(id) on delete cascade,
  variant_id uuid not null references product_variants(id),
  qty numeric(12,2) not null,
  unit_price numeric(12,2) not null,
  unit_cost numeric(12,2) not null default 0 -- Snapshot من التكلفة وقت البيع لحساب COGS بدقة
);
create index idx_sale_items_sale on sale_items(sale_id);
create index idx_sales_date on sales(sale_date);

-- ------------------------------------------------------------
-- الأصول الثابتة + المصروفات + الإيرادات الأخرى
-- ------------------------------------------------------------
create table fixed_assets (
  id uuid primary key default gen_random_uuid(),
  description text, amount numeric(12,2), acquired_at timestamptz not null default now()
);

create table expenses (
  id uuid primary key default gen_random_uuid(),
  expense_date timestamptz not null default now(),
  main_category text not null,
  sub_category text default '',
  description text default '',
  amount numeric(12,2) not null,
  is_recurring boolean not null default false,
  recurrence_days int,
  is_fixed_asset boolean not null default false,
  payment_method text default 'كاش',
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);
create index idx_expenses_date on expenses(expense_date);

create table other_revenue (
  id uuid primary key default gen_random_uuid(),
  revenue_date timestamptz not null default now(),
  source text not null, description text default '', amount numeric(12,2) not null,
  created_by uuid references profiles(id)
);

-- ------------------------------------------------------------
-- الموردون + أوردرات الشراء
-- ------------------------------------------------------------
create table suppliers (
  id uuid primary key default gen_random_uuid(),
  name text unique not null, contact text default '', notes text default ''
);

create table purchase_orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique not null,
  order_date timestamptz not null default now(),
  supplier_id uuid not null references suppliers(id),
  total numeric(12,2) not null default 0,
  payment_status text not null default 'متأخر/غير مدفوع' check (payment_status in ('مدفوع بالكامل','مدفوع جزئيًا','متأخر/غير مدفوع')),
  amount_paid numeric(12,2) not null default 0,
  remaining numeric(12,2) not null default 0,
  warehouse_id uuid references warehouses(id)
);

create table purchase_order_items (
  id uuid primary key default gen_random_uuid(),
  purchase_order_id uuid not null references purchase_orders(id) on delete cascade,
  variant_id uuid not null references product_variants(id),
  qty numeric(12,2) not null, unit_price numeric(12,2) not null
);

-- ------------------------------------------------------------
-- العملاء + الأوردرات (أونلاين) + الفواتير
-- ------------------------------------------------------------
create table customers (
  phone text primary key,
  name text default '',
  order_count int not null default 0,
  total_purchases numeric(12,2) not null default 0,
  first_order_at timestamptz not null default now(),
  notes text default ''
);

create table orders (
  id uuid primary key default gen_random_uuid(),
  easy_orders_id text unique,
  order_date timestamptz not null default now(),
  customer_phone text references customers(phone),
  customer_name text default '',
  total numeric(12,2) not null default 0,
  status text not null default 'pending',
  confirmed boolean not null default false,
  return_status text not null default 'لا',
  notes text default ''
);

create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  variant_id uuid not null references product_variants(id),
  qty numeric(12,2) not null, unit_price numeric(12,2) not null
);

create table invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text unique not null,
  invoice_date timestamptz not null default now(),
  customer_name text not null,
  total numeric(12,2) not null,
  paid numeric(12,2) not null default 0,
  remaining numeric(12,2) not null default 0,
  status text not null default 'متأخرة' check (status in ('مدفوعة بالكامل','مدفوعة جزئيًا','متأخرة','تم التحصيل COD'))
);

alter table sales enable row level security;
alter table sale_items enable row level security;
alter table expenses enable row level security;
alter table other_revenue enable row level security;
alter table fixed_assets enable row level security;
alter table suppliers enable row level security;
alter table purchase_orders enable row level security;
alter table purchase_order_items enable row level security;
alter table customers enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table invoices enable row level security;

create policy "قراءة عامة sales" on sales for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية sales" on sales for all using (fn_has_permission('Sales','تعديل'));
create policy "قراءة عامة sale_items" on sale_items for select using (auth.role() = 'authenticated');
create policy "قراءة عامة expenses" on expenses for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية expenses" on expenses for all using (fn_has_permission('Expenses','تعديل'));
create policy "قراءة عامة other_revenue" on other_revenue for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية other_revenue" on other_revenue for all using (fn_has_permission('Expenses','تعديل'));
create policy "قراءة عامة fixed_assets" on fixed_assets for select using (auth.role() = 'authenticated');
create policy "قراءة عامة suppliers" on suppliers for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية suppliers" on suppliers for all using (fn_has_permission('Suppliers','تعديل'));
create policy "قراءة عامة po" on purchase_orders for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية po" on purchase_orders for all using (fn_has_permission('Suppliers','تعديل'));
create policy "قراءة عامة po_items" on purchase_order_items for select using (auth.role() = 'authenticated');
create policy "قراءة عامة customers" on customers for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية customers" on customers for all using (fn_has_permission('Orders','تعديل'));
create policy "قراءة عامة orders" on orders for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية orders" on orders for all using (fn_has_permission('Orders','تعديل'));
create policy "قراءة عامة order_items" on order_items for select using (auth.role() = 'authenticated');
create policy "قراءة عامة invoices" on invoices for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية invoices" on invoices for all using (fn_has_permission('Invoices','تعديل'));
