-- ============================================================
-- الدفعة 61: حذف قيد بيتراجع فعليًا دلوقتي، مش بس بيمسح السطر:
-- (أ) لو القيد فيه "الخزينة"، بيسألك أنهي خزنة/بنك ترجعله
--     الفلوس (أو تتخصم منه لو كان القيد نفسه تحصيل)، ويعدّل
--     رصيدها فعليًا.
-- (ب) لو القيد ده كان "رصيد افتتاحي أصل ثابت" (من شاشة الأصول
--     الثابتة)، بيمسح الأصل نفسه من "الأصول الثابتة" كمان.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

create or replace function rpc_delete_journal_entry(p_id uuid, p_treasury_account_id uuid default null)
returns void language plpgsql security definer as $$
declare v_entry record; v_fa_id uuid;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select * into v_entry from journal_entries where id = p_id;
  if v_entry is null then raise exception 'القيد غير موجود'; end if;

  -- ✅ عكس أثر الخزنة لو كانت طرف في القيد
  if v_entry.debit_account = 'الخزينة' and p_treasury_account_id is not null then
    -- كانت الفلوس داخلة للخزينة (مدين) → لازم تتسحب دلوقتي
    perform fn_move_treasury('خارج', v_entry.amount, p_treasury_account_id, 'تراجع عن قيد محذوف — ' || coalesce(v_entry.description,''));
  elsif v_entry.credit_account = 'الخزينة' and p_treasury_account_id is not null then
    -- كانت الفلوس خارجة من الخزينة (دائن) → لازم ترجع دلوقتي
    perform fn_move_treasury('داخل', v_entry.amount, p_treasury_account_id, 'تراجع عن قيد محذوف — ' || coalesce(v_entry.description,''));
  end if;

  -- ✅ لو القيد ده كان رصيد افتتاحي لأصل ثابت، امسحي الأصل نفسه
  if v_entry.reference like 'OB-FA-%' then
    begin
      v_fa_id := split_part(v_entry.reference, 'OB-FA-', 2)::uuid;
      delete from fixed_assets where id = v_fa_id;
    exception when others then null;
    end;
  end if;

  delete from journal_entries where id = p_id;
  perform fn_log_operation('DELETE_JOURNAL_ENTRY', jsonb_build_object(
    'entry_number', v_entry.entry_number, 'debit', v_entry.debit_account, 'credit', v_entry.credit_account,
    'amount', v_entry.amount, 'description', v_entry.description
  ));
end;
$$;

grant execute on all functions in schema public to authenticated;
