-- ============================================================
-- الدفعة 26: إكمال إصلاح تضارب الدوال المكررة (Overloading)
-- ملف 23 مسح تضارب 8 دوال، لكن فاتت دالتين اتغيرت باراميتراتهم
-- بعد كده من غير drop للنسخة القديمة:
--   1) rpc_record_return — اتغيرت من 3 باراميتر (ملف 04) لـ4 (ملف 19)
--   2) rpc_record_standalone_return — اتغيرت من 4 باراميتر (ملف 24) لـ5 (ملف 25)
-- النتيجة المحتملة: نسختين شغالين لكل دالة في قاعدة البيانات فعليًا.
-- الحل: نفس أسلوب ملف 23 بالظبط — مسح كل نسخ الدالتين دول،
-- وإعادة إنشاء النسخة الصحيحة النهائية بس لكل واحدة.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

do $$
declare v_func text;
declare v_sig record;
begin
  foreach v_func in array array[
    'rpc_record_return', 'rpc_record_standalone_return'
  ]
  loop
    for v_sig in select oid::regprocedure as sig from pg_proc where proname = v_func
    loop
      execute 'drop function if exists ' || v_sig.sig || ' cascade';
    end loop;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 1) rpc_record_return — النسخة النهائية (مرتجع مرتبط بفاتورة بيع)
-- ------------------------------------------------------------
create or replace function rpc_record_return(p_sale_id uuid, p_items jsonb, p_is_full boolean default true, p_treasury_account_id uuid default null)
returns void language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_qty numeric; v_total numeric := 0; v_total_cogs numeric := 0;
  v_sale_number text; v_payment_method text; v_is_cash boolean; v_unit_cost numeric; v_sale_date timestamptz;
begin
  if not fn_has_permission('Sales', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select sale_number, payment_method, sale_date into v_sale_number, v_payment_method, v_sale_date from sales where id = p_sale_id;
  if v_sale_number is null then raise exception 'البيعة غير موجودة'; end if;
  perform fn_check_period_open(now());
  v_is_cash := v_payment_method is not null and v_payment_method <> 'آجل';

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id into v_variant_id from product_variants where code = v_item->>'variant_code';
    v_qty := (v_item->>'qty')::numeric;

    select unit_cost into v_unit_cost from sale_items where sale_id = p_sale_id and variant_id = v_variant_id limit 1;
    v_unit_cost := coalesce(v_unit_cost, 0);

    update product_variants set quantity = quantity + v_qty where id = v_variant_id;
    v_total := v_total + (coalesce((v_item->>'price')::numeric, 0) * v_qty);
    v_total_cogs := v_total_cogs + (v_unit_cost * v_qty);
  end loop;

  update sales set status = case when p_is_full then 'مرتجع كلي' else 'مرتجع جزئي' end where id = p_sale_id;

  perform fn_journal_entry('المبيعات', case when v_is_cash then 'الخزينة' else 'العملاء (مدينون)' end, v_total, v_sale_number, 'مرتجع بيعة ' || v_sale_number);
  if v_total_cogs > 0 then
    perform fn_journal_entry('المخزون', 'تكلفة البضاعة المباعة', v_total_cogs, v_sale_number, 'عكس تكلفة بضاعة مرتجع ' || v_sale_number);
  end if;

  if v_is_cash then
    perform fn_move_treasury('خارج', v_total, p_treasury_account_id, 'مرتجع بيعة ' || v_sale_number);
  end if;

  perform fn_log_operation('RECORD_RETURN', jsonb_build_object('sale_number', v_sale_number, 'was_cash', v_is_cash, 'cogs_reversed', v_total_cogs));
end;
$$;

-- ------------------------------------------------------------
-- 2) rpc_record_standalone_return — النسخة النهائية (مرتجع مباشر
--    مع ربط اختياري برقم فاتورة)
-- ------------------------------------------------------------
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
