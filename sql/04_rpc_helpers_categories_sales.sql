-- ============================================================
-- الجزء 4: دوال الأعمال المركّبة (RPC) — تُستدعى من الواجهة
-- عن طريق supabase.rpc('اسم_الدالة', {...})
-- كل دالة SECURITY DEFINER: بتتحقق من الصلاحية بنفسها، ثم تنفّذ
-- العملية بالكامل في معاملة واحدة (Atomic) بدل خطوات منفصلة
-- ============================================================

-- ------------------------------------------------------------
-- هيلبرز عامة
-- ------------------------------------------------------------
create or replace function fn_current_username()
returns text language sql stable as $$
  select username from profiles where id = auth.uid();
$$;

create or replace function fn_log_operation(p_operation text, p_details jsonb default '{}'::jsonb)
returns void language plpgsql security definer as $$
begin
  insert into operations_log (actor, operation, details)
  values (coalesce(fn_current_username(), 'SYSTEM'), p_operation, p_details);
end;
$$;

create or replace function fn_journal_entry(p_debit text, p_credit text, p_amount numeric, p_reference text, p_description text)
returns text language plpgsql security definer as $$
declare v_number text;
begin
  v_number := 'JE-' || lpad(nextval('journal_entry_seq')::text, 6, '0');
  insert into journal_entries (entry_number, description, debit_account, credit_account, amount, reference)
  values (v_number, p_description, p_debit, p_credit, p_amount, p_reference);
  return v_number;
end;
$$;

create or replace function fn_append_cash_flow(p_direction text, p_source text, p_amount numeric, p_is_cash boolean default true)
returns numeric language plpgsql security definer as $$
declare v_last numeric; v_new numeric;
begin
  select balance_after into v_last from cash_flow order by flow_date desc, id desc limit 1;
  v_last := coalesce(v_last, 0);
  v_new := case when p_direction = 'داخل' then v_last + p_amount else v_last - p_amount end;
  insert into cash_flow (direction, source, amount, balance_after, is_cash) values (p_direction, p_source, p_amount, v_new, p_is_cash);
  return v_new;
end;
$$;

-- ------------------------------------------------------------
-- توليد الأكواد الهرمية
-- ------------------------------------------------------------
create or replace function rpc_create_category(p_name text, p_type text, p_parent_code text default null)
returns table(code text, name text) language plpgsql security definer as $$
declare
  v_code text; v_max int; v_parent_id uuid;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  if p_type = 'رئيسية' then
    select coalesce(max(pt.code::int), 0) into v_max from product_tree pt where pt.type = 'رئيسية';
    v_code := (v_max + 1)::text;
    insert into product_tree (code, name, type) values (v_code, p_name, 'رئيسية');
  else
    select id into v_parent_id from product_tree where product_tree.code = p_parent_code;
    if v_parent_id is null then raise exception 'الفئة الرئيسية غير موجودة'; end if;

    select coalesce(max(substring(pt.code from length(p_parent_code)+1)::int), 0) into v_max
    from product_tree pt where pt.parent_id = v_parent_id and pt.type = 'فرعية';
    v_code := p_parent_code || (v_max + 1)::text;
    insert into product_tree (code, name, type, parent_id) values (v_code, p_name, 'فرعية', v_parent_id);
  end if;

  perform fn_log_operation('CREATE_CATEGORY', jsonb_build_object('code', v_code, 'name', p_name));
  return query select v_code, p_name;
end;
$$;

create or replace function rpc_add_product(p_name text, p_sub_category_code text, p_base_price numeric, p_image text default '', p_description text default '', p_manual_code text default null)
returns table(code text) language plpgsql security definer as $$
declare v_sub_id uuid; v_main_id uuid; v_max int; v_code text;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select id, parent_id into v_sub_id, v_main_id from product_tree where product_tree.code = p_sub_category_code;
  if v_sub_id is null then raise exception 'الفئة الفرعية غير موجودة'; end if;

  if p_manual_code is not null and p_manual_code <> '' then
    v_code := p_manual_code;
  else
    select coalesce(max(substring(p.code from length(p_sub_category_code)+1)::int), 0) into v_max
    from products p where p.code like p_sub_category_code || '%';
    v_code := p_sub_category_code || lpad((v_max + 1)::text, 3, '0');
  end if;

  insert into products (code, name, main_category_id, sub_category_id, base_price, image_url, description)
  values (v_code, p_name, v_main_id, v_sub_id, p_base_price, p_image, p_description);

  perform fn_log_operation('ADD_PRODUCT', jsonb_build_object('code', v_code, 'name', p_name));
  return query select v_code;
end;
$$;

