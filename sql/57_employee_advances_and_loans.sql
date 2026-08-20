-- ============================================================
-- الدفعة 57 (نسخة مصححة):
-- (أ) سلف الموظفين — استخدمت جدول "advances" الموجود بالفعل
--     (بدل ما أعمل جدول جديد يتعارض معاه)، وبس ضفتله عمود
--     "settled_amount" عشان يدعم التسوية الجزئية (مش بس
--     كامل/مش مدفوع زي ما كان). رصيد السلفة المتبقي = المبلغ
--     الأصلي - المسوّى لحد دلوقتي.
-- (ب) قروض المحل (جدول جديد بالكامل) — استلام (جديد أو رصيد
--     افتتاحي)، وسداد كامل أو جزئي.
-- (ج) مصروف مرتبات "آجل" بقى بيروح لحساب "أجور مستحقة" مخصص.
-- (د) "قرض" بقى بيتصنف خصوم أوتوماتيك في fn_resolve_account.
-- (قابلة لإعادة التشغيل بأمان بالكامل)
-- ============================================================

alter table advances add column if not exists settled_amount numeric(12,2) not null default 0;

create table if not exists loans (
  id uuid primary key default gen_random_uuid(),
  name text not null, principal numeric(12,2) not null, remaining_balance numeric(12,2) not null,
  created_at timestamptz not null default now()
);
alter table loans enable row level security;
drop policy if exists "قراءة loans" on loans;
create policy "قراءة loans" on loans for select using (auth.role() = 'authenticated');

create table if not exists loan_log (
  id uuid primary key default gen_random_uuid(), loan_id uuid references loans(id),
  type text check (type in ('استلام','سداد')), amount numeric(12,2) not null,
  treasury_account_id uuid, note text default '', created_at timestamptz not null default now()
);
alter table loan_log enable row level security;
drop policy if exists "قراءة loan_log" on loan_log;
create policy "قراءة loan_log" on loan_log for select using (auth.role() = 'authenticated');

