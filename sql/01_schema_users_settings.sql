-- ============================================================
-- نظام الحسابات الشامل — Schema كامل على Postgres (Supabase)
-- الجزء 1: الجداول الأساسية + الإعدادات + المستخدمين
-- ============================================================

create extension if not exists "pgcrypto";

-- ------------------------------------------------------------
-- دالة عامة: تحديث updated_at تلقائيًا في أي جدول
-- ------------------------------------------------------------
create or replace function fn_set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ------------------------------------------------------------
-- المستخدمون (profiles) — مرتبط بـ auth.users بتاع Supabase
-- تسجيل الدخول نفسه بيتم عن طريق Supabase Auth (إيميل + باسورد)
-- الجدول ده بس بيحمل بيانات إضافية: الدور والصلاحيات
-- ------------------------------------------------------------
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  full_name text not null default '',
  role text not null default 'بائع' check (role in ('أدمن', 'شريك', 'بائع', 'كاشير')),
  permissions jsonb not null default '{}'::jsonb, -- { "Sales": "تعديل", "Reports": "عرض", ... }
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- دالة صلاحيات مركزية تُستخدم في كل الـ RLS Policies
create or replace function fn_has_permission(p_module text, p_level text)
returns boolean language plpgsql stable as $$
declare
  v_role text;
  v_perm text;
  v_levels text[] := array['مخفي', 'عرض', 'تعديل'];
begin
  select role, permissions->>p_module into v_role, v_perm
  from profiles where id = auth.uid();

  if v_role is null then return false; end if;
  if v_role = 'أدمن' then return true; end if;
  if v_role = 'شريك' and v_perm is null then v_perm := 'عرض'; end if;
  if v_perm is null then v_perm := 'مخفي'; end if;

  return array_position(v_levels, v_perm) >= array_position(v_levels, p_level);
end;
$$;

alter table profiles enable row level security;
create policy "الكل يشوف بروفايله" on profiles for select using (auth.uid() = id or fn_has_permission('Users','عرض'));
create policy "الأدمن يعدل اليوزرات" on profiles for all using (fn_has_permission('Users','تعديل'));

-- ------------------------------------------------------------
-- الإعدادات (Key-Value)
-- ------------------------------------------------------------
create table settings (
  key text primary key,
  value text
);

insert into settings (key, value) values
  ('brandName', 'براندي'), ('logoUrl', ''), ('operatingMode', 'BOTH'),
  ('primaryColor', '#1a1a2e'), ('accentColor', '#e94560'), ('currency', 'جنيه مصري'),
  ('darkMode', 'true'), ('easyOrdersApiKey', ''), ('easyOrdersSecret', ''),
  ('lowStockThresholdDefault', '5'), ('adminFeeEnabled', 'true'), ('taxEnabled', 'false'),
  ('taxRate', '14'), ('partnerApprovalEnabled', 'false'), ('monthlyPartnerPdfEnabled', 'false'),
  ('defaultOnlineWarehouseId', '');

alter table settings enable row level security;
create policy "الكل يقرا الإعدادات" on settings for select using (auth.role() = 'authenticated');
create policy "بس اللي عنده صلاحية يعدل" on settings for all using (fn_has_permission('Settings','تعديل'));

-- ------------------------------------------------------------
-- المخازن
-- ------------------------------------------------------------
create table warehouses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text default '',
  location text default '',
  is_default_online boolean not null default false,
  created_at timestamptz not null default now()
);

alter table warehouses enable row level security;
create policy "قراءة عامة" on warehouses for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية" on warehouses for all using (fn_has_permission('Inventory','تعديل'));

-- ------------------------------------------------------------
-- شجرة الأصناف (تكويد هرمي)
-- ------------------------------------------------------------
create table product_tree (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  type text not null check (type in ('رئيسية', 'فرعية')),
  parent_id uuid references product_tree(id),
  active boolean not null default true
);

alter table product_tree enable row level security;
create policy "قراءة عامة" on product_tree for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية" on product_tree for all using (fn_has_permission('Inventory','تعديل'));

-- ------------------------------------------------------------
-- المنتجات (Parent) + المتغيرات (Variants)
-- ------------------------------------------------------------
create table products (
  id uuid primary key default gen_random_uuid(),
  code text unique not null, -- الكود الهرمي التلقائي
  name text not null,
  main_category_id uuid references product_tree(id),
  sub_category_id uuid references product_tree(id),
  base_price numeric(12,2) not null default 0,
  image_url text default '',
  description text default '',
  has_variants boolean not null default false,
  status text not null default 'نشط' check (status in ('نشط','متوقف')),
  created_at timestamptz not null default now()
);
create index idx_products_search on products using gin (to_tsvector('simple', name || ' ' || code));

create table product_variants (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  product_id uuid not null references products(id) on delete cascade,
  color text default '',
  size text default '',
  quantity numeric(12,2) not null default 0,
  cost numeric(12,2) not null default 0,
  special_price numeric(12,2),
  warehouse_id uuid references warehouses(id),
  low_stock_threshold numeric(12,2) not null default 5,
  status text not null default 'نشط' check (status in ('نشط','متوقف'))
);
create index idx_variants_product on product_variants(product_id);
create index idx_variants_search on product_variants using gin (to_tsvector('simple', coalesce(color,'') || ' ' || coalesce(size,'') || ' ' || code));

create table cost_history (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references product_variants(id),
  old_cost numeric(12,2), new_cost numeric(12,2), quantity numeric(12,2),
  source_ref text, created_at timestamptz not null default now()
);

alter table products enable row level security;
alter table product_variants enable row level security;
alter table cost_history enable row level security;
create policy "قراءة عامة منتجات" on products for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية منتجات" on products for all using (fn_has_permission('Inventory','تعديل'));
create policy "قراءة عامة متغيرات" on product_variants for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية متغيرات" on product_variants for all using (fn_has_permission('Inventory','تعديل'));
create policy "قراءة عامة تاريخ تكلفة" on cost_history for select using (auth.role() = 'authenticated');

-- ------------------------------------------------------------
-- دالة عامة (بدون تسجيل دخول) بترجع الإيميل المرتبط بيوزرنيم معيّن
-- عشان تسمحي للمستخدم يسجّل دخول باليوزرنيم بدل الإيميل الكامل
-- آمنة: بترجع الإيميل بس، مش أي بيانات حساسة تانية
-- ------------------------------------------------------------
create or replace function rpc_get_email_by_username(p_username text)
returns text language plpgsql security definer as $$
declare v_email text;
begin
  select u.email into v_email
  from profiles p join auth.users u on u.id = p.id
  where p.username = p_username and p.active = true;
  return v_email;
end;
$$;

grant execute on function rpc_get_email_by_username(text) to anon, authenticated;
