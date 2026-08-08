-- ============================================================
-- الدفعة 25: مرتجع منتج مباشر — إضافة ربط اختياري برقم فاتورة
-- (لو المرتجع تابع لبيعة معينة وعايزة تسجّلي رقمها للمرجعية،
-- من غير ما نرجع لأسلوب "دوري عن الفاتورة" القديم المعقد)
-- ============================================================

create or replace function rpc_record_standalone_return(
  p_items jsonb, p_payment_method text default 'كاش', p_treasury_account_id uuid default null,
  p_notes text default '', p_sale_reference text default null
)
returns jsonb language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_cost numeric; v_price numeric; v_qty numeric;
  v_subtotal numeric := 0; v_total_cogs numeric := 0; v_is_cash boolean; v_ref text; v_desc text;
begin
  perform fn_check_period_open(now());
  if not fn_has_permission('Sales', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

  v_ref := 'RET-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || floor(random()*900+100)::text;
  v_is_cash := p_payment_method is not null and p_payment_method <> 'آجل';
  v_desc := 'مرتجع منتج' || (case when p_sale_reference is not null and p_sale_reference <> '' then ' — تابع لفاتورة ' || p_sale_reference else ' مباشر' end)
            || (case when p_notes is not null and p_notes <> '' then ' — ' || p_notes else '' end);

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost into v_variant_id, v_cost from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    v_price := coalesce((v_item->>'price')::numeric, 0);

    update product_variants set quantity = quantity + v_qty where id = v_variant_id;

    v_subtotal := v_subtotal + (v_price * v_qty);
    v_total_cogs := v_total_cogs + (coalesce(v_cost, 0) * v_qty);
  end loop;

  perform fn_journal_entry('المبيعات', case when v_is_cash then 'الخزينة' else 'العملاء (مدينون)' end, v_subtotal, coalesce(p_sale_reference, v_ref), v_desc);
  if v_total_cogs > 0 then
    perform fn_journal_entry('المخزون', 'تكلفة البضاعة المباعة', v_total_cogs, coalesce(p_sale_reference, v_ref), 'عكس تكلفة بضاعة — ' || v_desc);
  end if;
  if v_is_cash then
    perform fn_move_treasury('خارج', v_subtotal, p_treasury_account_id, v_desc);
  end if;

  perform fn_log_operation('STANDALONE_RETURN', jsonb_build_object('ref', v_ref, 'sale_reference', p_sale_reference, 'total', v_subtotal, 'cogs', v_total_cogs));
  return jsonb_build_object('ref', v_ref, 'total', v_subtotal);
end;
$$;

grant execute on all functions in schema public to authenticated;
