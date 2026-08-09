-- ============================================================
-- الدفعة 14: فواتير العميل "حساب مفتوح" — إضافة أصناف حقيقية من
-- المخزون للفاتورة على أكتر من دفعة (بدل رقم إجمالي يدوي بس)
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

alter table invoices add column if not exists customer_phone text default '';
alter table invoices add column if not exists notes text default '';
alter table invoices alter column total set default 0;

alter table invoices drop constraint if exists invoices_status_check;
alter table invoices add constraint invoices_status_check
  check (status in ('مفتوحة','مدفوعة بالكامل','مدفوعة جزئيًا','متأخرة','تم التحصيل COD'));

-- ------------------------------------------------------------
-- 1) فتح فاتورة جديدة لعميل (حساب مفتوح فاضي، تقدري تضيفي عليه بعدين)
-- ------------------------------------------------------------
create or replace function rpc_open_invoice(p_customer_name text, p_customer_phone text default '', p_notes text default '')
returns table(invoice_id uuid, invoice_number text) language plpgsql security definer as $$
declare v_id uuid; v_number text;
begin
  if not fn_has_permission('Invoices', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_customer_name is null or trim(p_customer_name) = '' then raise exception 'اسم العميل مطلوب'; end if;

  v_number := 'INV-' || to_char(now(), 'YYYYMMDDHH24MISS');
  insert into invoices (invoice_number, customer_name, customer_phone, notes, total, paid, remaining, status)
  values (v_number, p_customer_name, coalesce(p_customer_phone, ''), coalesce(p_notes, ''), 0, 0, 0, 'مفتوحة')
  returning id into v_id;

  perform fn_log_operation('OPEN_INVOICE', jsonb_build_object('invoice_number', v_number, 'customer', p_customer_name));
  return query select v_id, v_number;
end;
$$;

-- ------------------------------------------------------------
-- 2) إضافة أصناف حقيقية من المخزون لفاتورة موجودة — بتخصم من
-- المخزون فورًا، وبتحدّث إجمالي/متبقي الفاتورة تلقائيًا. قابلة
-- للاستدعاء أكتر من مرة على نفس الفاتورة (كل ما العميل ياخد حاجة جديدة)
-- p_items shape: [{"variant_code":"...","qty":2,"price":150}, ...]
-- ------------------------------------------------------------
create or replace function rpc_add_items_to_invoice(p_invoice_id uuid, p_items jsonb, p_warehouse_id uuid default null)
returns jsonb language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_cost numeric; v_price numeric; v_qty numeric;
  v_subtotal numeric := 0; v_sale_id uuid; v_sale_number text;
  v_customer_name text; v_customer_phone text; v_paid numeric;
  v_new_total numeric; v_new_remaining numeric; v_new_status text;
begin
  if not fn_has_permission('Invoices', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

  select customer_name, customer_phone, paid into v_customer_name, v_customer_phone, v_paid from invoices where id = p_invoice_id;
  if v_customer_name is null then raise exception 'الفاتورة غير موجودة'; end if;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id into v_variant_id from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    v_price := coalesce((v_item->>'price')::numeric, 0);
    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  v_sale_number := 'S-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || floor(random() * 900 + 100)::text;

  insert into sales (sale_number, source, subtotal, discount, total, payment_method, invoice_id, customer_name, customer_phone, warehouse_id, created_by)
  values (v_sale_number, 'محل', v_subtotal, 0, v_subtotal, 'آجل', p_invoice_id, v_customer_name, v_customer_phone, p_warehouse_id, auth.uid())
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost into v_variant_id, v_cost from product_variants where code = v_item->>'variant_code';
    v_qty := (v_item->>'qty')::numeric;
    v_price := coalesce((v_item->>'price')::numeric, 0);

    insert into sale_items (sale_id, variant_id, qty, unit_price, unit_cost) values (v_sale_id, v_variant_id, v_qty, v_price, v_cost);
    update product_variants set quantity = quantity - v_qty where id = v_variant_id;
  end loop;

  perform fn_journal_entry('العملاء (مدينون)', 'المبيعات', v_subtotal, v_sale_number, 'إضافة أصناف لفاتورة');

  select coalesce(sum(total), 0) into v_new_total from sales where invoice_id = p_invoice_id;
  v_new_remaining := v_new_total - v_paid;
  v_new_status := case when v_new_remaining <= 0 then 'مدفوعة بالكامل' when v_paid > 0 then 'مدفوعة جزئيًا' else 'مفتوحة' end;

  update invoices set total = v_new_total, remaining = v_new_remaining, status = v_new_status where id = p_invoice_id;

  perform fn_log_operation('ADD_ITEMS_TO_INVOICE', jsonb_build_object('invoice_id', p_invoice_id, 'sale_number', v_sale_number, 'added', v_subtotal));
  return jsonb_build_object('saleNumber', v_sale_number, 'addedTotal', v_subtotal, 'invoiceTotal', v_new_total, 'invoiceRemaining', v_new_remaining);
end;
$$;

-- ------------------------------------------------------------
-- 3) تفاصيل فاتورة كاملة: البيانات + كل الأصناف اللي اتضافت
-- عليها من كل الدفعات (تجميع كل sale_items المرتبطة بيها)
-- ------------------------------------------------------------
create or replace function rpc_get_invoice_details(p_invoice_id uuid)
returns jsonb language plpgsql security definer as $$
declare v_invoice jsonb; v_items jsonb;
begin
  if not fn_has_permission('Invoices', 'عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select to_jsonb(i) into v_invoice from invoices i where id = p_invoice_id;
  if v_invoice is null then raise exception 'الفاتورة غير موجودة'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'productName', p.name, 'variantCode', pv.code, 'color', pv.color, 'size', pv.size,
    'qty', si.qty, 'unitPrice', si.unit_price, 'lineTotal', si.qty * si.unit_price,
    'addedAt', s.sale_date
  ) order by s.sale_date), '[]'::jsonb) into v_items
  from sales s
  join sale_items si on si.sale_id = s.id
  join product_variants pv on pv.id = si.variant_id
  join products p on p.id = pv.product_id
  where s.invoice_id = p_invoice_id;

  return jsonb_build_object('invoice', v_invoice, 'items', v_items);
end;
$$;

grant execute on all functions in schema public to authenticated;
