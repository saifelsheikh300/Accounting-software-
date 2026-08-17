-- ============================================================
-- الدفعة 38: حذف الفئات (رئيسية/فرعية) بأمان
-- زي المنتجات بالظبط، الحذف "ناعم" (Soft Delete) — يروح لسلة
-- المحذوفات وترجعيه لو غلطتي. مش هيسمحلك تمسحي فئة لسه فيها
-- منتجات أو فئات فرعية تحتها، عشان محدش يفضل معلّق من غير فئة.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

alter table product_tree add column if not exists deleted_at timestamptz;

create or replace function rpc_soft_delete(p_table text, p_id text)
returns void language plpgsql security definer as $$
declare v_has_products int; v_has_subs int;
begin
  if p_table not in ('products','product_variants','customers','suppliers','employees','product_tree') then
    raise exception 'جدول غير مسموح للحذف الناعم';
  end if;
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  if p_table = 'product_tree' then
    select count(*) into v_has_products from products where (main_category_id = p_id::uuid or sub_category_id = p_id::uuid) and deleted_at is null;
    if v_has_products > 0 then raise exception 'فيه % منتج لسه مرتبط بالفئة دي — انقليهم لفئة تانية الأول', v_has_products; end if;

    select count(*) into v_has_subs from product_tree where parent_id = p_id::uuid and deleted_at is null;
    if v_has_subs > 0 then raise exception 'فيه % فئة فرعية لسه تحت الفئة دي — امسحيهم أو انقليهم الأول', v_has_subs; end if;
  end if;

  if p_table = 'customers' then
    execute format('update %I set deleted_at = now() where phone = $1', p_table) using p_id;
  else
    execute format('update %I set deleted_at = now() where id = $1::uuid', p_table) using p_id;
  end if;

  perform fn_log_operation('SOFT_DELETE', jsonb_build_object('table', p_table, 'id', p_id));
end;
$$;

create or replace function rpc_restore_deleted(p_table text, p_id text)
returns void language plpgsql security definer as $$
begin
  if p_table not in ('products','product_variants','customers','suppliers','employees','product_tree') then
    raise exception 'جدول غير مسموح للاسترجاع';
  end if;
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  if p_table = 'customers' then
    execute format('update %I set deleted_at = null where phone = $1', p_table) using p_id;
  else
    execute format('update %I set deleted_at = null where id = $1::uuid', p_table) using p_id;
  end if;

  perform fn_log_operation('RESTORE_DELETED', jsonb_build_object('table', p_table, 'id', p_id));
end;
$$;

grant execute on all functions in schema public to authenticated;
