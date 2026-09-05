-- ============================================================
-- الدفعة 86: إصلاح تغيير مورد الأوردر (كان بيحدّث الأوردر بس، مش
-- المنتجات اللي جواه)
--
-- كل منتج فيه عمود منفصل (supplier_id) بيسجل "آخر مورد اتشرى منه"،
-- وده بيتحدّث تلقائي بس وقت الشراء الفعلي (عن طريق trigger).
-- لما غيّرنا مورد الأوردر، الأوردر نفسه اتحدّث صح، لكن المنتجات
-- فضلت شايلة المورد القديم لأن حاجة محدش حدّثها فيها. دلوقتي
-- بتتزامن مع المورد الجديد كمان في نفس الخطوة.
-- ============================================================

create or replace function rpc_reassign_purchase_order_supplier(p_order_id uuid, p_new_supplier_name text)
returns void language plpgsql security definer as $$
declare v_new_supplier_id uuid; v_order_number text;
begin
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_new_supplier_name is null or trim(p_new_supplier_name) = '' then raise exception 'اسم المورد الجديد مطلوب'; end if;

  select id into v_new_supplier_id from suppliers where name = p_new_supplier_name;
  if v_new_supplier_id is null then
    insert into suppliers (name) values (p_new_supplier_name) returning id into v_new_supplier_id;
  end if;

  select order_number into v_order_number from purchase_orders where id = p_order_id;
  if v_order_number is null then raise exception 'الأوردر غير موجود'; end if;

  update purchase_orders set supplier_id = v_new_supplier_id where id = p_order_id;
  update supplier_payments set supplier_id = v_new_supplier_id where order_id = p_order_id;

  -- ✅ الإصلاح الجديد: تحديث المنتجات اللي جوه الأوردر ده عشان تتزامن مع المورد الجديد
  update products set supplier_id = v_new_supplier_id
  where id in (
    select pv.product_id from purchase_order_items poi
    join product_variants pv on pv.id = poi.variant_id
    where poi.purchase_order_id = p_order_id
  );

  perform fn_log_operation('REASSIGN_PURCHASE_ORDER_SUPPLIER', jsonb_build_object('order_number', v_order_number, 'new_supplier', p_new_supplier_name));
end;
$$;

grant execute on all functions in schema public to authenticated;
