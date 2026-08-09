-- ============================================================
-- الدفعة 18: إصلاح باج — عمود balance_after في cash_flow مكنش
-- بيتحسب عند تحريك خزنة حقيقية (رأس المال، وأي عملية تانية عن
-- طريق fn_move_treasury)، فكارت "الخزنة" في الداشبورد كان بيعرض
-- رقم غلط بعد أي حركة من دي، رغم إن رصيد الحساب نفسه في صفحة
-- "الخزنة والبنوك" كان بيتحدث صح فعليًا
-- ============================================================

-- ------------------------------------------------------------
-- الهيلبر الموحّد: بقى بيحسب ويسجل balance_after زي ما كانت
-- fn_append_cash_flow بتعمل بالظبط، عشان كارت الداشبورد يفضل صح
-- ------------------------------------------------------------
create or replace function fn_move_treasury(p_direction text, p_amount numeric, p_treasury_account_id uuid, p_source text)
returns void language plpgsql security definer as $$
declare v_is_cash boolean; v_name text; v_last_balance numeric; v_new_balance numeric;
begin
  if p_amount is null or p_amount <= 0 then return; end if;

  select balance_after into v_last_balance from cash_flow order by flow_date desc, id desc limit 1;
  v_last_balance := coalesce(v_last_balance, 0);
  v_new_balance := case when p_direction = 'داخل' then v_last_balance + p_amount else v_last_balance - p_amount end;

  if p_treasury_account_id is not null then
    select (type = 'كاش'), name into v_is_cash, v_name from treasury_accounts where id = p_treasury_account_id;
    if v_name is null then raise exception 'حساب الخزنة/البنك غير موجود'; end if;

    update treasury_accounts set current_balance = current_balance + (case when p_direction = 'داخل' then p_amount else -p_amount end)
    where id = p_treasury_account_id;

    insert into cash_flow (direction, source, amount, treasury_account_id, is_cash, balance_after)
    values (p_direction, p_source, p_amount, p_treasury_account_id, v_is_cash, v_new_balance);
  else
    perform fn_append_cash_flow(p_direction, p_source, p_amount, true);
  end if;
end;
$$;

-- ------------------------------------------------------------
-- إعادة تعريف رأس المال عشان يستخدم fn_move_treasury الموحّدة
-- بدل نسخة داخلية منفصلة كانت فيها نفس الباج بالظبط
-- ------------------------------------------------------------
create or replace function rpc_add_capital_movement(
  p_partner_name text, p_type text, p_amount numeric, p_notes text default '', p_treasury_account_id uuid default null
)
returns numeric language plpgsql security definer as $$
declare
  v_partner_id uuid; v_last_balance numeric; v_new_balance numeric; v_total_capital numeric; v_direction text;
begin
  if not fn_has_permission('Capital', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select id, balance into v_partner_id, v_last_balance from partners where name = p_partner_name;
  if v_partner_id is null then
    insert into partners (name, balance) values (p_partner_name, 0) returning id, balance into v_partner_id, v_last_balance;
  end if;

  v_new_balance := v_last_balance + (case when p_type = 'سحب رأس مال' then -abs(p_amount) else abs(p_amount) end);

  insert into capital_movements (partner_id, type, amount, balance_after, notes) values (v_partner_id, p_type, abs(p_amount), v_new_balance, p_notes);
  update partners set balance = v_new_balance where id = v_partner_id;

  select sum(balance) into v_total_capital from partners;
  update partners set ownership_percent = case when v_total_capital > 0 then round((balance / v_total_capital) * 100, 2) else 0 end
  where true;

  v_direction := case when p_type = 'سحب رأس مال' then 'خارج' else 'داخل' end;
  perform fn_move_treasury(v_direction, abs(p_amount), p_treasury_account_id, p_type || ' — ' || p_partner_name);

  perform fn_journal_entry(
    case when v_direction = 'داخل' then 'الخزينة' else 'رأس المال — ' || p_partner_name end,
    case when v_direction = 'داخل' then 'رأس المال — ' || p_partner_name else 'الخزينة' end,
    abs(p_amount), p_partner_name, p_type || ' — ' || p_partner_name
  );

  perform fn_log_operation('ADD_CAPITAL_MOVEMENT', jsonb_build_object('partner', p_partner_name, 'type', p_type, 'amount', p_amount));
  return v_new_balance;
end;
$$;

grant execute on all functions in schema public to authenticated;

-- ------------------------------------------------------------
-- تصليح تاريخي (يُشغَّل مرة واحدة بس): إعادة حساب balance_after
-- لكل حركات cash_flow القديمة بالترتيب الزمني الصحيح — عشان أي
-- حركة اتسجلت بالباج (من وقت تشغيل الملف 17 لحد دلوقتي) ترجع صح
-- ------------------------------------------------------------
do $$
declare v_row record; v_running numeric := 0;
begin
  for v_row in select id, direction, amount from cash_flow order by flow_date asc, id asc loop
    v_running := v_running + (case when v_row.direction = 'داخل' then v_row.amount else -v_row.amount end);
    update cash_flow set balance_after = v_running where id = v_row.id;
  end loop;
end $$;