create or replace function rpc_settle_employee_advance(p_employee_id uuid, p_amount numeric, p_treasury_account_id uuid, p_note text default '')
returns void language plpgsql security definer as $$
declare v_name text; v_total_outstanding numeric; v_remaining_payment numeric; v_row record; v_take numeric;
begin
  if not fn_has_permission('HR', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'المبلغ مطلوب'; end if;
  select name into v_name from employees where id = p_employee_id;
  if v_name is null then raise exception 'الموظف غير موجود'; end if;

  select coalesce(sum(amount - settled_amount), 0) into v_total_outstanding from advances where employee_id = p_employee_id;
  if p_amount > v_total_outstanding then raise exception 'المبلغ أكبر من رصيد السلف المتبقي (% متبقي)', v_total_outstanding; end if;

  v_remaining_payment := p_amount;
  for v_row in select * from advances where employee_id = p_employee_id and settled_amount < amount order by advance_date asc loop
    exit when v_remaining_payment <= 0;
    v_take := least(v_remaining_payment, v_row.amount - v_row.settled_amount);
    update advances set settled_amount = settled_amount + v_take, deducted = (settled_amount + v_take >= amount) where id = v_row.id;
    v_remaining_payment := v_remaining_payment - v_take;
  end loop;

  perform fn_move_treasury('داخل', p_amount, p_treasury_account_id, 'تسوية سلفة — ' || v_name || coalesce(' — ' || nullif(p_note,''), ''));
  perform fn_journal_entry('الخزينة', 'سلف الموظفين', p_amount, 'ADV-S-' || extract(epoch from now())::bigint::text, 'تسوية سلفة — ' || v_name);
  perform fn_log_operation('SETTLE_EMPLOYEE_ADVANCE', jsonb_build_object('employee', v_name, 'amount', p_amount));
end;
$$;

create or replace function rpc_list_employee_advance_balances()
returns table(employee_id uuid, employee_name text, balance numeric)
language sql security definer as $$
  select e.id, e.name, coalesce(sum(a.amount - a.settled_amount), 0) as balance
  from employees e left join advances a on a.employee_id = e.id
  group by e.id, e.name
  having coalesce(sum(a.amount - a.settled_amount), 0) > 0
  order by e.name;
$$;

create or replace function rpc_add_loan(p_name text, p_principal numeric, p_treasury_account_id uuid default null, p_is_opening boolean default false)
returns uuid language plpgsql security definer as $$
declare v_id uuid;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_name is null or trim(p_name) = '' then raise exception 'اسم القرض مطلوب'; end if;
  if p_principal is null or p_principal <= 0 then raise exception 'المبلغ مطلوب'; end if;
  if not p_is_opening and p_treasury_account_id is null then raise exception 'حددي هيتحط في أنهي خزنة/بنك'; end if;

  insert into loans (name, principal, remaining_balance) values (p_name, p_principal, p_principal) returning id into v_id;
  insert into loan_log (loan_id, type, amount, treasury_account_id, note) values (v_id, 'استلام', p_principal, p_treasury_account_id, 'بداية القرض');

  if p_is_opening then
    perform fn_journal_entry('رصيد افتتاحي', 'قرض — ' || p_name, p_principal, 'LOAN-' || v_id::text, 'رصيد افتتاحي قرض — ' || p_name);
  else
    perform fn_move_treasury('داخل', p_principal, p_treasury_account_id, 'استلام قرض — ' || p_name);
    perform fn_journal_entry('الخزينة', 'قرض — ' || p_name, p_principal, 'LOAN-' || v_id::text, 'استلام قرض — ' || p_name);
  end if;

  perform fn_log_operation('ADD_LOAN', jsonb_build_object('name', p_name, 'principal', p_principal, 'opening', p_is_opening));
  return v_id;
end;
$$;

create or replace function rpc_repay_loan(p_loan_id uuid, p_amount numeric, p_treasury_account_id uuid, p_note text default '')
returns void language plpgsql security definer as $$
declare v_name text; v_remaining numeric;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'المبلغ مطلوب'; end if;
  select name, remaining_balance into v_name, v_remaining from loans where id = p_loan_id;
  if v_name is null then raise exception 'القرض غير موجود'; end if;
  if p_amount > v_remaining then raise exception 'المبلغ أكبر من المتبقي على القرض (% متبقي)', v_remaining; end if;

  update loans set remaining_balance = remaining_balance - p_amount where id = p_loan_id;
  insert into loan_log (loan_id, type, amount, treasury_account_id, note) values (p_loan_id, 'سداد', p_amount, p_treasury_account_id, p_note);

  perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, 'سداد قرض — ' || v_name);
  perform fn_journal_entry('قرض — ' || v_name, 'الخزينة', p_amount, 'LOAN-R-' || extract(epoch from now())::bigint::text, 'سداد قرض — ' || v_name);
  perform fn_log_operation('REPAY_LOAN', jsonb_build_object('loan', v_name, 'amount', p_amount));
end;
$$;

do $$
declare v_sig record;
begin
  for v_sig in select oid::regprocedure as sig from pg_proc where proname = 'rpc_add_expense'
  loop
    execute 'drop function if exists ' || v_sig.sig || ' cascade';
  end loop;
end $$;

