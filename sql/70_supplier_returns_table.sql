-- ============================================================
-- الدفعة 70: تسجيل مرتجعات الموردين في جدول ظاهر (مش مجرد سجل عمليات داخلي)
--
-- المرتجع كان بيتسجل صح تمامًا في الدفاتر (المخزون بينقص، الموردون/
-- الخزينة بتتأثر صح) لكن مفيش أي مكان في الواجهة يعرضه للمستخدم —
-- كان مسجل بس في operations_log (سجل داخلي مش معروض). دلوقتي
-- بيتسجل كمان في جدول supplier_returns مخصص، وله تاب في صفحة
-- المورد زي "المشتريات" بالظبط.
-- ============================================================

create table if not exists supplier_returns (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid references suppliers(id),
  supplier_name text not null,
  items jsonb not null,
  return_total numeric(12,2) not null,
  settlement text not null,
  created_at timestamptz not null default now()
);

alter table supplier_returns enable row level security;
drop policy if exists "قراءة مرتجعات الموردين" on supplier_returns;
create policy "قراءة مرتجعات الموردين" on supplier_returns for select to authenticated using (true);

do $$
declare v_sig record;
begin
  for v_sig in select oid::regprocedure as sig from pg_proc where proname = 'rpc_record_standalone_supplier_return'
  loop
    execute 'drop function if exists ' || v_sig.sig || ' cascade';
  end loop;
end $$;

create or replace function rpc_record_standalone_supplier_return(
  p_supplier_name text, p_items jsonb, p_settlement text default 'نقدي', p_treasury_account_id uuid default null
)
returns jsonb language plpgsql security definer as $$
declare
  v_item jsonb; v_variant_id uuid; v_qty numeric; v_available numeric; v_item_cost numeric;
  v_return_total numeric := 0; v_ref text; v_supplier_id uuid; v_items_log jsonb := '[]'::jsonb;
  v_variant_code text; v_variant_label text;
begin
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  perform fn_check_period_open(now());
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;
  if p_settlement not in ('نقدي', 'خصم') then raise exception 'طريقة استرداد غير معروفة'; end if;

  select id into v_supplier_id from suppliers where name = p_supplier_name;
  if v_supplier_id is null then raise exception 'المورد غير موجود'; end if;

  v_ref := 'مرتجع مورد — ' || p_supplier_name || ' — ' || to_char(now(), 'YYYY-MM-DD HH24:MI');

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_variant_code := v_item->>'variant_code';
    select id into v_variant_id from product_variants where code = v_variant_code;
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_variant_code; end if;
    v_qty := (v_item->>'qty')::numeric;
    if v_qty <= 0 then raise exception 'الكمية لازم تكون أكبر من صفر'; end if;

    select coalesce(sum(quantity_remaining), 0) into v_available from inventory_batches where variant_id = v_variant_id;
    if v_available < v_qty then
      raise exception 'مفيش كفاية مخزون من الصنف % عشان ترجعيه — المتاح فعليًا: %', v_variant_code, v_available;
    end if;

    v_item_cost := fn_consume_fifo(v_variant_id, v_qty);
    v_return_total := v_return_total + v_item_cost;

    select coalesce(p.name,'') || ' — ' || coalesce(pv.color,'') || ' ' || coalesce(pv.size,'') into v_variant_label
    from product_variants pv left join products p on p.id = pv.product_id where pv.id = v_variant_id;

    v_items_log := v_items_log || jsonb_build_object('variantCode', v_variant_code, 'label', v_variant_label, 'qty', v_qty, 'cost', v_item_cost);
  end loop;

  if v_return_total <= 0 then raise exception 'قيمة المرتجع لازم تكون أكبر من صفر'; end if;

  if p_settlement = 'نقدي' then
    perform fn_journal_entry('الخزينة', 'المخزون', v_return_total, v_ref, v_ref);
    perform fn_move_treasury('داخل', v_return_total, p_treasury_account_id, v_ref);
  else
    perform fn_journal_entry('الموردون', 'المخزون', v_return_total, v_ref, v_ref);
  end if;

  insert into supplier_returns (supplier_id, supplier_name, items, return_total, settlement)
  values (v_supplier_id, p_supplier_name, v_items_log, v_return_total, p_settlement);

  perform fn_log_operation('SUPPLIER_RETURN_STANDALONE', jsonb_build_object(
    'supplier_name', p_supplier_name, 'return_total', v_return_total, 'settlement', p_settlement
  ));

  return jsonb_build_object('return_total', v_return_total, 'settlement', p_settlement);
end;
$$;

grant execute on all functions in schema public to authenticated;
