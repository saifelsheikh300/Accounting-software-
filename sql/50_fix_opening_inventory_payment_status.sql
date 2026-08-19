-- ============================================================
-- الدفعة 50: إصلاح خطأ "duplicate key/check constraint
-- purchase_orders_payment_status_check" اللي كان بيظهر عند
-- تسجيل مخزون افتتاحي.
--
-- السبب: الدالة كانت بتحط قيمة "آجل بالكامل" لحالة الدفع، لكن
-- الجدول مايقبلش غير 3 قيم بالظبط: مدفوع بالكامل / مدفوع جزئيًا
-- / متأخر/غير مدفوع. استخدمت "متأخر/غير مدفوع" بدلها.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

create or replace function rpc_add_opening_inventory(
  p_supplier_name text, p_items jsonb, p_owed_amount numeric default 0,
  p_as_of_date date default current_date, p_warehouse_id uuid default null
)
returns table(order_number text, total numeric, owed numeric, settled_from_capital numeric)
language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_old_cost numeric; v_old_qty numeric; v_qty numeric; v_price numeric;
  v_new_avg_cost numeric; v_total numeric := 0; v_supplier_id uuid; v_order_id uuid; v_order_number text;
  v_owed numeric; v_settled numeric; v_method text;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

  select value into v_method from settings where key = 'inventoryValuationMethod';
  v_method := coalesce(v_method, 'متوسط مرجح');

  select id into v_supplier_id from suppliers where name = p_supplier_name;
  if v_supplier_id is null then raise exception 'المورد غير موجود — ضيفيه الأول من شاشة الموردين'; end if;

  v_order_number := 'OB-PO-' || to_char(now(), 'YYYYMMDDHH24MISS');

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_total := v_total + ((v_item->>'price')::numeric * (v_item->>'qty')::numeric);
  end loop;

  v_owed := least(greatest(coalesce(p_owed_amount, 0), 0), v_total);
  v_settled := v_total - v_owed;

  insert into purchase_orders (order_number, supplier_id, total, payment_status, amount_paid, remaining, warehouse_id)
  values (v_order_number, v_supplier_id, v_total,
    case when v_owed = 0 then 'مدفوع بالكامل' when v_owed = v_total then 'متأخر/غير مدفوع' else 'مدفوع جزئيًا' end,
    v_settled, v_owed, p_warehouse_id)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost, quantity into v_variant_id, v_old_cost, v_old_qty from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المتغير غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    v_price := (v_item->>'price')::numeric;

    insert into purchase_order_items (purchase_order_id, variant_id, qty, unit_price) values (v_order_id, v_variant_id, v_qty, v_price);

    if v_method = 'متوسط مرجح' and (coalesce(v_old_qty,0) + v_qty) > 0 then
      v_new_avg_cost := ((coalesce(v_old_qty,0) * coalesce(v_old_cost,0)) + (v_qty * v_price)) / (coalesce(v_old_qty,0) + v_qty);
    else
      v_new_avg_cost := v_price;
    end if;

    update product_variants set quantity = quantity + v_qty, cost = v_new_avg_cost where id = v_variant_id;
    insert into cost_history (variant_id, old_cost, new_cost, quantity, source_ref) values (v_variant_id, v_old_cost, v_new_avg_cost, v_qty, v_order_number);
  end loop;

  -- ✅ مفيش أي حركة على الخزنة خالص هنا — القيمة بتتوزع بس بين
  -- "مديون بيها" (الموردون) و"متغطية من رأس المال الحالي" (رصيد افتتاحي)
  if v_owed > 0 then
    perform fn_journal_entry('المخزون', 'الموردون', v_owed, v_order_number, 'رصيد افتتاحي مخزون (مديون) — ' || p_supplier_name);
  end if;
  if v_settled > 0 then
    perform fn_journal_entry('المخزون', 'رصيد افتتاحي', v_settled, v_order_number, 'رصيد افتتاحي مخزون (متغطي) — ' || p_supplier_name);
  end if;

  perform fn_log_operation('ADD_OPENING_INVENTORY', jsonb_build_object('supplier', p_supplier_name, 'total', v_total, 'owed', v_owed));
  return query select v_order_number, v_total, v_owed, v_settled;
end;
$$;

grant execute on all functions in schema public to authenticated;