create or replace function rpc_add_variant(
  p_product_code text, p_color text, p_size text, p_quantity numeric, p_cost numeric,
  p_special_price numeric default null, p_warehouse_id uuid default null, p_low_stock_threshold numeric default 5
)
returns table(code text) language plpgsql security definer as $$
declare v_product_id uuid; v_code text; v_wh uuid;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select id into v_product_id from products where products.code = p_product_code;
  if v_product_id is null then raise exception 'المنتج غير موجود'; end if;

  v_wh := coalesce(p_warehouse_id, (select id from warehouses order by created_at limit 1));
  v_code := p_product_code || '-' || upper(left(coalesce(p_color,''), 2)) || '-' || upper(coalesce(p_size,''));

  insert into product_variants (code, product_id, color, size, quantity, cost, special_price, warehouse_id, low_stock_threshold)
  values (v_code, v_product_id, p_color, p_size, p_quantity, p_cost, p_special_price, v_wh, p_low_stock_threshold);

  update products set has_variants = true where id = v_product_id;

  perform fn_log_operation('ADD_VARIANT', jsonb_build_object('code', v_code));
  return query select v_code;
end;
$$;

-- ------------------------------------------------------------
-- تسجيل بيعة (محل أو أونلاين) — Atomic بالكامل
-- p_items shape: [{"variant_code":"21001-AH-M","qty":2,"price":150}, ...]
-- ------------------------------------------------------------
create or replace function rpc_record_sale(
  p_source text, p_items jsonb, p_discount numeric default 0, p_payment_method text default null,
  p_invoice_id uuid default null, p_customer_name text default '', p_customer_phone text default '',
  p_warehouse_id uuid default null, p_sale_date timestamptz default now()
)
returns table(sale_id uuid, sale_number text, total numeric) language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_cost numeric; v_price numeric; v_qty numeric;
  v_subtotal numeric := 0; v_total numeric; v_sale_id uuid; v_sale_number text;
  v_is_cash boolean;
begin
  if not fn_has_permission('Sales', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم منتج واحد على الأقل'; end if;

  v_sale_number := 'S-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || floor(random()*900+100)::text;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost into v_variant_id, v_cost from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    v_price := coalesce((v_item->>'price')::numeric, 0);
    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  v_total := v_subtotal - coalesce(p_discount, 0);
  v_is_cash := p_payment_method is not null and p_payment_method <> 'آجل';

  insert into sales (sale_number, sale_date, source, subtotal, discount, total, payment_method, invoice_id, customer_name, customer_phone, warehouse_id, created_by)
  values (v_sale_number, p_sale_date, p_source, v_subtotal, coalesce(p_discount,0), v_total, p_payment_method, p_invoice_id, p_customer_name, p_customer_phone, p_warehouse_id, auth.uid())
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost into v_variant_id, v_cost from product_variants where code = v_item->>'variant_code';
    v_qty := (v_item->>'qty')::numeric;
    v_price := coalesce((v_item->>'price')::numeric, 0);

    insert into sale_items (sale_id, variant_id, qty, unit_price, unit_cost) values (v_sale_id, v_variant_id, v_qty, v_price, v_cost);

    update product_variants set quantity = quantity - v_qty where id = v_variant_id;
  end loop;

  perform fn_journal_entry(case when v_is_cash then 'الخزينة' else 'العملاء (مدينون)' end, 'المبيعات', v_total, v_sale_number, 'بيعة رقم ' || v_sale_number);
  if v_is_cash then perform fn_append_cash_flow('داخل', 'بيعة ' || v_sale_number, v_total, p_payment_method = 'كاش'); end if;

  -- تتبع العميل المتكرر
  if p_customer_phone is not null and p_customer_phone <> '' then
    insert into customers (phone, name, order_count, total_purchases, first_order_at)
    values (p_customer_phone, p_customer_name, 1, v_total, now())
    on conflict (phone) do update set
      order_count = customers.order_count + 1,
      total_purchases = customers.total_purchases + v_total,
      name = coalesce(nullif(excluded.name, ''), customers.name);
  end if;

  perform fn_log_operation('RECORD_SALE', jsonb_build_object('sale_number', v_sale_number, 'total', v_total));
  return query select v_sale_id, v_sale_number, v_total;
end;
$$;

-- ------------------------------------------------------------
-- مرتجع بيعة (كلي أو جزئي)
-- ------------------------------------------------------------
create or replace function rpc_record_return(p_sale_id uuid, p_items jsonb, p_is_full boolean default true)
returns void language plpgsql security definer as $$
declare v_item jsonb; v_variant_id uuid; v_qty numeric; v_total numeric := 0; v_sale_number text;
begin
  if not fn_has_permission('Sales', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select sale_number into v_sale_number from sales where id = p_sale_id;
  if v_sale_number is null then raise exception 'البيعة غير موجودة'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id into v_variant_id from product_variants where code = v_item->>'variant_code';
    v_qty := (v_item->>'qty')::numeric;
    update product_variants set quantity = quantity + v_qty where id = v_variant_id;
    v_total := v_total + (coalesce((v_item->>'price')::numeric,0) * v_qty);
  end loop;

  update sales set status = case when p_is_full then 'مرتجع كلي' else 'مرتجع جزئي' end where id = p_sale_id;

  perform fn_journal_entry('المبيعات', 'الخزينة', v_total, v_sale_number, 'مرتجع بيعة ' || v_sale_number);
  perform fn_append_cash_flow('خارج', 'مرتجع بيعة ' || v_sale_number, v_total);
  perform fn_log_operation('RECORD_RETURN', jsonb_build_object('sale_number', v_sale_number));
end;
$$;
