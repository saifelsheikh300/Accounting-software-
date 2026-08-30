-- ============================================================
-- الدفعة 76: نظام استهلاك المصروفات المدفوعة مقدمًا (تلقائي زي الإهلاك)
--
-- المبدأ: مصروف مدفوع مقدمًا (زي إيجار 3 شهور دفعة واحدة) بيتسجل
-- الأول كـ"أصل" (حق ليك)، وبعدين كل شهر بيتحول جزء منه لمصروف
-- حقيقي في قائمة الدخل — بالظبط زي إهلاك الأصول الثابتة.
--
-- ده جدول تتبع منفصل: مش بيعمل القيد الافتتاحي (لأن ده اتسجل
-- بالفعل من شاشة "أرصدة أول مدة" العادية)، هو بس بيتابع الاستهلاك
-- الشهري من تاريخ معين.
-- ============================================================

create table if not exists prepaid_expenses (
  id uuid primary key default gen_random_uuid(),
  description text not null,
  total_amount numeric(12,2) not null,
  amortized_so_far numeric(12,2) not null default 0,
  monthly_amount numeric(12,2) not null,
  start_month text not null, -- أول شهر يستهلك فيه، بصيغة YYYY-MM (زي '2026-03')
  asset_account text not null default 'مصروفات مدفوعة مقدماً',
  expense_account text not null,
  last_amortized_month text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table prepaid_expenses enable row level security;
drop policy if exists "قراءة بصلاحية عرض prepaid" on prepaid_expenses;
create policy "قراءة بصلاحية عرض prepaid" on prepaid_expenses for select using (fn_has_permission('Reports','عرض'));

-- تسجيل مصروف مقدم موجود بالفعل (رصيده الافتتاحي اتسجل من قبل)
-- عشان يبدأ يتابعه ويستهلكه تلقائيًا من start_month
create or replace function rpc_register_prepaid_expense(
  p_description text, p_total_amount numeric, p_monthly_amount numeric,
  p_start_month text, p_expense_account text, p_asset_account text default 'مصروفات مدفوعة مقدماً',
  p_already_amortized numeric default 0
)
returns uuid language plpgsql security definer as $$
declare v_id uuid;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_total_amount <= 0 or p_monthly_amount <= 0 then raise exception 'المبالغ لازم تكون أكبر من صفر'; end if;

  insert into prepaid_expenses (description, total_amount, amortized_so_far, monthly_amount, start_month, asset_account, expense_account)
  values (p_description, p_total_amount, coalesce(p_already_amortized,0), p_monthly_amount, p_start_month, p_asset_account, p_expense_account)
  returning id into v_id;

  perform fn_log_operation('REGISTER_PREPAID_EXPENSE', jsonb_build_object('description', p_description, 'total', p_total_amount, 'monthly', p_monthly_amount));
  return v_id;
end;
$$;

-- تشغيل الاستهلاك الشهري (زرار يدوي أو جدولة تلقائية أول كل شهر)
create or replace function rpc_run_prepaid_amortization()
returns void language plpgsql security definer as $$
declare v_item record; v_amount numeric; v_month text := to_char(now(),'YYYY-MM');
begin
  if not fn_has_permission('Reports','تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  for v_item in select * from prepaid_expenses
    where active and amortized_so_far < total_amount
    and coalesce(last_amortized_month,'') <> v_month
    and v_month >= start_month
  loop
    v_amount := least(v_item.monthly_amount, v_item.total_amount - v_item.amortized_so_far);
    if v_amount > 0 then
      update prepaid_expenses set amortized_so_far = amortized_so_far + v_amount, last_amortized_month = v_month where id = v_item.id;
      perform fn_journal_entry(v_item.expense_account, v_item.asset_account, v_amount, v_item.id::text, 'استهلاك مصروف مقدم — ' || v_item.description || ' — ' || v_month);
    end if;
  end loop;

  perform fn_log_operation('RUN_PREPAID_AMORTIZATION', jsonb_build_object('month', v_month));
end;
$$;

grant execute on all functions in schema public to authenticated;
