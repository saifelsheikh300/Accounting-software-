-- ============================================================
-- الدفعة 2 (نسخة مُصلَّحة، آمنة لإعادة التشغيل من الصفر)
-- شغّلي الملف ده بدل 08 القديم بالكامل
-- ============================================================

alter table warehouses add column if not exists branch_type text not null default 'مخزن' check (branch_type in ('فرع','مخزن'));
alter table warehouses add column if not exists manager_name text default '';

create table if not exists stock_transfers (
  id uuid primary key default gen_random_uuid(),
  transfer_number text unique not null,
  transfer_date timestamptz not null default now(),
  from_warehouse_id uuid not null references warehouses(id),
  to_warehouse_id uuid not null references warehouses(id),
  notes text default '',
  created_by uuid references profiles(id)
);

create table if not exists stock_transfer_items (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null references stock_transfers(id) on delete cascade,
  variant_id uuid not null references product_variants(id),
  qty numeric(12,2) not null
);

alter table stock_transfers enable row level security;
alter table stock_transfer_items enable row level security;

drop policy if exists "قراءة بصلاحية stock_transfers" on stock_transfers;
create policy "قراءة بصلاحية stock_transfers" on stock_transfers for select using (fn_has_permission('Inventory','عرض'));
drop policy if exists "قراءة بصلاحية stock_transfer_items" on stock_transfer_items;
create policy "قراءة بصلاحية stock_transfer_items" on stock_transfer_items for select using (fn_has_permission('Inventory','عرض'));

create or replace function rpc_transfer_stock(p_from_warehouse_id uuid, p_to_warehouse_id uuid, p_items jsonb, p_notes text default '')
returns table(transfer_id uuid, transfer_number text) language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_qty numeric; v_transfer_id uuid; v_transfer_number text;
  v_variant record; v_dest_variant_id uuid;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;
  if p_from_warehouse_id = p_to_warehouse_id then raise exception 'اختاري مخزنين مختلفين'; end if;

  v_transfer_number := 'TR-' || to_char(now(), 'YYYYMMDDHH24MISS');
  insert into stock_transfers (transfer_number, from_warehouse_id, to_warehouse_id, notes, created_by)
  values (v_transfer_number, p_from_warehouse_id, p_to_warehouse_id, p_notes, auth.uid())
  returning id into v_transfer_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    select * into v_variant from product_variants where code = v_item->>'variant_code' and warehouse_id = p_from_warehouse_id;
    if v_variant.id is null then raise exception 'المتغير غير موجود في المخزن المصدر: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    if v_variant.quantity < v_qty then raise exception 'الكمية غير كافية للصنف: %', v_item->>'variant_code'; end if;

    insert into stock_transfer_items (transfer_id, variant_id, qty) values (v_transfer_id, v_variant.id, v_qty);
    update product_variants set quantity = quantity - v_qty where id = v_variant.id;

    select id into v_dest_variant_id from product_variants where code = v_variant.code || '-' || (select left(w.name,3) from warehouses w where w.id = p_to_warehouse_id);
    if v_dest_variant_id is not null then
      update product_variants set quantity = quantity + v_qty where id = v_dest_variant_id;
    else
      insert into product_variants (code, product_id, color, size, quantity, cost, special_price, warehouse_id, low_stock_threshold)
      values (v_variant.code || '-' || (select left(w.name,3) from warehouses w where w.id = p_to_warehouse_id),
              v_variant.product_id, v_variant.color, v_variant.size, v_qty, v_variant.cost, v_variant.special_price, p_to_warehouse_id, v_variant.low_stock_threshold);
    end if;
  end loop;

  perform fn_log_operation('TRANSFER_STOCK', jsonb_build_object('transfer_number', v_transfer_number));
  return query select v_transfer_id, v_transfer_number;
end;
$$;

create table if not exists purchase_requests (
  id uuid primary key default gen_random_uuid(),
  request_number text unique not null,
  request_date timestamptz not null default now(),
  supplier_name text default '',
  notes text default '',
  status text not null default 'بانتظار الاعتماد' check (status in ('بانتظار الاعتماد','معتمد','مرفوض','تم التحويل لأمر شراء')),
  requested_by uuid references profiles(id),
  approved_by uuid references profiles(id),
  approved_at timestamptz
);

create table if not exists purchase_request_items (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references purchase_requests(id) on delete cascade,
  variant_id uuid references product_variants(id),
  free_text_item text default '',
  qty numeric(12,2) not null,
  estimated_price numeric(12,2) default 0
);

alter table purchase_requests enable row level security;
alter table purchase_request_items enable row level security;

drop policy if exists "قراءة بصلاحية purchase_requests" on purchase_requests;
create policy "قراءة بصلاحية purchase_requests" on purchase_requests for select using (fn_has_permission('Suppliers','عرض'));
drop policy if exists "تعديل بصلاحية purchase_requests" on purchase_requests;
create policy "تعديل بصلاحية purchase_requests" on purchase_requests for all using (fn_has_permission('Suppliers','تعديل'));
drop policy if exists "قراءة بصلاحية purchase_request_items" on purchase_request_items;
create policy "قراءة بصلاحية purchase_request_items" on purchase_request_items for select using (fn_has_permission('Suppliers','عرض'));

create or replace function rpc_create_purchase_request(p_supplier_name text, p_items jsonb, p_notes text default '')
returns table(request_id uuid, request_number text) language plpgsql security definer as $$
declare v_item jsonb; v_request_id uuid; v_request_number text; v_variant_id uuid;
begin
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  v_request_number := 'PR-' || to_char(now(), 'YYYYMMDDHH24MISS');

  insert into purchase_requests (request_number, supplier_name, notes, requested_by)
  values (v_request_number, p_supplier_name, p_notes, auth.uid()) returning id into v_request_id;

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_variant_id := null;
    if v_item ? 'variant_code' and v_item->>'variant_code' <> '' then
      select id into v_variant_id from product_variants where code = v_item->>'variant_code';
    end if;
    insert into purchase_request_items (request_id, variant_id, free_text_item, qty, estimated_price)
    values (v_request_id, v_variant_id, coalesce(v_item->>'freeText',''), (v_item->>'qty')::numeric, coalesce((v_item->>'estimatedPrice')::numeric,0));
  end loop;

  perform fn_log_operation('CREATE_PURCHASE_REQUEST', jsonb_build_object('request_number', v_request_number));
  return query select v_request_id, v_request_number;
end;
$$;

create or replace function rpc_approve_purchase_request(p_request_id uuid, p_approve boolean)
returns void language plpgsql security definer as $$
begin
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  update purchase_requests set status = case when p_approve then 'معتمد' else 'مرفوض' end,
    approved_by = auth.uid(), approved_at = now()
    where id = p_request_id;
  perform fn_log_operation('APPROVE_PURCHASE_REQUEST', jsonb_build_object('request_id', p_request_id, 'approved', p_approve));
end;
$$;

grant execute on all functions in schema public to authenticated;
