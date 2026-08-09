-- ============================================================
-- الجزء 3: رأس المال والشركاء، العهدة، الموارد البشرية،
-- المحاسبة (القيد المزدوج)، السجلات، المواسم
-- ============================================================

-- ------------------------------------------------------------
-- الشركاء + حركات رأس المال + مستحقات الإدارة + توزيع الأرباح
-- ------------------------------------------------------------
create table partners (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  balance numeric(14,2) not null default 0,        -- الرصيد التراكمي (تُحدَّث تلقائيًا)
  ownership_percent numeric(6,3) not null default 0, -- تُحسب تلقائيًا
  profit_share_percent numeric(6,3),
  admin_rate numeric(12,2),
  admin_rate_type text check (admin_rate_type in ('نسبة %','مبلغ ثابت'))
);

create table capital_movements (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references partners(id),
  movement_date timestamptz not null default now(),
  type text not null check (type in ('إضافة رأس مال','سحب رأس مال')),
  amount numeric(14,2) not null,
  balance_after numeric(14,2) not null default 0,
  notes text default ''
);

create table admin_rights (
  id uuid primary key default gen_random_uuid(),
  partner_id uuid not null references partners(id),
  month_label text not null, -- 'YYYY-MM'
  earned numeric(12,2) not null default 0,
  withdrawn numeric(12,2) not null default 0,
  available numeric(12,2) not null default 0,
  last_withdrawal_at timestamptz,
  unique (partner_id, month_label)
);

create table profits_distribution (
  id uuid primary key default gen_random_uuid(),
  month_label text not null,
  net_profit numeric(14,2) not null,
  partner_id uuid not null references partners(id),
  percent numeric(6,3) not null,
  share numeric(14,2) not null,
  approval_status text not null default 'موافق' check (approval_status in ('بانتظار الموافقة','موافق','غير موافق')),
  approved_at timestamptz
);

-- ------------------------------------------------------------
-- العهدة (Petty Cash) + التدفق النقدي
-- ------------------------------------------------------------
create table petty_cash (
  id uuid primary key default gen_random_uuid(),
  movement_date timestamptz not null default now(),
  type text not null check (type in ('إيداع','سحب','مصروف')),
  amount numeric(12,2) not null,
  description text default '',
  balance_after numeric(12,2) not null default 0,
  created_by uuid references profiles(id)
);

create table cash_flow (
  id uuid primary key default gen_random_uuid(),
  flow_date timestamptz not null default now(),
  direction text not null check (direction in ('داخل','خارج')),
  source text, amount numeric(12,2) not null,
  balance_after numeric(14,2) not null default 0,
  is_cash boolean not null default true, -- كاش أو بنك (لفصل الخزنة في القسم 14)
  reconciliation_note text default ''
);
create index idx_cash_flow_date on cash_flow(flow_date);

-- ------------------------------------------------------------
-- الموارد البشرية
-- ------------------------------------------------------------
create table employees (
  id uuid primary key default gen_random_uuid(),
  name text not null, job_title text default '',
  hired_at timestamptz not null default now(),
  base_salary numeric(12,2) not null,
  phone text default '',
  status text not null default 'نشط' check (status in ('نشط','منتهي الخدمة'))
);

create table salaries (
  id uuid primary key default gen_random_uuid(),
  month_label text not null,
  employee_id uuid not null references employees(id),
  base_salary numeric(12,2) not null,
  deductions numeric(12,2) not null default 0,
  additions numeric(12,2) not null default 0,
  net numeric(12,2) not null,
  paid boolean not null default false,
  unique (month_label, employee_id)
);

create table attendance (
  id uuid primary key default gen_random_uuid(),
  attendance_date date not null default current_date,
  employee_id uuid not null references employees(id),
  status text not null check (status in ('حضور','غياب','إجازة')),
  notes text default ''
);

create table advances (
  id uuid primary key default gen_random_uuid(),
  advance_date timestamptz not null default now(),
  employee_id uuid not null references employees(id),
  amount numeric(12,2) not null,
  deducted boolean not null default false,
  notes text default ''
);

-- ------------------------------------------------------------
-- القيد المحاسبي المزدوج (يومية المحاسبة)
-- ------------------------------------------------------------
create sequence journal_entry_seq start 1;