create or replace function rpc_add_expense(
  p_main_category text, p_amount numeric, p_sub_category text default '', p_description text default '',
  p_is_recurring boolean default false, p_recurrence_days int default null, p_is_fixed_asset boolean default false,
  p_payment_method text default 'كاش', p_employee_id uuid default null, p_bonus numeric default null,
  p_expense_date timestamptz default now(), p_treasury_account_id uuid default null,
  p_useful_life_months int default 36, p_depreciation_method text default 'شهري'
)
returns uuid language plpgsql security definer as $$
declare v_id uuid; v_credit_account text;
begin
  perform fn_check_period_open(p_expense_date);
  if not fn_has_permission('Expenses', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'المبلغ لازم يكون أكبر من صفر'; end if;
  if p_main_category is null or trim(p_main_category) = '' then raise exception 'الفئة الرئيسية مطلوبة'; end if;

  if p_is_fixed_asset then
    insert into fixed_assets (description, amount, acquired_at, useful_life_months, depreciation_method, treasury_account_id)
    values (coalesce(nullif(p_description,''), p_main_category), p_amount, p_expense_date, greatest(coalesce(p_useful_life_months,36),1), coalesce(p_depreciation_method,'شهري'), p_treasury_account_id)
    returning id into v_id;

    if p_payment_method <> 'آجل' then
      perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, coalesce(nullif(p_description,''), p_main_category));
    end if;

    perform fn_journal_entry('الأصول الثابتة', case when p_payment_method = 'آجل' then 'دائنون آخرون' else 'الخزينة' end,
      p_amount, p_main_category, 'شراء أصل ثابت — ' || coalesce(nullif(p_description,''), p_main_category));

    perform fn_log_operation('ADD_FIXED_ASSET', jsonb_build_object('description', p_description, 'amount', p_amount));
    return v_id;
  end if;

  insert into expenses (expense_date, main_category, sub_category, description, amount, is_recurring, recurrence_days, is_fixed_asset, payment_method, employee_id, bonus, treasury_account_id, created_by)
  values (p_expense_date, p_main_category, coalesce(p_sub_category,''), coalesce(p_description,''), p_amount, p_is_recurring, p_recurrence_days, false, p_payment_method, p_employee_id, p_bonus, p_treasury_account_id, auth.uid())
  returning id into v_id;

  if p_payment_method <> 'آجل' then
    perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, coalesce(nullif(p_description,''), p_main_category));
    v_credit_account := 'الخزينة';
  elsif p_main_category ilike 'مرتبات%' or p_main_category ilike 'المرتبات%' then
    v_credit_account := 'أجور مستحقة';
  else
    v_credit_account := 'دائنون آخرون';
  end if;

  perform fn_journal_entry('المصروفات: ' || p_main_category, v_credit_account, p_amount, p_main_category, coalesce(nullif(p_description,''), p_main_category));

  perform fn_log_operation('ADD_EXPENSE', jsonb_build_object('category', p_main_category, 'amount', p_amount));
  return v_id;
end;
$$;

create or replace function fn_resolve_account(p_name text)
returns uuid language plpgsql security definer as $$
declare
  v_id uuid; v_type text; v_parent_code text; v_parent_id uuid;
  v_max_n int; v_new_code text; v_sub_group text; v_attempt int;
begin
  if p_name is null or trim(p_name) = '' then return null; end if;

  select id into v_id from accounts where name = p_name;
  if v_id is not null then return v_id; end if;

  v_type := case
    when p_name ilike 'المصروفات%' or p_name ilike 'تكلفة البضاعة%' or p_name ilike '%اهلاك%' or p_name ilike '%إهلاك%' or p_name ilike 'المرتبات%' then 'مصروفات'
    when p_name ilike 'المبيعات%' or p_name ilike '%إيرادات%' then 'إيرادات'
    when p_name ilike '%رأس المال%' then 'حقوق ملكية'
    when p_name ilike '%الموردون%' or p_name ilike '%دائن%' or p_name ilike 'شيكات دفع%' or p_name ilike 'مستحقات%' or p_name ilike 'أجور مستحقة%' or p_name ilike 'قرض%' then 'خصوم'
    else 'أصول'
  end;

  if p_name ilike 'رأس المال —%' then
    select id into v_parent_id from accounts where name = 'رأس المال';
    if v_parent_id is null then
      select id into v_parent_id from accounts where code = '3';
      insert into accounts (code, name, type, is_group, parent_id) values ('3.001', 'رأس المال', 'حقوق ملكية', true, v_parent_id) returning id into v_parent_id;
    end if;
    select code into v_parent_code from accounts where id = v_parent_id;
  else
    v_parent_code := case v_type
      when 'مصروفات' then '5' when 'إيرادات' then '4' when 'حقوق ملكية' then '3'
      when 'خصوم' then '2.1'
      else '1.1'
    end;
    select id into v_parent_id from accounts where code = v_parent_code;
  end if;

  v_sub_group := case v_parent_code when '1.1' then 'أصول متداولة' when '2.1' then 'خصوم متداولة' else null end;

  v_attempt := 0;
  loop
    v_attempt := v_attempt + 1;
    select coalesce(max(substring(code from '([0-9]+)$')::int), 0) into v_max_n from accounts where parent_id = v_parent_id;
    v_new_code := v_parent_code || '.' || lpad((v_max_n + 1 + (v_attempt - 1))::text, 3, '0');
    begin
      insert into accounts (code, name, type, is_group, parent_id, sub_group)
      values (v_new_code, p_name, v_type, false, v_parent_id, v_sub_group)
      returning id into v_id;
      return v_id;
    exception when unique_violation then
      if v_attempt >= 20 then raise; end if;
    end;
  end loop;
end;
$$;

grant execute on all functions in schema public to authenticated;
