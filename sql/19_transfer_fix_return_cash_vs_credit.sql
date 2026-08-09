-- ============================================================
-- الدفعة 19: إصلاحان إضافيان من نفس فئة مراجعة "الأسس المحاسبية"
-- 1) التحويل بين حسابات الخزنة كان فيه نفس باج balance_after
-- 2) مرتجع البيعة كان بيخصم من الخزنة دايمًا حتى لو البيعة
--    الأصلية كانت آجل (على فاتورة) — غلط محاسبيًا
-- ============================================================

-- ------------------------------------------------------------
-- 1) التحويل بين حسابات الخزنة — بقى بيستخدم fn_move_treasury
-- الموحّدة (بعد إصلاحها) بدل إدخال يدوي كان ناسي balance_after
-- ------------------------------------------------------------
create or replace function rpc_transfer_between_treasuries(p_from_id uuid, p_to_id uuid, p_amount numeric, p_notes text default '')
returns void language plpgsql security definer as $$
declare v_from_name text; v_to_name text;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  select name into v_from_name from treasury_accounts where id = p_from_id;
  select name into v_to_name from treasury_accounts where id = p_to_id;
  if v_from_name is null or v_to_name is null then raise exception 'حساب خزنة غير موجود'; end if;

  perform fn_move_treasury('خارج', p_amount, p_from_id, 'تحويل إلى ' || v_to_name || case when p_notes <> '' then ' — ' || p_notes else '' end);
  perform fn_move_treasury('داخل', p_amount, p_to_id, 'تحويل من ' || v_from_name || case when p_notes <> '' then ' — ' || p_notes else '' end);

  perform fn_log_operation('TRANSFER_TREASURY', jsonb_build_object('from', v_from_name, 'to', v_to_name, 'amount', p_amount));
end;
$$;

-- ------------------------------------------------------------
-- 2) مرتجع البيعة — بيفرّق دلوقتي بين بيعة كاش وبيعة آجل:
-- كاش: بيخصم من خزنة حقيقية (لو اتحددت) + قيد يقلل الخزينة
-- آجل: بيقلل مديونية العميل بس، من غير ما يلمس الخزنة خالص
-- ------------------------------------------------------------
create or replace function rpc_record_return(p_sale_id uuid, p_items jsonb, p_is_full boolean default true, p_treasury_account_id uuid default null)
returns void language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_qty numeric; v_total numeric := 0;
  v_sale_number text; v_payment_method text; v_is_cash boolean;
begin
  if not fn_has_permission('Sales', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select sale_number, payment_method into v_sale_number, v_payment_method from sales where id = p_sale_id;
  if v_sale_number is null then raise exception 'البيعة غير موجودة'; end if;
  v_is_cash := v_payment_method is not null and v_payment_method <> 'آجل';

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id into v_variant_id from product_variants where code = v_item->>'variant_code';
    v_qty := (v_item->>'qty')::numeric;
    update product_variants set quantity = quantity + v_qty where id = v_variant_id;
    v_total := v_total + (coalesce((v_item->>'price')::numeric, 0) * v_qty);
  end loop;

  update sales set status = case when p_is_full then 'مرتجع كلي' else 'مرتجع جزئي' end where id = p_sale_id;

  perform fn_journal_entry('المبيعات', case when v_is_cash then 'الخزينة' else 'العملاء (مدينون)' end, v_total, v_sale_number, 'مرتجع بيعة ' || v_sale_number);

  if v_is_cash then
    perform fn_move_treasury('خارج', v_total, p_treasury_account_id, 'مرتجع بيعة ' || v_sale_number);
  end if;

  perform fn_log_operation('RECORD_RETURN', jsonb_build_object('sale_number', v_sale_number, 'was_cash', v_is_cash));
end;
$$;

grant execute on all functions in schema public to authenticated;
