-- ============================================================
-- الدفعة 63: الإيرادات الأخرى كانت بتعمل حساب جديد في شجرة
-- الحسابات لكل مصدر مختلف (زي "إيرادات أخرى — كراتين فاضية")
-- بدل ما تتحط كلها تحت حساب "إيرادات أخرى" الواحد وتتفرز بالتفصيل
-- من جوّاه. اتصلح: كل الإيرادات الأخرى بقت بتترحّل لنفس الحساب
-- (4.002)، وتفاصيل كل واحدة (المصدر، الوصف، المبلغ) موجودة في
-- جدول other_revenue وبتظهر لما تدوسي على الحساب في شجرة الحسابات.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

create or replace function rpc_add_other_revenue(p_source text, p_amount numeric, p_description text default '', p_treasury_account_id uuid default null)
returns uuid language plpgsql security definer as $$
declare v_id uuid;
begin
  perform fn_check_period_open(now());
  if not fn_has_permission('Expenses', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'المبلغ لازم يكون أكبر من صفر'; end if;

  insert into other_revenue (source, description, amount, created_by) values (p_source, coalesce(p_description,''), p_amount, auth.uid())
  returning id into v_id;

  perform fn_move_treasury('داخل', p_amount, p_treasury_account_id, coalesce(nullif(p_description,''), p_source));
  perform fn_journal_entry('الخزينة', 'إيرادات أخرى', p_amount, p_source, coalesce(nullif(p_description,''), p_source));

  perform fn_log_operation('ADD_OTHER_REVENUE', jsonb_build_object('source', p_source, 'amount', p_amount));
  return v_id;
end;
$$;

-- تنضيف الحسابات المكررة القديمة (زي "إيرادات أخرى — كراتين فاضية")
-- اللي اتعملت غلط قبل الإصلاح، ونقل رصيدها للحساب الصحيح
do $$
declare v_dup record; v_balance numeric; v_main_id uuid;
begin
  select id into v_main_id from accounts where name = 'إيرادات أخرى';
  if v_main_id is null then return; end if;

  for v_dup in select * from accounts where name like 'إيرادات أخرى —%' loop
    select coalesce(sum(amount) filter (where credit_account_id = v_dup.id),0) - coalesce(sum(amount) filter (where debit_account_id = v_dup.id),0)
    into v_balance from journal_entries;

    if v_balance <> 0 then
      if v_balance > 0 then
        perform fn_journal_entry(v_dup.name, 'إيرادات أخرى', v_balance, 'FIX-63-' || v_dup.id::text, 'تصحيح تصنيف — نقل لحساب إيرادات أخرى الموحد');
      else
        perform fn_journal_entry('إيرادات أخرى', v_dup.name, abs(v_balance), 'FIX-63-' || v_dup.id::text, 'تصحيح تصنيف — نقل لحساب إيرادات أخرى الموحد');
      end if;
    end if;

    delete from accounts where id = v_dup.id;
  end loop;
end $$;

grant execute on all functions in schema public to authenticated;
