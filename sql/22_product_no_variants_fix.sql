-- ============================================================
-- الدفعة 22: إصلاح جذري — منتج من غير متغيرات كان بيتحفظ من غير
-- أي صف في product_variants، فيبقى غير قابل للبيع أو الشراء أو
-- حتى الظهور في أي بحث، رغم إنه ظاهر في صفحة المخزون كـ"موجود"
-- ============================================================

-- ------------------------------------------------------------
-- 1) تصحيح تاريخي: أي منتج حالي عنده has_variants = false ومالوش
-- ولا صف في product_variants — نضيفله متغير افتراضي واحد
-- ------------------------------------------------------------
insert into product_variants (code, product_id, color, size, quantity, cost, warehouse_id, low_stock_threshold)
select p.code || '-DEF', p.id, '', '', 0, p.base_price,
       (select id from warehouses order by created_at limit 1), 5
from products p
where not exists (select 1 from product_variants v where v.product_id = p.id)
  and p.deleted_at is null;

update products set has_variants = true
where id in (select product_id from product_variants) and has_variants = false;

-- ------------------------------------------------------------
-- 2) تعديل دالة الإضافة: لو مفيش متغيرات محددة، تتعمل واحدة
-- افتراضية تلقائيًا بدل ما المنتج يفضل بلا متغيرات خالص
-- ------------------------------------------------------------
create or replace function rpc_add_product_with_variants(
  p_name text, p_sub_category_code text, p_base_price numeric, p_variants jsonb default '[]'::jsonb,
  p_image text default '', p_description text default '', p_manual_code text default null
)
returns jsonb language plpgsql security definer as $$
declare
  v_sub_id uuid; v_main_id uuid; v_max int; v_product_code text; v_product_id uuid;
  v_variant jsonb; v_variant_code text; v_wh uuid; v_variant_codes jsonb := '[]'::jsonb;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_name is null or trim(p_name) = '' then raise exception 'اسم المنتج مطلوب'; end if;

  select id, parent_id into v_sub_id, v_main_id from product_tree where code = p_sub_category_code;
  if v_sub_id is null then raise exception 'الفئة الفرعية غير موجودة'; end if;

  if p_manual_code is not null and p_manual_code <> '' then
    v_product_code := p_manual_code;
  else
    select coalesce(max(substring(p.code from length(p_sub_category_code)+1)::int), 0) into v_max
    from products p where p.code like p_sub_category_code || '%';
    v_product_code := p_sub_category_code || lpad((v_max + 1)::text, 3, '0');
  end if;

  insert into products (code, name, main_category_id, sub_category_id, base_price, image_url, description)
  values (v_product_code, p_name, v_main_id, v_sub_id, p_base_price, p_image, p_description)
  returning id into v_product_id;

  v_wh := (select id from warehouses order by created_at limit 1);

  if p_variants is null or jsonb_array_length(p_variants) = 0 then
    -- ✅ الإصلاح: متغير افتراضي واحد بدل ما المنتج يفضل بلا متغيرات
    v_variant_code := v_product_code || '-DEF';
    insert into product_variants (code, product_id, color, size, quantity, cost, warehouse_id, low_stock_threshold)
    values (v_variant_code, v_product_id, '', '', 0, p_base_price, v_wh, 5);
    v_variant_codes := jsonb_build_array(v_variant_code);
  else
    for v_variant in select * from jsonb_array_elements(p_variants) loop
      v_wh := coalesce(nullif(v_variant->>'warehouseId', '')::uuid, v_wh);
      v_variant_code := v_product_code || '-' || upper(left(coalesce(v_variant->>'color', ''), 2)) || '-' || upper(coalesce(v_variant->>'size', ''));

      insert into product_variants (code, product_id, color, size, quantity, cost, special_price, warehouse_id, low_stock_threshold)
      values (
        v_variant_code, v_product_id, v_variant->>'color', v_variant->>'size',
        coalesce((v_variant->>'quantity')::numeric, 0), coalesce((v_variant->>'cost')::numeric, 0),
        nullif(v_variant->>'specialPrice', '')::numeric, v_wh,
        coalesce((v_variant->>'lowStockThreshold')::numeric, 5)
      );

      v_variant_codes := v_variant_codes || jsonb_build_array(v_variant_code);
    end loop;
  end if;

  update products set has_variants = true where id = v_product_id;

  perform fn_log_operation('ADD_PRODUCT_WITH_VARIANTS', jsonb_build_object('code', v_product_code, 'variants', v_variant_codes));
  return jsonb_build_object('productCode', v_product_code, 'variantCodes', v_variant_codes);
end;
$$;

grant execute on all functions in schema public to authenticated;