create table journal_entries (
  id uuid primary key default gen_random_uuid(),
  entry_number text unique not null,
  entry_date timestamptz not null default now(),
  description text default '',
  debit_account text not null,
  credit_account text not null,
  amount numeric(14,2) not null,
  reference text default ''
);
create index idx_journal_date on journal_entries(entry_date);

-- ------------------------------------------------------------
-- سجل العمليات + سجل Webhooks + المواسم + النسخ الاحتياطي
-- ------------------------------------------------------------
create table operations_log (
  id bigint generated always as identity primary key,
  logged_at timestamptz not null default now(),
  actor text not null, -- username أو 'SYSTEM'
  operation text not null,
  details jsonb default '{}'::jsonb
);
create index idx_ops_log_date on operations_log(logged_at desc);

create table webhooks_log (
  id bigint generated always as identity primary key,
  received_at timestamptz not null default now(),
  event_type text, raw_payload jsonb, processed boolean not null default false, error_message text
);

create table seasons (
  id uuid primary key default gen_random_uuid(),
  name text not null, start_date date not null, end_date date not null, notes text default ''
);

create table backup_log (
  id bigint generated always as identity primary key,
  backed_up_at timestamptz not null default now(),
  backup_type text, status text, notes text default ''
);

-- ------------------------------------------------------------
-- RLS لكل الجداول أعلاه
-- ------------------------------------------------------------
alter table partners enable row level security;
alter table capital_movements enable row level security;
alter table admin_rights enable row level security;
alter table profits_distribution enable row level security;
alter table petty_cash enable row level security;
alter table cash_flow enable row level security;
alter table employees enable row level security;
alter table salaries enable row level security;
alter table attendance enable row level security;
alter table advances enable row level security;
alter table journal_entries enable row level security;
alter table operations_log enable row level security;
alter table webhooks_log enable row level security;
alter table seasons enable row level security;
alter table backup_log enable row level security;

create policy "قراءة بصلاحية عرض partners" on partners for select using (fn_has_permission('Capital','عرض'));
create policy "تعديل بصلاحية partners" on partners for all using (fn_has_permission('Capital','تعديل'));
create policy "قراءة بصلاحية عرض capital_movements" on capital_movements for select using (fn_has_permission('Capital','عرض'));
create policy "تعديل بصلاحية capital_movements" on capital_movements for all using (fn_has_permission('Capital','تعديل'));
create policy "قراءة بصلاحية عرض admin_rights" on admin_rights for select using (fn_has_permission('Capital','عرض'));
create policy "قراءة بصلاحية عرض profits" on profits_distribution for select using (fn_has_permission('Capital','عرض'));
create policy "قراءة بصلاحية عرض petty_cash" on petty_cash for select using (fn_has_permission('PettyCash','عرض'));
create policy "تعديل بصلاحية petty_cash" on petty_cash for all using (fn_has_permission('PettyCash','تعديل'));
create policy "قراءة بصلاحية عرض cash_flow" on cash_flow for select using (fn_has_permission('Reports','عرض'));
create policy "قراءة بصلاحية عرض employees" on employees for select using (fn_has_permission('HR','عرض'));
create policy "تعديل بصلاحية employees" on employees for all using (fn_has_permission('HR','تعديل'));
create policy "قراءة بصلاحية عرض salaries" on salaries for select using (fn_has_permission('HR','عرض'));
create policy "تعديل بصلاحية salaries" on salaries for all using (fn_has_permission('HR','تعديل'));
create policy "قراءة بصلاحية عرض attendance" on attendance for select using (fn_has_permission('HR','عرض'));
create policy "تعديل بصلاحية attendance" on attendance for all using (fn_has_permission('HR','تعديل'));
create policy "قراءة بصلاحية عرض advances" on advances for select using (fn_has_permission('HR','عرض'));
create policy "تعديل بصلاحية advances" on advances for all using (fn_has_permission('HR','تعديل'));
create policy "قراءة بصلاحية عرض journal" on journal_entries for select using (fn_has_permission('Reports','عرض'));
create policy "قراءة بصلاحية عرض log" on operations_log for select using (fn_has_permission('Users','عرض'));
create policy "قراءة بصلاحية عرض seasons" on seasons for select using (auth.role() = 'authenticated');
create policy "تعديل بصلاحية seasons" on seasons for all using (fn_has_permission('Reports','تعديل'));
create policy "قراءة بصلاحية عرض backup" on backup_log for select using (fn_has_permission('Settings','عرض'));
