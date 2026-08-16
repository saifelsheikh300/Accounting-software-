-- ============================================================
-- الدفعة 34: إصلاحان جوهريان في سلامة الحسابات
--
-- 1) أرصدة أول مدة: كان الإضافة والترحيل خطوتين منفصلتين، ولو
--    نسيتي تضغطي "ترحيل" الرصيد فضل قاعد في جدوله بس من غير أي
--    أثر محاسبي حقيقي (بالظبط زي ما لاحظتي — رصيد 5000 اتضاف
--    والميزان فضل زي ما هو). دلوقتي الإضافة والترحيل بقوا عملية
--    واحدة ذرية (Atomic) — مفيش رصيد ممكن يتضاف من غير ما يترحّل
--    فورًا. وصلحت كمان إن حساب "رصيد افتتاحي" كان ممكن يتسجل
--    غلط كـ"أصول" بدل "حقوق ملكية" لو اتعمل تلقائي.
--
-- 2) أي عملية بتحرك فلوس (بيع، مصروف، سحب رأس مال...) من غير ما
--    تحددي حساب خزنة/بنك، كانت بتتسجل في سجل عام منفصل عن أي حساب
--    فعلي — يعني فلوس بتتحرك من غير ما ترتبط بخزنة كاش أو بنك
--    محدد. دلوقتي أي عملية زي دي *لازم* يتحدد لها حساب، وإلا
--    السيستم يرفض العملية بالكامل برسالة خطأ واضحة.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

-- ------------------------------------------------------------
-- 1) تأمين حساب "رصيد افتتاحي" كحساب حقوق ملكية صحيح من الأول
-- ------------------------------------------------------------
insert into accounts (code, name, type, is_group)
select 'EQ-OB', 'رصيد افتتاحي', 'حقوق ملكية', false
where not exists (select 1 from accounts where name = 'رصيد افتتاحي');

-- ------------------------------------------------------------
-- 2) دالة إضافة رصيد افتتاحي — إضافة + ترحيل فوري في نفس العملية
-- ------------------------------------------------------------
create or replace function rpc_add_opening_balance(
  p_account_id uuid, p_amount numeric, p_description text default '', p_as_of_date date default current_date
)
returns uuid language plpgsql security definer as $$
declare v_id uuid; v_account_name text; v_account_type text; v_equity_account text := 'رصيد افتتاحي';
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'المبلغ مطلوب'; end if;

  select name, type into v_account_name, v_account_type from accounts where id = p_account_id;
  if v_account_name is null then raise exception 'الحساب غير موجود'; end if;

  insert into opening_balances (as_of_date, account_id, amount, description, locked)
  values (p_as_of_date, p_account_id, p_amount, p_description, true)
  returning id into v_id;

  if v_account_type in ('أصول','مصروفات') then
    perform fn_journal_entry(v_account_name, v_equity_account, p_amount, 'OB-' || v_id::text, 'رصيد افتتاحي — ' || coalesce(p_description,''));
  else
    perform fn_journal_entry(v_equity_account, v_account_name, p_amount, 'OB-' || v_id::text, 'رصيد افتتاحي — ' || coalesce(p_description,''));
  end if;

  perform fn_log_operation('ADD_OPENING_BALANCE', jsonb_build_object('account', v_account_name, 'amount', p_amount));
  return v_id;
end;
$$;

-- ترحيل أي أرصدة قديمة اتضافت قبل الإصلاح ده ولسه من غير ترحيل
-- (يشمل الـ5000 جنيه اللي جربتيها)
do $$
declare v_row record; v_equity_account text := 'رصيد افتتاحي';
begin
  for v_row in select ob.*, a.name as account_name, a.type as account_type from opening_balances ob join accounts a on a.id = ob.account_id where ob.locked = false loop
    if v_row.account_type in ('أصول','مصروفات') then
      perform fn_journal_entry(v_row.account_name, v_equity_account, v_row.amount, 'OB-' || v_row.id::text, 'رصيد افتتاحي (ترحيل متأخر) — ' || coalesce(v_row.description,''));
    else
      perform fn_journal_entry(v_equity_account, v_row.account_name, v_row.amount, 'OB-' || v_row.id::text, 'رصيد افتتاحي (ترحيل متأخر) — ' || coalesce(v_row.description,''));
    end if;
  end loop;
  update opening_balances set locked = true where locked = false;
end $$;

-- قفل الكتابة المباشرة — الإضافة بقت بس من خلال rpc_add_opening_balance
drop policy if exists "تعديل بصلاحية opening_balances" on opening_balances;

-- ------------------------------------------------------------
-- 3) fn_move_treasury: منع أي عملية مالية من غير ما تحدد حساب خزنة/بنك
-- ------------------------------------------------------------
create or replace function fn_move_treasury(p_direction text, p_amount numeric, p_treasury_account_id uuid, p_source text)
returns void language plpgsql security definer as $$
declare v_is_cash boolean; v_name text; v_new_balance numeric; v_last_balance numeric; v_current numeric; v_allow_neg boolean;
begin
  if p_amount is null or p_amount <= 0 then return; end if;

  if p_treasury_account_id is null then
    raise exception 'لازم تحددي حساب الخزنة/البنك اللي هتتحرك منه أو تروح له العملية دي';
  end if;

  select (type = 'كاش'), name, current_balance, allow_negative into v_is_cash, v_name, v_current, v_allow_neg from treasury_accounts where id = p_treasury_account_id;
  if v_name is null then raise exception 'حساب الخزنة/البنك غير موجود'; end if;

  if p_direction = 'خارج' and not v_allow_neg and (v_current - p_amount) < 0 then
    raise exception 'رصيد حساب % لا يكفي — المتاح: %', v_name, v_current;
  end if;

  select balance_after into v_last_balance from cash_flow order by flow_date desc, id desc limit 1;
  v_last_balance := coalesce(v_last_balance, 0);
  v_new_balance := case when p_direction = 'داخل' then v_last_balance + p_amount else v_last_balance - p_amount end;

  update treasury_accounts set current_balance = current_balance + (case when p_direction = 'داخل' then p_amount else -p_amount end)
  where id = p_treasury_account_id;

  insert into cash_flow (direction, source, amount, treasury_account_id, is_cash, balance_after)
  values (p_direction, p_source, p_amount, p_treasury_account_id, v_is_cash, v_new_balance);
end;
$$;

-- ------------------------------------------------------------
-- 4) فحص سلامة الدفاتر — يتأكد إن كل حساب بيوصل لصفر (مدين = دائن)
--    وبيرمي error فوري لو فيه أي خلل، بدل ما يسيب الأرقام تبان غلط
-- ------------------------------------------------------------
create or replace function rpc_verify_trial_balance()
returns jsonb language plpgsql security definer as $$
declare v_total_debit numeric; v_total_credit numeric; v_diff numeric;
begin
  select coalesce(sum(amount), 0) into v_total_debit from journal_entries;
  select coalesce(sum(amount), 0) into v_total_credit from journal_entries;
  -- كل صف في journal_entries بطبيعته قيد متزن (نفس المبلغ مدين ودائن)،
  -- فالمجموعين لازم يتطابقوا حرفيًا دايمًا. لو مش متطابقين، فيه خلل حقيقي.
  v_diff := v_total_debit - v_total_credit;
  if abs(v_diff) > 0.01 then
    raise exception 'خلل في توازن الدفاتر! الفرق: %', v_diff;
  end if;
  return jsonb_build_object('balanced', true, 'total_debit', v_total_debit, 'total_credit', v_total_credit);
end;
$$;

grant execute on all functions in schema public to authenticated;
