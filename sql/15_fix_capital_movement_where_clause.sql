-- ============================================================
-- الدفعة 15: إصلاح خطأ "UPDATE requires a WHERE clause" عند
-- إضافة/سحب رأس مال — Supabase بيمنع أي UPDATE من غير شرط WHERE
-- كإجراء أمان، وسطر إعادة حساب نسبة الملكية كان من غيره
-- ============================================================

create or replace function rpc_add_capital_movement(p_partner_name text, p_type text, p_amount numeric, p_notes text default '')
returns numeric language plpgsql security definer as $$
declare v_partner_id uuid; v_last_balance numeric; v_new_balance numeric; v_total_capital numeric;
begin
  if not fn_has_permission('Capital', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select id, balance into v_partner_id, v_last_balance from partners where name = p_partner_name;
  if v_partner_id is null then
    insert into partners (name, balance) values (p_partner_name, 0) returning id, balance into v_partner_id, v_last_balance;
  end if;

  v_new_balance := v_last_balance + (case when p_type = 'سحب رأس مال' then -abs(p_amount) else abs(p_amount) end);

  insert into capital_movements (partner_id, type, amount, balance_after, notes) values (v_partner_id, p_type, abs(p_amount), v_new_balance, p_notes);
  update partners set balance = v_new_balance where id = v_partner_id;

  -- إعادة حساب نسبة الملكية لكل الشركاء (where true عشان Supabase محتاج شرط WHERE دايمًا)
  select sum(balance) into v_total_capital from partners;
  update partners set ownership_percent = case when v_total_capital > 0 then round((balance / v_total_capital) * 100, 2) else 0 end
  where true;

  perform fn_log_operation('ADD_CAPITAL_MOVEMENT', jsonb_build_object('partner', p_partner_name, 'type', p_type, 'amount', p_amount));
  return v_new_balance;
end;
$$;

grant execute on all functions in schema public to authenticated;
