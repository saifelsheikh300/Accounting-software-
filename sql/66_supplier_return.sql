-- ============================================================
-- الدفعة 66: مرتجع مورد (إرجاع بضاعة لمورد بعد أوردر شراء)
--
-- المبدأ المحاسبي:
--   لما نرجع بضاعة لمورد، إحنا بنعكس جزء من عملية الشراء الأصلية:
--     - المخزون بينقص بتكلفة الشراء الأصلية (مش سعر البيع)
--     - لو لسه فيه مبلغ متبقي مستحق للمورد (remaining)، بننزله
--       منه الأول (دائن: الموردون تقل التزاماتنا)
--     - لو قيمة المرتجع أكبر من المتبقي (يعني كنا دافعين جزء أو
--       كله كاش)، الفرق ده بيرجعلنا كاش من المورد (مدين: الخزينة)
--   الأصناف بترجع من نفس دفعة الشراء (batch) اللي جت منها الأوردر
--   ده بالظبط (نفس التكلفة)، ومينفعش نرجع كمية اتباعت جزء منها
--   بالفعل لعميل — لازم تتوفر في المخزون فعليًا.
-- (قابلة لإعادة التشغيل بأمان بالكامل)
-- ============================================================

do $$
declare v_sig record;
begin
  for v_sig in select oid::regprocedure as sig from pg_proc where proname = 'rpc_record_supplier_return'
  loop
    execute 'drop function if exists ' || v_sig.sig || ' cascade';
  end loop;
end $$;

create or replace function rpc_record_supplier_return(
  p_order_id uuid, p_items jsonb, p_treasury_account_id uuid default null, p_notes text default ''
)
returns jsonb language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_qty numeric; v_batch_qty_left numeric;
  v_unit_cost numeric; v_order_number text; v_remaining numeric; v_amount_paid numeric; v_total numeric;
  v_return_total numeric := 0; v_reduce_payable numeric; v_cash_refund numeric;
  v_new_remaining numeric; v_new_paid numeric; v_new_total numeric; v_new_status text;
