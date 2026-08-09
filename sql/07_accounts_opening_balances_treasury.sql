-- ============================================================
-- الدفعة 1: شجرة الحسابات + أرصدة أول مدة + خزنة/بنوك متعددة
-- + سلة المحذوفات + مراكز التكلفة
-- مبني فوق سكيما 01-06 الموجودة، بدون أي تعارض مع جداول قائمة
-- ============================================================

-- ------------------------------------------------------------
-- 1) شجرة الحسابات (Chart of Accounts) — هرمية زي product_tree
-- بديل الأسماء الحرة (النصوص) اللي كانت بتتكتب يدوي في journal_entries
-- ------------------------------------------------------------
create table accounts (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  type text not null check (type in ('أصول','خصوم','حقوق ملكية','إيرادات','مصروفات')),
  parent_id uuid references accounts(id),
  is_group boolean not null default false, -- حساب رئيسي تجميعي (مينفعش يتقيد عليه مباشرة)
  active boolean not null default true,
  created_at timestamptz not null default now()
);

alter table journal_entries add column if not exists debit_account_id uuid references accounts(id);
alter table journal_entries add column if not exists credit_account_id uuid references accounts(id);

alter table accounts enable row level security;
create policy "قراءة عامة accounts" on accounts for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية accounts" on accounts for all using (fn_has_permission('Reports','تعديل'));

create or replace function rpc_add_account(p_name text, p_type text, p_parent_code text default null, p_is_group boolean default false)
returns table(code text) language plpgsql security definer as $$
declare v_code text; v_max int; v_parent_id uuid;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  if p_parent_code is null then
    select coalesce(max(a.code::int), 0) into v_max from accounts a where a.parent_id is null;
    v_code := (v_max + 1)::text;
  else
    select id into v_parent_id from accounts where accounts.code = p_parent_code;
    if v_parent_id is null then raise exception 'الحساب الأب غير موجود'; end if;
    select coalesce(max(substring(a.code from length(p_parent_code)+1)::int), 0) into v_max
    from accounts a where a.parent_id = v_parent_id;
    v_code := p_parent_code || (v_max + 1)::text;
  end if;

  insert into accounts (code, name, type, parent_id, is_group) values (v_code, p_name, p_type, v_parent_id, p_is_group);
  perform fn_log_operation('ADD_ACCOUNT', jsonb_build_object('code', v_code, 'name', p_name));
  return query select v_code;
end;
$$;

-- ------------------------------------------------------------
-- 2) أرصدة أول مدة (Opening Balances) — تُقفل بعد الاعتماد
-- ------------------------------------------------------------
create table opening_balances (
  id uuid primary key default gen_random_uuid(),
  as_of_date date not null,
  account_id uuid references accounts(id),
  variant_id uuid references product_variants(id), -- لو الرصيد الافتتاحي مخزون
  amount numeric(14,2) not null default 0,
  quantity numeric(12,2),
  description text default '',
  locked boolean not null default false,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

alter table opening_balances enable row level security;
create policy "قراءة بصلاحية opening_balances" on opening_balances for select using (fn_has_permission('Reports','عرض'));
create policy "تعديل بصلاحية opening_balances" on opening_balances for all using (fn_has_permission('Reports','تعديل'));

create or replace function rpc_lock_opening_balances()
returns void language plpgsql security definer as $$
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  update opening_balances set locked = true where locked = false;
  perform fn_log_operation('LOCK_OPENING_BALANCES', '{}'::jsonb);
end;
$$;

-- ------------------------------------------------------------
-- 3) خزنة وبنوك متعددة — بدل is_cash boolean، هنربط كل حركة بحساب مالي محدد
-- ------------------------------------------------------------
create table treasury_accounts (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  type text not null check (type in ('كاش','بنك')),
  bank_name text default '',
  account_number text default '',
  opening_balance numeric(14,2) not null default 0,
  current_balance numeric(14,2) not null default 0,
  active boolean not null default true
);

alter table cash_flow add column if not exists treasury_account_id uuid references treasury_accounts(id);

