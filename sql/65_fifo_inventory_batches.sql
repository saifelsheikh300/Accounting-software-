-- ============================================================
-- الدفعة 65: نظام FIFO حقيقي للمخزون (بدل المتوسط المرجح).
--
-- الفكرة: كل دفعة شراء بتتسجل لوحدها بتكلفتها وسعر بيعها
-- الخاص بيها، وبيتباع من الأقدم للأحدث. البيع بياخد التكلفة
-- الحقيقية للدفعة اللي بيستهلكها (ممكن يستهلك من أكتر من دفعة
-- في نفس عملية البيع لو الكمية أكبر من دفعة واحدة).
--
-- عشان مانلمسش كل شاشة في البرنامج، الحقول القديمة
-- (product_variants.cost و special_price) فضلت موجودة، بس بقت
-- بتتحدث تلقائيًا لتعكس "الدفعة الحالية" (الأقدم اللي لسه فيها
-- كمية) — يعني كل الشاشات اللي بتقرا منها (الكاشير، المبيعات،
-- المخزون) هتفضل تشتغل عادي وتعرض السعر/التكلفة الصح تلقائيًا.
--
-- (قابلة لإعادة التشغيل بأمان بالكامل)
-- ============================================================

create table if not exists inventory_batches (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references product_variants(id),
  quantity_remaining numeric not null,
  quantity_original numeric not null,
  unit_cost numeric not null default 0,
  unit_price numeric,
  source text default '',
  reference text default '',
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
alter table inventory_batches enable row level security;
drop policy if exists "قراءة inventory_batches" on inventory_batches;
create policy "قراءة inventory_batches" on inventory_batches for select using (auth.role() = 'authenticated');

create index if not exists idx_inventory_batches_variant on inventory_batches(variant_id, received_at);

-- ترحيل المخزون الحالي لدفعة واحدة لكل صنف (نقطة البداية لنظام الدفعات)
insert into inventory_batches (variant_id, quantity_remaining, quantity_original, unit_cost, unit_price, source, reference, received_at)
select pv.id, pv.quantity, pv.quantity, coalesce(pv.cost,0),
  coalesce(pv.special_price, (select base_price from products where id = pv.product_id)),
  'رصيد سابق', 'MIGRATION-65', now()
from product_variants pv
where pv.quantity > 0 and not exists (select 1 from inventory_batches where variant_id = pv.id);

create or replace function fn_sync_variant_from_fifo(p_variant_id uuid) returns void language plpgsql as $$
declare v_total_qty numeric; v_oldest record;
begin
  select coalesce(sum(quantity_remaining),0) into v_total_qty from inventory_batches where variant_id = p_variant_id;
  select unit_cost, unit_price into v_oldest from inventory_batches
    where variant_id = p_variant_id and quantity_remaining > 0 order by received_at asc, id asc limit 1;
  update product_variants set quantity = v_total_qty,
    cost = coalesce(v_oldest.unit_cost, cost),
    special_price = coalesce(v_oldest.unit_price, special_price)
  where id = p_variant_id;
end;
$$;

create or replace function fn_add_inventory_batch(p_variant_id uuid, p_qty numeric, p_unit_cost numeric, p_unit_price numeric, p_source text, p_reference text)
returns void language plpgsql as $$
begin
  insert into inventory_batches (variant_id, quantity_remaining, quantity_original, unit_cost, unit_price, source, reference)
  values (p_variant_id, p_qty, p_qty, p_unit_cost, p_unit_price, p_source, p_reference);
  perform fn_sync_variant_from_fifo(p_variant_id);
end;
$$;

-- بيستهلك من أقدم دفعة لسه فيها كمية، وبيرجع التكلفة الفعلية المستهلكة
create or replace function fn_consume_fifo(p_variant_id uuid, p_qty numeric) returns numeric language plpgsql as $$
declare v_batch record; v_take numeric; v_remaining numeric := p_qty; v_total_cost numeric := 0; v_fallback_cost numeric;
begin
  for v_batch in
    select * from inventory_batches where variant_id = p_variant_id and quantity_remaining > 0
    order by received_at asc, id asc for update
  loop
    exit when v_remaining <= 0;
    v_take := least(v_remaining, v_batch.quantity_remaining);
    update inventory_batches set quantity_remaining = quantity_remaining - v_take where id = v_batch.id;
    v_total_cost := v_total_cost + (v_take * v_batch.unit_cost);
    v_remaining := v_remaining - v_take;
  end loop;

  if v_remaining > 0.0001 then
    -- بيانات قديمة قبل نظام الدفعات مفيهاش دفعة كفاية — استخدمي آخر تكلفة معروفة كحل احتياطي
    select cost into v_fallback_cost from product_variants where id = p_variant_id;
    v_total_cost := v_total_cost + (v_remaining * coalesce(v_fallback_cost, 0));
  end if;

  perform fn_sync_variant_from_fifo(p_variant_id);
  return v_total_cost;
end;
$$;

-- ------------------------------------------------------------
-- أوردر شراء: كل صنف بيعمل دفعة جديدة بتكلفتها وسعرها، بدل تحديث متوسط
-- ------------------------------------------------------------
create or replace function rpc_create_purchase_order(
  p_supplier_name text, p_items jsonb, p_payment_status text default 'مدفوع بالكامل',
  p_amount_paid numeric default 0, p_warehouse_id uuid default null, p_treasury_account_id uuid default null
)
returns table(order_id uuid, order_number text, total numeric) language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_old_cost numeric; v_qty numeric; v_price numeric; v_sale_price numeric;
  v_total numeric := 0; v_supplier_id uuid; v_order_id uuid; v_order_number text;
  v_paid numeric; v_remaining numeric;
begin
  perform fn_check_period_open(now());
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

  select id into v_supplier_id from suppliers where name = p_supplier_name;
  if v_supplier_id is null then raise exception 'المورد غير موجود'; end if;

  v_order_number := 'PO-' || to_char(now(), 'YYYYMMDDHH24MISS');

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_total := v_total + ((v_item->>'price')::numeric * (v_item->>'qty')::numeric);
  end loop;

  v_paid := case when p_payment_status = 'مدفوع بالكامل' then v_total else coalesce(p_amount_paid, 0) end;
  v_remaining := v_total - v_paid;

  insert into purchase_orders (order_number, supplier_id, total, payment_status, amount_paid, remaining, warehouse_id)
  values (v_order_number, v_supplier_id, v_total, p_payment_status, v_paid, v_remaining, p_warehouse_id)
  returning id into v_order_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, cost into v_variant_id, v_old_cost from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المتغير غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    v_price := (v_item->>'price')::numeric;
    v_sale_price := nullif(v_item->>'sale_price', '')::numeric;

    insert into purchase_order_items (purchase_order_id, variant_id, qty, unit_price) values (v_order_id, v_variant_id, v_qty, v_price);

    -- ✅ 65: دفعة جديدة مستقلة بدل تحديث المتوسط
    perform fn_add_inventory_batch(v_variant_id, v_qty, v_price, v_sale_price, 'شراء', v_order_number);
    insert into cost_history (variant_id, old_cost, new_cost, quantity, source_ref) values (v_variant_id, v_old_cost, v_price, v_qty, v_order_number);
  end loop;

  if v_paid > 0 then
    perform fn_journal_entry('المخزون', 'الخزينة', v_paid, v_order_number, 'دفعة فورية أوردر شراء ' || v_order_number);
  end if;
  if v_remaining > 0 then
    perform fn_journal_entry('المخزون', 'الموردون', v_remaining, v_order_number, 'رصيد آجل أوردر شراء ' || v_order_number);
  end if;
  if v_paid > 0 then perform fn_move_treasury('خارج', v_paid, p_treasury_account_id, 'أوردر شراء ' || v_order_number); end if;

  perform fn_log_operation('CREATE_PURCHASE_ORDER', jsonb_build_object('order_number', v_order_number, 'total', v_total));
  return query select v_order_id, v_order_number, v_total;
end;
$$;

-- ------------------------------------------------------------
-- مخزون افتتاحي: نفس الفكرة، دفعة مستقلة
-- ------------------------------------------------------------
create or replace function rpc_add_opening_inventory(
  p_supplier_name text, p_items jsonb, p_owed_amount numeric default 0,
  p_as_of_date date default current_date, p_warehouse_id uuid default null
)
returns table(order_number text, total numeric, owed numeric, settled_from_capital numeric)
language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_qty numeric; v_price numeric; v_sale_price numeric;
  v_total numeric := 0; v_supplier_id uuid; v_order_id uuid; v_order_number text;
  v_owed numeric; v_settled numeric;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;

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
    select id into v_variant_id from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المتغير غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    v_price := (v_item->>'price')::numeric;
    v_sale_price := nullif(v_item->>'sale_price', '')::numeric;

    insert into purchase_order_items (purchase_order_id, variant_id, qty, unit_price) values (v_order_id, v_variant_id, v_qty, v_price);
    perform fn_add_inventory_batch(v_variant_id, v_qty, v_price, v_sale_price, 'رصيد افتتاحي', v_order_number);
  end loop;

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

-- ------------------------------------------------------------
-- البيع: تكلفة البضاعة بتتحسب من الدفعات الفعلية المستهلكة (FIFO)
-- ------------------------------------------------------------
create or replace function rpc_record_sale(
  p_source text, p_items jsonb, p_discount numeric default 0, p_payment_method text default null,
  p_invoice_id uuid default null, p_customer_name text default '', p_customer_phone text default '',
  p_warehouse_id uuid default null, p_sale_date timestamptz default now(), p_treasury_account_id uuid default null,
  p_currency_code text default 'EGP'
)
returns table(sale_id uuid, sale_number text, total numeric) language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_price numeric; v_qty numeric; v_avail_qty numeric; v_item_cogs numeric;
  v_subtotal numeric := 0; v_total numeric; v_sale_id uuid; v_sale_number text;
  v_is_cash boolean; v_total_cogs numeric := 0; v_rate numeric; v_base_total numeric;
begin
  perform fn_check_period_open(p_sale_date);
  if not fn_has_permission('Sales', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم منتج واحد على الأقل'; end if;

  v_sale_number := 'S-' || to_char(now(), 'YYYYMMDDHH24MISS') || '-' || floor(random()*900+100)::text;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id, quantity into v_variant_id, v_avail_qty from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    if v_avail_qty < v_qty then raise exception 'الكمية غير كافية للصنف % — المتاح فعليًا: %', v_item->>'variant_code', v_avail_qty; end if;
    v_price := coalesce((v_item->>'price')::numeric, 0);
    v_subtotal := v_subtotal + (v_price * v_qty);
  end loop;

  v_total := v_subtotal - coalesce(p_discount, 0);

  if p_currency_code = 'EGP' then
    v_base_total := v_total;
  else
    select rate_to_base into v_rate from exchange_rates where currency_code = p_currency_code and rate_date <= p_sale_date::date order by rate_date desc limit 1;
    if v_rate is null then raise exception 'سعر الصرف غير محدد للعملة %', p_currency_code; end if;
    v_base_total := round(v_total * v_rate, 2);
  end if;

  v_is_cash := p_payment_method is not null and p_payment_method <> 'آجل';

  insert into sales (sale_number, sale_date, source, subtotal, discount, total, payment_method, invoice_id, customer_name, customer_phone, warehouse_id, created_by, currency_code)
  values (v_sale_number, p_sale_date, p_source, v_subtotal, coalesce(p_discount,0), v_total, p_payment_method, p_invoice_id, p_customer_name, p_customer_phone, p_warehouse_id, auth.uid(), p_currency_code)
  returning id into v_sale_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id into v_variant_id from product_variants where code = v_item->>'variant_code';
    v_qty := (v_item->>'qty')::numeric;
    v_price := coalesce((v_item->>'price')::numeric, 0);

    -- ✅ 65: استهلاك FIFO من الدفعات الفعلية بدل تكلفة متوسطة ثابتة
    v_item_cogs := fn_consume_fifo(v_variant_id, v_qty);
    v_total_cogs := v_total_cogs + v_item_cogs;

    insert into sale_items (sale_id, variant_id, qty, unit_price, unit_cost) values (v_sale_id, v_variant_id, v_qty, v_price, case when v_qty > 0 then v_item_cogs / v_qty else 0 end);
  end loop;

  perform fn_journal_entry(case when v_is_cash then 'الخزينة' else 'العملاء (مدينون)' end, 'المبيعات', v_base_total, v_sale_number, 'بيعة رقم ' || v_sale_number);
  if v_total_cogs > 0 then
    perform fn_journal_entry('تكلفة البضاعة المباعة', 'المخزون', v_total_cogs, v_sale_number, 'تكلفة بضاعة بيعة ' || v_sale_number);
  end if;
  if v_is_cash then perform fn_move_treasury('داخل', v_base_total, p_treasury_account_id, 'بيعة ' || v_sale_number); end if;

  if p_customer_phone is not null and p_customer_phone <> '' then
    insert into customers (phone, name, order_count, total_purchases, first_order_at)
    values (p_customer_phone, p_customer_name, 1, v_total, now())
    on conflict (phone) do update set
      order_count = customers.order_count + 1,
      total_purchases = customers.total_purchases + v_total,
      name = coalesce(nullif(excluded.name, ''), customers.name);
  end if;

  perform fn_log_operation('RECORD_SALE', jsonb_build_object('sale_number', v_sale_number, 'total', v_total, 'currency', p_currency_code));
  return query select v_sale_id, v_sale_number, v_total;
end;
$$;

grant execute on all functions in schema public to authenticated;
