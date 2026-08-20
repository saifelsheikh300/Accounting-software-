-- ============================================================
-- الدفعة 58: دعم دفع المرتب على أجزاء (كان لازم يتدفع كامل مرة
-- واحدة بس). دلوقتي ممكن تدفعي جزء أول الشهر وجزء تاني آخره،
-- وهيفضل "لسه مش مدفوع بالكامل" لحد ما يوصل لصافي المرتب.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

alter table salaries add column if not exists paid_amount numeric(12,2) not null default 0;

create or replace function rpc_pay_salary(p_month_label text, p_employee_name text, p_treasury_account_id uuid default null, p_amount numeric default null)
returns void language plpgsql security definer as $$
declare v_emp_id uuid; v_net numeric; v_paid_so_far numeric; v_remaining numeric; v_pay numeric;
begin
  if not fn_has_permission('HR', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select id into v_emp_id from employees where name = p_employee_name;
  if v_emp_id is null then raise exception 'الموظف غير موجود'; end if;

  select net, paid_amount into v_net, v_paid_so_far from salaries where month_label = p_month_label and employee_id = v_emp_id;
  if v_net is null then raise exception 'مرتب الشهر ده لسه ما اتجهزش لهذا الموظف'; end if;

  v_remaining := v_net - coalesce(v_paid_so_far, 0);
  if v_remaining <= 0 then raise exception 'المرتب ده متدفوع بالكامل بالفعل'; end if;

  v_pay := coalesce(p_amount, v_remaining);
  if v_pay <= 0 then raise exception 'المبلغ لازم يكون أكبر من صفر'; end if;
  if v_pay > v_remaining then raise exception 'المبلغ أكبر من المتبقي على المرتب (% متبقي)', v_remaining; end if;

  update salaries set paid_amount = coalesce(paid_amount,0) + v_pay, paid = (coalesce(paid_amount,0) + v_pay >= v_net)
  where month_label = p_month_label and employee_id = v_emp_id;

  perform fn_move_treasury('خارج', v_pay, p_treasury_account_id, 'راتب ' || p_employee_name || ' — ' || p_month_label);
  perform fn_journal_entry('المرتبات', 'الخزينة', v_pay, p_employee_name, 'راتب ' || p_employee_name || ' — ' || p_month_label);
  perform fn_log_operation('PAY_SALARY', jsonb_build_object('employee', p_employee_name, 'month', p_month_label, 'amount', v_pay));
end;
$$;

grant execute on all functions in schema public to authenticated;
