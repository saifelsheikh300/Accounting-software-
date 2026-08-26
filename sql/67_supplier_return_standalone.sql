-- ============================================================
-- الدفعة 67: مرتجع مورد مباشر (من شاشة "أوردر شراء جديد")
--
-- بديل أبسط لمرتجع المورد المرتبط بأوردر معين (66): هنا المستخدم
-- بيختار المورد والأصناف والكمية بس، من نفس شاشة أوردر الشراء
-- الجديد، وبيحدد هل الفلوس هترجع نقدي ولا هتتخصم من رصيد المورد.
--
-- المبدأ المحاسبي:
--   - المخزون بينقص بمتوسط تكلفة الشراء الفعلي (FIFO) من أقدم
--     دفعة لسه فيها كمية — مش بسعر بيع ولا رقم يكتبه المستخدم،
--     عشان القيمة المحاسبية تفضل مطابقة لتكلفة البضاعة الفعلية.
--   - قبل الاستهلاك، بيتأكد إن الكمية المطلوب إرجاعها متوفرة فعليًا
--     في المخزون (مينفعش ترجعي حاجة مباعة/مش موجودة).
--   - نقدي: مدين الخزينة (كاش داخل)، دائن المخزون.
--   - خصم: مدين الموردون (تقليل التزام)، دائن المخزون.
--     (ده تعديل عام على رصيد الموردين في الأستاذ، مش مربوط
--     بأوردر شراء معين — لأن المرتجع هنا مش لازم يكون مرتبط
--     بأوردر واحد بعينه)
-- ============================================================

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
  v_return_total numeric := 0; v_ref text;
begin
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  perform fn_check_period_open(now());
  if jsonb_array_length(p_items) = 0 then raise exception 'لازم صنف واحد على الأقل'; end if;
  if p_settlement not in ('نقدي', 'خصم') then raise exception 'طريقة استرداد غير معروفة'; end if;
  if not exists (select 1 from suppliers where name = p_supplier_name) then raise exception 'المورد غير موجود'; end if;

  v_ref := 'مرتجع مورد — ' || p_supplier_name || ' — ' || to_char(now(), 'YYYY-MM-DD HH24:MI');

  for v_item in select * from jsonb_array_elements(p_items) loop
    select id into v_variant_id from product_variants where code = v_item->>'variant_code';
    if v_variant_id is null then raise exception 'المنتج غير موجود: %', v_item->>'variant_code'; end if;
    v_qty := (v_item->>'qty')::numeric;
    if v_qty <= 0 then raise exception 'الكمية لازم تكون أكبر من صفر'; end if;

    select coalesce(sum(quantity_remaining), 0) into v_available from inventory_batches where variant_id = v_variant_id;
    if v_available < v_qty then
      raise exception 'مفيش كفاية مخزون من الصنف % عشان ترجعيه — المتاح فعليًا: %', v_item->>'variant_code', v_available;
    end if;

    v_item_cost := fn_consume_fifo(v_variant_id, v_qty);
    v_return_total := v_return_total + v_item_cost;
  end loop;

  if v_return_total <= 0 then raise exception 'قيمة المرتجع لازم تكون أكبر من صفر'; end if;

  if p_settlement = 'نقدي' then
    perform fn_journal_entry('الخزينة', 'المخزون', v_return_total, v_ref, v_ref);
    perform fn_move_treasury('داخل', v_return_total, p_treasury_account_id, v_ref);
  else
    perform fn_journal_entry('الموردون', 'المخزون', v_return_total, v_ref, v_ref);
  end if;

  perform fn_log_operation('SUPPLIER_RETURN_STANDALONE', jsonb_build_object(
    'supplier_name', p_supplier_name, 'return_total', v_return_total, 'settlement', p_settlement
  ));

  return jsonb_build_object('return_total', v_return_total, 'settlement', p_settlement);
end;
$$;

grant execute on all functions in schema public to authenticated;
