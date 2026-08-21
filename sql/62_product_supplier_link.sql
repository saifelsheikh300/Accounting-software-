-- ============================================================
-- الدفعة 62: اسم المورد بيظهر لكل منتج + فلتر بالمورد في المخزون.
--
-- ضفت عمود supplier_id في جدول المنتجات، وبيتحدث تلقائيًا لآخر
-- مورد اشتريتي المنتج منه (سواء أوردر شراء عادي أو رصيد افتتاحي
-- مخزون). لو منتج ماتربطش بمورد لسه، هيفضل فاضي عادي.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

alter table products add column if not exists supplier_id uuid references suppliers(id);

-- تحديث المنتجات الحالية من آخر أوردر شراء ليها (لو موجود)
update products p set supplier_id = latest.supplier_id
from (
  select distinct on (pv.product_id) pv.product_id, po.supplier_id
  from purchase_order_items poi
  join product_variants pv on pv.id = poi.variant_id
  join purchase_orders po on po.id = poi.purchase_order_id
  order by pv.product_id, po.order_date desc
) as latest
where p.id = latest.product_id and p.supplier_id is null;

-- تحديث تلقائي: أي أوردر شراء جديد (عادي أو رصيد افتتاحي) يحدّث مورد المنتج
create or replace function fn_update_product_supplier() returns trigger language plpgsql as $$
declare v_supplier_id uuid; v_product_id uuid;
begin
  select supplier_id into v_supplier_id from purchase_orders where id = new.purchase_order_id;
  select product_id into v_product_id from product_variants where id = new.variant_id;
  if v_supplier_id is not null and v_product_id is not null then
    update products set supplier_id = v_supplier_id where id = v_product_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_update_product_supplier on purchase_order_items;
create trigger trg_update_product_supplier after insert on purchase_order_items
for each row execute function fn_update_product_supplier();

grant execute on all functions in schema public to authenticated;
