-- ============================================================
-- الدفعة 78: جدولة أقساط قروض المحل (زي متابعة الشيكات المستحقة)
--
-- القروض كانت بس "أصلي / متبقي" من غير أي جدول سداد. دلوقتي كل
-- قرض ممكن يكون ليه قسط شهري ثابت وتاريخ استحقاق، والنظام:
--   - بيفكّرك قبل الاستحقاق بـ3 أيام (زي تذكير الشيكات بالظبط)
--   - بيدي زرار "دفع القسط المستحق" بمبلغ جاهز مسبقًا
--   - بيقدّم تاريخ الاستحقاق شهر لما تدفعي القسط
-- ============================================================

alter table loans add column if not exists monthly_installment numeric(12,2);
alter table loans add column if not exists next_due_date date;

create or replace function rpc_add_loan(
  p_name text, p_principal numeric, p_treasury_account_id uuid default null, p_is_opening boolean default false,
  p_monthly_installment numeric default null, p_next_due_date date default null
)
returns uuid language plpgsql security definer as $$
declare v_id uuid;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_name is null or trim(p_name) = '' then raise exception 'اسم القرض مطلوب'; end if;
  if p_principal is null or p_principal <= 0 then raise exception 'المبلغ مطلوب'; end if;
  if not p_is_opening and p_treasury_account_id is null then raise exception 'حددي هيتحط في أنهي خزنة/بنك'; end if;

  insert into loans (name, principal, remaining_balance, monthly_installment, next_due_date)
  values (p_name, p_principal, p_principal, p_monthly_installment, p_next_due_date) returning id into v_id;
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
declare v_name text; v_remaining numeric; v_next_due date;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'المبلغ مطلوب'; end if;
  select name, remaining_balance, next_due_date into v_name, v_remaining, v_next_due from loans where id = p_loan_id;
  if v_name is null then raise exception 'القرض غير موجود'; end if;
  if p_amount > v_remaining then raise exception 'المبلغ أكبر من المتبقي على القرض (% متبقي)', v_remaining; end if;

  update loans set remaining_balance = remaining_balance - p_amount,
    next_due_date = case when v_next_due is not null then v_next_due + interval '1 month' else null end
  where id = p_loan_id;
  insert into loan_log (loan_id, type, amount, treasury_account_id, note) values (p_loan_id, 'سداد', p_amount, p_treasury_account_id, p_note);

  perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, 'سداد قرض — ' || v_name);
  perform fn_journal_entry('قرض — ' || v_name, 'الخزينة', p_amount, 'LOAN-R-' || extract(epoch from now())::bigint::text, 'سداد قرض — ' || v_name);
  perform fn_log_operation('REPAY_LOAN', jsonb_build_object('loan', v_name, 'amount', p_amount));
end;
$$;

-- تذكير بأقساط القروض المستحقة قريبًا (زي الشيكات بالظبط)
create or replace function rpc_check_upcoming_loan_installments_due()
returns void language plpgsql security definer as $$
declare v_loan record;
begin
  for v_loan in select * from loans where remaining_balance > 0 and next_due_date between current_date and current_date + 3 loop
    perform fn_create_notification(p.id, 'قسط قرض مستحق قريبًا 🏦',
      'قرض ' || v_loan.name || ' — قسط ' || coalesce(v_loan.monthly_installment, v_loan.remaining_balance) || ' مستحق في ' || v_loan.next_due_date, 'advancesloans')
    from profiles p where p.role in ('أدمن','شريك');
  end loop;
end;
$$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'daily-loan-installment-reminders') then
    perform cron.unschedule('daily-loan-installment-reminders');
  end if;
exception when others then null;
end $$;
select cron.schedule('daily-loan-installment-reminders', '0 8 * * *', $$select rpc_check_upcoming_loan_installments_due()$$);

grant execute on all functions in schema public to authenticated;
