-- ============================================================
-- الدفعة 41: (أ) ميزان المراجعة الحقيقي — رصيد سابق / حركة الفترة
-- / رصيد نهائي، مع اختيار "من تاريخ - إلى تاريخ"
-- (ب) نقل فئة فرعية لفئة رئيسية تانية (كان موجود بس للفئة
--     الرئيسية اللي بتتحول لفرعية — مش العكس)
-- (ج) نقل كل منتجات فئة فرعية لفئة فرعية تانية دفعة واحدة (قبل
--     الحذف، بدل تعديل كل منتج لوحده)
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

-- ------------------------------------------------------------
-- أ) ميزان المراجعة الحقيقي
-- ------------------------------------------------------------
create or replace function rpc_trial_balance(p_start_date date default null, p_end_date date default current_date)
returns jsonb language plpgsql security definer as $$
declare v_rows jsonb; v_totals jsonb; v_balanced boolean;
begin
  if not fn_has_permission('Reports','عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'accountCode', a.code, 'accountName', a.name, 'accountType', a.type,
    'prevDebit', round(greatest(coalesce(pd.total,0) - coalesce(pc.total,0), 0), 2),
    'prevCredit', round(greatest(coalesce(pc.total,0) - coalesce(pd.total,0), 0), 2),
    'periodDebit', round(coalesce(md.total,0), 2),
    'periodCredit', round(coalesce(mc.total,0), 2),
    'finalDebit', round(greatest((coalesce(pd.total,0)+coalesce(md.total,0)) - (coalesce(pc.total,0)+coalesce(mc.total,0)), 0), 2),
    'finalCredit', round(greatest((coalesce(pc.total,0)+coalesce(mc.total,0)) - (coalesce(pd.total,0)+coalesce(md.total,0)), 0), 2)
  ) order by a.code), '[]'::jsonb)
  into v_rows
  from accounts a
  left join (
    select debit_account_id acc, sum(amount) total from journal_entries
    where p_start_date is not null and entry_date::date < p_start_date group by 1
  ) pd on pd.acc = a.id
  left join (
    select credit_account_id acc, sum(amount) total from journal_entries
    where p_start_date is not null and entry_date::date < p_start_date group by 1
  ) pc on pc.acc = a.id
  left join (
    select debit_account_id acc, sum(amount) total from journal_entries
    where entry_date::date >= coalesce(p_start_date, '0001-01-01'::date) and entry_date::date <= p_end_date group by 1
  ) md on md.acc = a.id
  left join (
    select credit_account_id acc, sum(amount) total from journal_entries
    where entry_date::date >= coalesce(p_start_date, '0001-01-01'::date) and entry_date::date <= p_end_date group by 1
  ) mc on mc.acc = a.id
  where coalesce(pd.total,0) <> 0 or coalesce(pc.total,0) <> 0 or coalesce(md.total,0) <> 0 or coalesce(mc.total,0) <> 0;

  select jsonb_build_object(
    'prevDebit', round(coalesce(sum((e->>'prevDebit')::numeric),0), 2),
    'prevCredit', round(coalesce(sum((e->>'prevCredit')::numeric),0), 2),
    'periodDebit', round(coalesce(sum((e->>'periodDebit')::numeric),0), 2),
    'periodCredit', round(coalesce(sum((e->>'periodCredit')::numeric),0), 2),
    'finalDebit', round(coalesce(sum((e->>'finalDebit')::numeric),0), 2),
    'finalCredit', round(coalesce(sum((e->>'finalCredit')::numeric),0), 2)
  ) into v_totals from jsonb_array_elements(v_rows) e;

  v_balanced := abs((v_totals->>'finalDebit')::numeric - (v_totals->>'finalCredit')::numeric) < 0.01;

  return jsonb_build_object('rows', v_rows, 'totals', v_totals, 'balanced', v_balanced);
end;
$$;

-- ------------------------------------------------------------
-- ب) نقل فئة فرعية موجودة لفئة رئيسية تانية (Reparent)
-- (منفصلة عن rpc_convert_category_to_sub اللي بتحول رئيسية لفرعية)
-- ------------------------------------------------------------
create or replace function rpc_reparent_subcategory(p_code text, p_new_parent_code text)
returns void language plpgsql security definer as $$
declare v_type text; v_new_parent_type text; v_new_parent_id uuid;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select type into v_type from product_tree where code = p_code and deleted_at is null;
  if v_type is null then raise exception 'الفئة غير موجودة'; end if;
  if v_type <> 'فرعية' then raise exception 'الفئة دي رئيسية مش فرعية — استخدمي تحويل الفئة بدل كده'; end if;

  select id, type into v_new_parent_id, v_new_parent_type from product_tree where code = p_new_parent_code and deleted_at is null;
  if v_new_parent_id is null then raise exception 'الفئة الرئيسية الجديدة غير موجودة'; end if;
  if v_new_parent_type <> 'رئيسية' then raise exception 'الفئة اللي هتنقلها تحتها لازم تكون رئيسية'; end if;

  update product_tree set parent_id = v_new_parent_id where code = p_code;

  perform fn_log_operation('REPARENT_SUBCATEGORY', jsonb_build_object('code', p_code, 'new_parent', p_new_parent_code));
end;
$$;

-- ------------------------------------------------------------
-- ج) نقل كل منتجات فئة فرعية لفئة فرعية تانية دفعة واحدة
-- (عشان تقدري تفضّي فئة قبل ما تمسحيها من غير تعديل كل منتج لوحده)
-- ------------------------------------------------------------
create or replace function rpc_bulk_move_category_products(p_old_sub_category_code text, p_new_sub_category_code text)
returns int language plpgsql security definer as $$
declare v_old_sub_id uuid; v_new_sub_id uuid; v_new_main_id uuid; v_moved int;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_old_sub_category_code = p_new_sub_category_code then raise exception 'اختاري فئة تانية غير الحالية'; end if;

  select id into v_old_sub_id from product_tree where code = p_old_sub_category_code and deleted_at is null;
  if v_old_sub_id is null then raise exception 'الفئة القديمة غير موجودة'; end if;

  select id, parent_id into v_new_sub_id, v_new_main_id from product_tree where code = p_new_sub_category_code and deleted_at is null;
  if v_new_sub_id is null then raise exception 'الفئة الجديدة غير موجودة'; end if;

  update products set sub_category_id = v_new_sub_id, main_category_id = v_new_main_id
  where sub_category_id = v_old_sub_id and deleted_at is null;
  get diagnostics v_moved = row_count;

  perform fn_log_operation('BULK_MOVE_CATEGORY_PRODUCTS', jsonb_build_object('from', p_old_sub_category_code, 'to', p_new_sub_category_code, 'count', v_moved));
  return v_moved;
end;
$$;

grant execute on all functions in schema public to authenticated;