begin
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  perform fn_check_period_open(now());
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

  select order_number, remaining, amount_paid, total into v_order_number, v_remaining, v_amount_paid, v_total
  from purchase_orders where id = p_order_id;
  if v_order_number is null then raise exception 'أوردر الشراء غير موجود'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id into v_variant_id from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    if v_qty <= 0 then raise exception 'الكمية لازم تكون أكبر من صفر'; end if;

    -- لازم تكون الكمية دي لسه موجودة فعليًا من نفس دفعة الشراء دي (يعني لسه متباعتش)
    select coalesce(sum(quantity_remaining), 0) into v_batch_qty_left
    from inventory_batches where variant_id = v_variant_id and reference = v_order_number;
    if v_batch_qty_left < v_qty then
      raise exception 'مينفعش ترجعي % وحدة من الصنف % — المتاح فعليًا من نفس دفعة الشراء دي: %',
        v_qty, v_item->>'variant_code', v_batch_qty_left;
    end if;

    -- تكلفة الوحدة زي ما اتشرت بالظبط (نفس مرجع الأوردر ده)
    select unit_cost into v_unit_cost from inventory_batches
      where variant_id = v_variant_id and reference = v_order_number and quantity_remaining > 0
      order by received_at asc limit 1;
    v_unit_cost := coalesce(v_unit_cost, 0);

    -- نقص الكمية من دفعات الأوردر ده (الأحدث فالأقدم داخل نفس الأوردر مش فارق لأنها كلها بنفس التكلفة غالبًا)
    declare v_take numeric; v_left numeric := v_qty; v_b record;
    begin
      for v_b in select * from inventory_batches
        where variant_id = v_variant_id and reference = v_order_number and quantity_remaining > 0
        order by received_at asc for update
      loop
        exit when v_left <= 0;
        v_take := least(v_left, v_b.quantity_remaining);
        update inventory_batches set quantity_remaining = quantity_remaining - v_take where id = v_b.id;
        v_left := v_left - v_take;
      end loop;
    end;

    perform fn_sync_variant_from_fifo(v_variant_id);
    v_return_total := v_return_total + (v_unit_cost * v_qty);
  end loop;

  if v_return_total <= 0 then raise exception 'قيمة المرتجع لازم تكون أكبر من صفر'; end if;

  -- نقلل المتبقي المستحق للمورد الأول، وأي زيادة عنه بترجع كاش
  v_reduce_payable := least(v_return_total, v_remaining);
  v_cash_refund := v_return_total - v_reduce_payable;

  if v_reduce_payable > 0 then
    perform fn_journal_entry('الموردون', 'المخزون', v_reduce_payable, v_order_number, 'مرتجع مورد — تخفيض مستحقات ' || v_order_number);
  end if;
  if v_cash_refund > 0 then
    perform fn_journal_entry('الخزينة', 'المخزون', v_cash_refund, v_order_number, 'مرتجع مورد — استرداد كاش ' || v_order_number);
    perform fn_move_treasury('داخل', v_cash_refund, p_treasury_account_id, 'مرتجع مورد ' || v_order_number);
  end if;

  -- تحديث أوردر الشراء نفسه ليعكس المرتجع
  v_new_remaining := greatest(v_remaining - v_reduce_payable, 0);
  v_new_paid := greatest(v_amount_paid - v_cash_refund, 0);
  v_new_total := greatest(v_total - v_return_total, 0);
  v_new_status := case
    when v_new_remaining = 0 and v_new_total > 0 then 'مدفوع بالكامل'
    when v_new_paid = 0 then 'متأخر/غير مدفوع'
    else 'مدفوع جزئيًا'
  end;

  update purchase_orders set total = v_new_total, amount_paid = v_new_paid, remaining = v_new_remaining, payment_status = v_new_status
  where id = p_order_id;

  perform fn_log_operation('SUPPLIER_RETURN', jsonb_build_object(
    'order_number', v_order_number, 'return_total', v_return_total,
    'reduced_payable', v_reduce_payable, 'cash_refund', v_cash_refund, 'notes', p_notes
  ));

  return jsonb_build_object('order_number', v_order_number, 'return_total', v_return_total, 'reduced_payable', v_reduce_payable, 'cash_refund', v_cash_refund);
end;
$$;

grant execute on all functions in schema public to authenticated;

-- ------------------------------------------------------------
-- تحديث بسيط: rpc_get_supplier_statement كانت بترجع أوردرات الشراء
-- من غير الـ id بتاعها، وده لازم عشان شاشة "مرتجع مورد" الجديدة
-- تقدر تحدد الأوردر المطلوب إرجاع بضاعة منه.
-- ------------------------------------------------------------
create or replace function rpc_get_supplier_statement(p_supplier_id uuid)
returns jsonb language plpgsql security definer as $$
declare
  v_supplier jsonb; v_purchases jsonb; v_payments jsonb; v_total numeric; v_paid numeric; v_remaining numeric;
begin
  select to_jsonb(s) into v_supplier from suppliers s where id = p_supplier_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'orderId', id, 'orderNumber', order_number, 'date', order_date, 'total', total,
    'paymentStatus', payment_status, 'amountPaid', amount_paid, 'remaining', remaining
  ) order by order_date desc), '[]'::jsonb),
  coalesce(sum(total), 0), coalesce(sum(amount_paid), 0), coalesce(sum(remaining), 0)
  into v_purchases, v_total, v_paid, v_remaining
  from purchase_orders where supplier_id = p_supplier_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'orderNumber', po.order_number, 'amount', sp.amount, 'paidAt', sp.paid_at
  ) order by sp.paid_at desc), '[]'::jsonb)
  into v_payments
  from supplier_payments sp join purchase_orders po on po.id = sp.order_id
  where sp.supplier_id = p_supplier_id;

  return jsonb_build_object(
    'supplier', v_supplier, 'purchases', v_purchases, 'payments', v_payments,
    'totalPurchases', v_total, 'totalPaid', v_paid, 'totalRemaining', v_remaining
  );
end;
$$;

grant execute on all functions in schema public to authenticated;
