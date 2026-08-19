-- ============================================================
-- الدفعة 55: قفل رصيد أول مدة لأكتر من شريك بنسب ملكية، بدل
-- ما يكون صاحب واحد بس. كل شريك بياخد نصيبه من رأس المال
-- (المبلغ الكلي × نسبته)، وبيتسجل في جدول الشركاء بنسبة
-- ملكيته على طول (تظهر في "رأس المال والشركاء").
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

create or replace function rpc_finalize_opening_balance_to_capital_multi(p_partners jsonb)
returns numeric language plpgsql security definer as $$
declare
  v_ob_id uuid; v_balance numeric; v_total_pct numeric := 0; v_p jsonb; v_pct numeric; v_share numeric;
  v_name text; v_capital_account text; v_ref text := 'CLOSE-OB-' || extract(epoch from now())::bigint::text;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_partners) = 0 then raise exception 'لازم شريك واحد على الأقل'; end if;

  select id into v_ob_id from accounts where name = 'رصيد افتتاحي';
  if v_ob_id is null then raise exception 'مفيش حساب "رصيد افتتاحي" أصلاً'; end if;

  select coalesce(sum(amount) filter (where credit_account_id = v_ob_id),0) - coalesce(sum(amount) filter (where debit_account_id = v_ob_id),0)
  into v_balance from journal_entries;
  if v_balance = 0 then raise exception 'رصيد "رصيد افتتاحي" صفر أصلاً — مفيش حاجة تتنقل'; end if;

  select sum((p->>'percent')::numeric) into v_total_pct from jsonb_array_elements(p_partners) p;
  if abs(v_total_pct - 100) > 0.5 then raise exception 'مجموع نسب الشركاء لازم يساوي 100%% (دلوقتي %', v_total_pct; end if;

  for v_p in select * from jsonb_array_elements(p_partners) loop
    v_name := v_p->>'name';
    v_pct := (v_p->>'percent')::numeric;
    v_share := round(abs(v_balance) * v_pct / 100, 2);
    v_capital_account := 'رأس المال — ' || v_name;

    if v_balance > 0 then
      perform fn_journal_entry('رصيد افتتاحي', v_capital_account, v_share, v_ref, 'قفل رصيد أول مدة لرأس المال — ' || v_name || ' (' || v_pct || '%%)');
    else
      perform fn_journal_entry(v_capital_account, 'رصيد افتتاحي', v_share, v_ref, 'قفل رصيد أول مدة لرأس المال — ' || v_name || ' (' || v_pct || '%%)');
    end if;

    if exists (select 1 from partners where name = v_name) then
      update partners set balance = balance + v_share, ownership_percent = v_pct where name = v_name;
    else
      insert into partners (name, balance, ownership_percent) values (v_name, v_share, v_pct);
    end if;
  end loop;

  perform fn_log_operation('FINALIZE_OPENING_BALANCE_MULTI', jsonb_build_object('partners', p_partners, 'total', v_balance));
  return v_balance;
end;
$$;

grant execute on all functions in schema public to authenticated;
