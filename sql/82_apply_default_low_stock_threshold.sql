-- ============================================================
-- الدفعة 82: تطبيق حد التنبيه الافتراضي بأثر رجعي على كل المنتجات
--
-- الإعداد "حد التنبيه الافتراضي للمخزون" كان بيتسجل بس مش بيتطبق
-- فعليًا على أي منتج — كل منتج جديد كان بياخد 5 ثابت بغض النظر عن
-- الإعداد ده. اتصلح للمنتجات الجديدة، والفنكشن دي بتصلح المنتجات
-- الموجودة بالفعل (بأثر رجعي) لو عايزة تطبّقي الرقم الجديد عليهم كلهم.
-- ============================================================

create or replace function rpc_apply_default_low_stock_threshold()
returns int language plpgsql security definer as $$
declare v_default numeric; v_count int;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select coalesce((value)::numeric, 5) into v_default from settings where key = 'lowStockThresholdDefault';
  v_default := coalesce(v_default, 5);

  update product_variants set low_stock_threshold = v_default where status = 'نشط';
  get diagnostics v_count = row_count;

  perform fn_log_operation('APPLY_DEFAULT_LOW_STOCK_THRESHOLD', jsonb_build_object('new_default', v_default, 'affected', v_count));
  return v_count;
end;
$$;

grant execute on all functions in schema public to authenticated;
