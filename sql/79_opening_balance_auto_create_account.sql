-- ============================================================
-- الدفعة 79: تسجيل رصيد افتتاحي على حساب جديد (بيتعمل تلقائيًا)
-- من غير ما تحتاجي تروحي "شجرة الحسابات" وتضيفيه بنفسك الأول
--
-- بتاخد اسم الحساب ونوعه (أصول/خصوم/حقوق ملكية) — لو الاسم مش
-- موجود، بيتعمل حساب جديد بكود مناسب تلقائي تحت المجموعة الصح،
-- ولو موجود بالفعل بيستخدمه زي ما هو.
-- ============================================================

create or replace function rpc_add_opening_balance_new_account(
  p_account_name text, p_account_type text, p_amount numeric,
  p_description text default '', p_as_of_date date default current_date
)
returns uuid language plpgsql security definer as $$
declare
  v_account_id uuid; v_id uuid; v_equity_account text := 'رصيد افتتاحي';
  v_parent_code text; v_parent_id uuid; v_sub_group text; v_max_n int; v_new_code text; v_attempt int := 0;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount = 0 then raise exception 'المبلغ مطلوب'; end if;
  if p_account_name is null or trim(p_account_name) = '' then raise exception 'اسم الحساب مطلوب'; end if;
  if p_account_type not in ('أصول','خصوم','حقوق ملكية','إيرادات','مصروفات') then raise exception 'نوع الحساب غير معروف'; end if;

  select id into v_account_id from accounts where name = p_account_name;

  if v_account_id is null then
    v_parent_code := case p_account_type
      when 'أصول' then '1.1' when 'خصوم' then '2.1' when 'حقوق ملكية' then '3'
      when 'إيرادات' then '4' else '5'
    end;
    select id into v_parent_id from accounts where code = v_parent_code;
    v_sub_group := case v_parent_code when '1.1' then 'أصول متداولة' when '2.1' then 'خصوم متداولة' else null end;

    loop
      v_attempt := v_attempt + 1;
      select coalesce(max(substring(code from '([0-9]+)$')::int), 0) into v_max_n from accounts where parent_id = v_parent_id;
      v_new_code := v_parent_code || '.' || lpad((v_max_n + v_attempt)::text, 3, '0');
      begin
        insert into accounts (code, name, type, is_group, parent_id, sub_group)
        values (v_new_code, p_account_name, p_account_type, false, v_parent_id, v_sub_group)
        returning id into v_account_id;
        exit;
      exception when unique_violation then
        if v_attempt > 20 then raise; end if;
      end;
    end loop;
  end if;

  insert into opening_balances (as_of_date, account_id, amount, description, locked)
  values (p_as_of_date, v_account_id, p_amount, p_description, true)
  returning id into v_id;

  if p_account_type in ('أصول','مصروفات') then
    perform fn_journal_entry(p_account_name, v_equity_account, p_amount, 'OB-' || v_id::text, 'رصيد افتتاحي — ' || coalesce(p_description,''));
  else
    perform fn_journal_entry(v_equity_account, p_account_name, p_amount, 'OB-' || v_id::text, 'رصيد افتتاحي — ' || coalesce(p_description,''));
  end if;

  perform fn_log_operation('ADD_OPENING_BALANCE', jsonb_build_object('account', p_account_name, 'amount', p_amount, 'auto_created', true));
  return v_id;
end;
$$;

grant execute on all functions in schema public to authenticated;
