-- ============================================================
-- الدفعة 6: تعديل الفئات + تعديل المنتجات + إضافة منتج مع
-- متغيراته (ألوان/مقاسات) دفعة واحدة في نداء واحد
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

-- ------------------------------------------------------------
-- 1) تعديل اسم فئة (رئيسية أو فرعية) — الكود مبيتغيرش، بس الاسم
-- ------------------------------------------------------------
create or replace function rpc_update_category(p_code text, p_new_name text)
returns void language plpgsql security definer as $$
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_new_name is null or trim(p_new_name) = '' then raise exception 'الاسم مطلوب'; end if;

  update product_tree set name = p_new_name where code = p_code;
  if not found then raise exception 'الفئة غير موجودة: %', p_code; end if;

  perform fn_log_operation('UPDATE_CATEGORY', jsonb_build_object('code', p_code, 'name', p_new_name));
end;
$$;

-- ------------------------------------------------------------
-- 2) تعديل بيانات منتج موجود (الاسم/السعر/الفئة الفرعية/الصورة/الوصف)
-- الكود الهرمي بتاع المنتج مبيتغيرش حتى لو غيّرتي الفئة
-- ------------------------------------------------------------
create or replace function rpc_update_product(
  p_code text, p_name text, p_base_price numeric, p_sub_category_code text,
  p_image text default null, p_description text default null
)
returns void language plpgsql security definer as $$
declare v_sub_id uuid; v_main_id uuid;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_name is null or trim(p_name) = '' then raise exception 'اسم المنتج مطلوب'; end if;

  select id, parent_id into v_sub_id, v_main_id from product_tree where code = p_sub_category_code;
  if v_sub_id is null then raise exception 'الفئة الفرعية غير موجودة'; end if;

  update products set
    name = p_name,
    base_price = p_base_price,
    sub_category_id = v_sub_id,
    main_category_id = v_main_id,
    image_url = coalesce(p_image, image_url),
    description = coalesce(p_description, description)
  where code = p_code;

  if not found then raise exception 'المنتج غير موجود: %', p_code; end if;

  perform fn_log_operation('UPDATE_PRODUCT', jsonb_build_object('code', p_code, 'name', p_name));
end;
$$;

-- ------------------------------------------------------------
-- 3) إضافة منتج جديد + كل متغيراته (ألوان/مقاسات) في نداء واحد Atomic
-- p_variants shape: [{"color":"أسود","size":"M","quantity":10,"cost":80}, ...]
-- ممكن تبعتي مصفوفة فاضية [] لو المنتج من غير متغيرات (زي rpc_add_product القديمة بالظبط)
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

  if p_variants is not null and jsonb_array_length(p_variants) > 0 then
    for v_variant in select * from jsonb_array_elements(p_variants) loop
      v_wh := coalesce(nullif(v_variant->>'warehouseId', '')::uuid, (select id from warehouses order by created_at limit 1));
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
    update products set has_variants = true where id = v_product_id;
  end if;

  perform fn_log_operation('ADD_PRODUCT_WITH_VARIANTS', jsonb_build_object('code', v_product_code, 'variants', v_variant_codes));
  return jsonb_build_object('productCode', v_product_code, 'variantCodes', v_variant_codes);
end;
$$;

grant execute on all functions in schema public to authenticated;
