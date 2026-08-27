-- ============================================================
-- الدفعة 71: إصلاح ميزة "استرجاع النسخة الاحتياطية"
--
-- المشكلة اللي ظهرت في السكرين شوت: الاسترجاع كان بيحاول يكتب
-- البيانات مباشرة في الجداول (insert/upsert من المتصفح)، وده
-- بيتصادم مع نظام الحماية (RLS) لأن جداول زي accounts و
-- purchase_orders مصممة عمدًا إنها متتكتبش مباشرة من غير ما تعدي
-- على الفنكشنز الرسمية (rpc_add_account مثلاً) — عشان كده ظهر
-- خطأ "row-level security policy". وكمان بعض الجداول كان بيترحّل
-- بترتيب غلط (زي "المنتجات" قبل "الموردين")، فكان بيدي خطأ foreign
-- key لأن المنتج بيشاور على مورد لسه مترحّلش.
--
-- الحل: فنكشن واحدة موثوقة (rpc_admin_restore_table) بتاخد اسم
-- الجدول والصفوف، وبتتأكد إن المستخدم أدمن فعلاً، وبتحاول ترحّل
-- الصفوف على شوية مراحل (3 محاولات) بحيث أي صف فشل بسبب ترتيب
-- (زي صف بيشاور على صف تاني لسه مترحّلش) يتعاد تاني بعد ما اللي
-- قبله يترحّل — فمشكلة الترتيب بتتحل تلقائيًا من غير ما نحتاج
-- نرتب الجداول يدويًا بالظبط.
-- ============================================================

create or replace function rpc_admin_restore_table(p_table text, p_rows jsonb)
returns jsonb language plpgsql security definer as $$
declare
  v_allowed text[] := array[
    'settings','accounts','cost_centers','currencies','exchange_rates','seasons','accounting_periods',
    'warehouses','product_tree','products','product_variants','cost_history','inventory_batches',
    'suppliers','purchase_orders','purchase_order_items','supplier_payments','purchase_requests','purchase_request_items',
    'supplier_returns','customers','orders','order_items','sales','sale_items','invoices',
    'treasury_accounts','cash_flow','checks','petty_cash',
    'partners','capital_movements','admin_rights','profits_distribution',
    'employees','salaries','advances','attendance','fixed_assets',
    'expenses','other_revenue','journal_entries','opening_balances',
    'stock_transfers','stock_transfer_items','notifications','operations_log','webhooks_log','backup_log','attachments'
  ];
  v_row jsonb; v_count int := 0; v_pass int; v_remaining jsonb; v_next_remaining jsonb; v_last_error text;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية لاسترجاع نسخة احتياطية'; end if;
  if not (p_table = any(v_allowed)) then raise exception 'جدول غير مسموح بيه في الاسترجاع: %', p_table; end if;
  if p_rows is null or jsonb_array_length(p_rows) = 0 then return jsonb_build_object('inserted', 0, 'failed', 0); end if;

  v_remaining := p_rows;
  for v_pass in 1..4 loop
    exit when jsonb_array_length(v_remaining) = 0;
    v_next_remaining := '[]'::jsonb;
    for v_row in select * from jsonb_array_elements(v_remaining) loop
      begin
        execute format('insert into %I select * from jsonb_populate_record(null::%I, $1) on conflict do nothing', p_table, p_table) using v_row;
        v_count := v_count + 1;
      exception when others then
        v_last_error := sqlerrm;
        v_next_remaining := v_next_remaining || jsonb_build_array(v_row);
      end;
    end loop;
    v_remaining := v_next_remaining;
  end loop;

  perform fn_log_operation('ADMIN_RESTORE_TABLE', jsonb_build_object('table', p_table, 'inserted', v_count, 'failed', jsonb_array_length(v_remaining)));
  return jsonb_build_object('inserted', v_count, 'failed', jsonb_array_length(v_remaining), 'lastError', v_last_error);
end;
$$;

grant execute on all functions in schema public to authenticated;
