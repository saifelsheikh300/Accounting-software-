-- ============================================================
-- الدفعة 48: توزيع رأس المال الافتتاحي على الشركاء من غير ما
-- يلمس الخزنة خالص.
--
-- الفرق عن "رأس المال والشركاء" العادية: الشاشة دي بتفترض إن
-- الشريك حاطط فلوس جديدة فعليًا دلوقتي (فبتحط القيد مقابل
-- "الخزينة" تلقائي). لو انتي أصلاً سجلتي الخزنة والمخزون
-- والعملاء كأرصدة افتتاحية لوحدهم، ورأس المال ده مجرد توضيح
-- إن الفلوس/الأصول دي بتاعة مين من الشركاء، فده مجرد نقل
-- تصنيف من "رصيد افتتاحي" العام لحساب الشريك المحدد — من غير
-- ما يضيف أي فلوس جديدة في الخزنة.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

create or replace function rpc_add_partner_opening_capital(
  p_partner_name text, p_amount numeric, p_as_of_date date default current_date, p_description text default ''
)
returns void language plpgsql security definer as $$
declare v_partner_account text := 'رأس المال — ' || p_partner_name;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_partner_name is null or trim(p_partner_name) = '' then raise exception 'اسم الشريك مطلوب'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'المبلغ مطلوب'; end if;

  if not exists (select 1 from partners where name = p_partner_name) then
    insert into partners (name, balance) values (p_partner_name, 0);
  end if;

  -- تصنيف بس، من غير ما يلمس الخزنة أو أي أصل تاني
  perform fn_journal_entry('رصيد افتتاحي', v_partner_account, p_amount, 'OB-CAP-' || extract(epoch from now())::bigint::text,
    'توزيع رأس المال الافتتاحي — ' || p_partner_name || coalesce(' — ' || nullif(p_description,''), ''));

  perform fn_log_operation('ADD_PARTNER_OPENING_CAPITAL', jsonb_build_object('partner', p_partner_name, 'amount', p_amount));
end;
$$;

grant execute on all functions in schema public to authenticated;