alter table treasury_accounts enable row level security;
create policy "قراءة بصلاحية treasury_accounts" on treasury_accounts for select using (fn_has_permission('Reports','عرض'));
create policy "تعديل بصلاحية treasury_accounts" on treasury_accounts for all using (fn_has_permission('Reports','تعديل'));

create or replace function rpc_transfer_between_treasuries(p_from_id uuid, p_to_id uuid, p_amount numeric, p_notes text default '')
returns void language plpgsql security definer as $$
declare v_from_name text; v_to_name text;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  select name into v_from_name from treasury_accounts where id = p_from_id;
  select name into v_to_name from treasury_accounts where id = p_to_id;
  if v_from_name is null or v_to_name is null then raise exception 'حساب خزنة غير موجود'; end if;

  update treasury_accounts set current_balance = current_balance - p_amount where id = p_from_id;
  update treasury_accounts set current_balance = current_balance + p_amount where id = p_to_id;

  insert into cash_flow (direction, source, amount, treasury_account_id, is_cash, reconciliation_note)
  values ('خارج', 'تحويل إلى ' || v_to_name, p_amount, p_from_id, (select type='كاش' from treasury_accounts where id=p_from_id), p_notes);
  insert into cash_flow (direction, source, amount, treasury_account_id, is_cash, reconciliation_note)
  values ('داخل', 'تحويل من ' || v_from_name, p_amount, p_to_id, (select type='كاش' from treasury_accounts where id=p_to_id), p_notes);

  perform fn_log_operation('TRANSFER_TREASURY', jsonb_build_object('from', v_from_name, 'to', v_to_name, 'amount', p_amount));
end;
$$;

-- ------------------------------------------------------------
-- 4) سلة المحذوفات — soft delete على أهم الجداول التشغيلية
-- ------------------------------------------------------------
alter table products add column if not exists deleted_at timestamptz;
alter table product_variants add column if not exists deleted_at timestamptz;
alter table customers add column if not exists deleted_at timestamptz;
alter table suppliers add column if not exists deleted_at timestamptz;
alter table employees add column if not exists deleted_at timestamptz;

create or replace function rpc_soft_delete(p_table text, p_id text)
returns void language plpgsql security definer as $$
begin
  if p_table not in ('products','product_variants','customers','suppliers','employees') then
    raise exception 'جدول غير مسموح للحذف الناعم';
  end if;
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  if p_table = 'customers' then
    execute format('update %I set deleted_at = now() where phone = $1', p_table) using p_id;
  else
    execute format('update %I set deleted_at = now() where id = $1::uuid', p_table) using p_id;
  end if;

  perform fn_log_operation('SOFT_DELETE', jsonb_build_object('table', p_table, 'id', p_id));
end;
$$;

create or replace function rpc_restore_deleted(p_table text, p_id text)
returns void language plpgsql security definer as $$
begin
  if p_table not in ('products','product_variants','customers','suppliers','employees') then
    raise exception 'جدول غير مسموح للاسترجاع';
  end if;
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  if p_table = 'customers' then
    execute format('update %I set deleted_at = null where phone = $1', p_table) using p_id;
  else
    execute format('update %I set deleted_at = null where id = $1::uuid', p_table) using p_id;
  end if;

  perform fn_log_operation('RESTORE_DELETED', jsonb_build_object('table', p_table, 'id', p_id));
end;
$$;

-- ------------------------------------------------------------
-- 5) مراكز التكلفة — لربط المصروفات والمبيعات بمركز تكلفة
-- ------------------------------------------------------------
create table cost_centers (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  description text default '',
  active boolean not null default true
);

alter table expenses add column if not exists cost_center_id uuid references cost_centers(id);
alter table sales add column if not exists cost_center_id uuid references cost_centers(id);

alter table cost_centers enable row level security;
create policy "قراءة عامة cost_centers" on cost_centers for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية cost_centers" on cost_centers for all using (fn_has_permission('Expenses','تعديل'));

grant execute on all functions in schema public to authenticated;
