-- ============================================================
-- الدفعة 22: مرتجع مبسّط — بحث عن المنتج مباشرة وعمل مرتجع له
-- من غير الحاجة للبحث عن رقم فاتورة قديمة خالص. بيزوّد المخزون
-- وبيقلل الإيراد (وتكلفة البضاعة المباعة) عن طريق قيد محاسبي،
-- بدون الحاجة لربطه بأي بيعة معينة.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

create or replace function rpc_record_standalone_return(
  p_items jsonb, p_payment_method text default 'كاش', p_treasury_account_id uuid default null, p_notes text default ''
)
returns jsonb language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_cost numeric; v_price numeric; v_qty numeric;
  v_subtotal numeric := 0; v_total_cogs numeric := 0; v_is_cash boolean; v_ref text;
begin
  perform fn_check_period_open(now());
  if not fn_has_permission('Sales', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

  v_ref := 'RET-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || floor(random()*900+100)::text;
  v_is_cash := p_payment_method is not null and p_payment_method <> 'آجل';

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost into v_variant_id, v_cost from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    v_price := coalesce((v_item->>'price')::numeric, 0);

    update product_variants set quantity = quantity + v_qty where id = v_variant_id;

    v_subtotal := v_subtotal + (v_price * v_qty);
    v_total_cogs := v_total_cogs + (coalesce(v_cost, 0) * v_qty);
  end loop;

  perform fn_journal_entry('المبيعات', case when v_is_cash then 'الخزينة' else 'العملاء (مدينون)' end, v_subtotal, v_ref, 'مرتجع منتج مباشر — ' || coalesce(nullif(p_notes,''), v_ref));
  if v_total_cogs > 0 then
    perform fn_journal_entry('المخزون', 'تكلفة البضاعة المباعة', v_total_cogs, v_ref, 'عكس تكلفة بضاعة مرتجع — ' || v_ref);
  end if;
  if v_is_cash then
    perform fn_move_treasury('خارج', v_subtotal, p_treasury_account_id, 'مرتجع منتج مباشر — ' || v_ref);
  end if;

  perform fn_log_operation('STANDALONE_RETURN', jsonb_build_object('ref', v_ref, 'total', v_subtotal, 'cogs', v_total_cogs));
  return jsonb_build_object('ref', v_ref, 'total', v_subtotal);
end;
$$;

grant execute on all functions in schema public to authenticated;
