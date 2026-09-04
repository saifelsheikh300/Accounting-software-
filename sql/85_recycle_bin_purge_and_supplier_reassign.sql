-- ============================================================
-- الدفعة 85: تنظيف سلة المحذوفات تلقائيًا بعد 30 يوم + مسح فوري يدوي
-- + تغيير مورد أوردر شراء كامل (لو اتسجل غلط على مورد تاني)
-- ============================================================

-- مسح نهائي لعنصر واحد من سلة المحذوفات (لازم يكون محذوف ناعم بالفعل)
create or replace function rpc_purge_deleted_item(p_table text, p_id text)
returns void language plpgsql security definer as $$
begin
  if p_table not in ('products','product_variants','customers','suppliers','employees','product_tree') then
    raise exception 'جدول غير مسموح للمسح النهائي';
  end if;
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  begin
    if p_table = 'customers' then
      execute format('delete from %I where phone = $1 and deleted_at is not null', p_table) using p_id;
    else
      execute format('delete from %I where id = $1::uuid and deleted_at is not null', p_table) using p_id;
    end if;
  exception when foreign_key_violation then
    raise exception 'مينفعش تتمسح نهائيًا — لسه مرتبطة بعمليات سابقة (مبيعات/مشتريات/قيود). ممكن تسيبها في السلة أو تستخدمي "استرجاع" لو محتاجاها.';
  end;

  perform fn_log_operation('PURGE_DELETED', jsonb_build_object('table', p_table, 'id', p_id));
end;
$$;

-- تنظيف تلقائي: أي حاجة في السلة من أكتر من 30 يوم تتمسح نهائيًا لوحدها
-- (لو فيه حاجة مرتبطة بعمليات سابقة، بتتخطى بأمان وتفضل في السلة)
create or replace function rpc_purge_old_deleted()
returns void language plpgsql security definer as $$
declare v_table text; v_row record; v_tables text[] := array['products','product_variants','customers','suppliers','employees','product_tree'];
begin
  foreach v_table in array v_tables loop
    for v_row in execute format('select %s as id_val from %I where deleted_at is not null and deleted_at < now() - interval ''30 days''',
      case when v_table = 'customers' then 'phone' else 'id' end, v_table)
    loop
      begin
        if v_table = 'customers' then
          execute format('delete from %I where phone = $1', v_table) using v_row.id_val;
        else
          execute format('delete from %I where id = $1::uuid', v_table) using v_row.id_val;
        end if;
      exception when foreign_key_violation then
        continue; -- سيبها في السلة، مرتبطة بعمليات سابقة
      end;
    end loop;
  end loop;
  perform fn_log_operation('PURGE_OLD_DELETED', jsonb_build_object('older_than_days', 30));
end;
$$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'daily-purge-old-deleted') then perform cron.unschedule('daily-purge-old-deleted'); end if;
exception when others then null;
end $$;
select cron.schedule('daily-purge-old-deleted', '30 3 * * *', $$select rpc_purge_old_deleted()$$);

-- ------------------------------------------------------------
-- تغيير مورد أوردر شراء كامل (لو اتسجل غلط على مورد غير الصح)
-- بينقل الأوردر بكل تفاصيله للمورد الجديد، من غير ما يأثر على
-- الحسابات أو المبالغ خالص (نفس الأرقام، مورد مختلف بس)
-- ------------------------------------------------------------
create or replace function rpc_reassign_purchase_order_supplier(p_order_id uuid, p_new_supplier_name text)
returns void language plpgsql security definer as $$
declare v_new_supplier_id uuid; v_order_number text;
begin
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_new_supplier_name is null or trim(p_new_supplier_name) = '' then raise exception 'اسم المورد الجديد مطلوب'; end if;

  select id into v_new_supplier_id from suppliers where name = p_new_supplier_name;
  if v_new_supplier_id is null then
    insert into suppliers (name) values (p_new_supplier_name) returning id into v_new_supplier_id;
  end if;

  select order_number into v_order_number from purchase_orders where id = p_order_id;
  if v_order_number is null then raise exception 'الأوردر غير موجود'; end if;

  update purchase_orders set supplier_id = v_new_supplier_id where id = p_order_id;
  update supplier_payments set supplier_id = v_new_supplier_id where order_id = p_order_id;

  perform fn_log_operation('REASSIGN_PURCHASE_ORDER_SUPPLIER', jsonb_build_object('order_number', v_order_number, 'new_supplier', p_new_supplier_name));
end;
$$;

grant execute on all functions in schema public to authenticated;
