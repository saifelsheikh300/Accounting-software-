-- ============================================================
-- الدفعة 73: إصلاح تعارض IDs الحسابات عند الاسترجاع
--
-- المشكلة: البرنامج بيزرع دليل حسابات افتراضي تلقائيًا أول ما
-- الأدمن يسجّل دخول (rpc_seed_default_chart_of_accounts) لو
-- الجهاز/القاعدة فاضية. فلو سجّلت دخول على الجهاز التاني قبل
-- الاسترجاع، بيتزرع دليل حسابات بـ IDs جديدة مختلفة عن الأصلية.
-- بعدين لما نسترجع حسابات النسخة الاحتياطية، أي حساب "بنفس الكود"
-- (زي "المخزون" كود 1140 مثلاً) موجود أصلاً بيتخطى (عشان الكود
-- unique)، فيفضل الحساب الجديد بـ ID مختلف — وأي قيد يومية قديم
-- بيحاول يربط بالـ ID الأصلي القديم مش بيلاقيه = foreign key error.
--
-- الحل: جدول تحويل مؤقت (restore_account_remap) بيسجل "الحساب
-- القديم ده بقى نفسه إيه في القاعدة الجديدة" حسب الكود، وأي جدول
-- بيشاور على accounts (journal_entries, opening_balances) بيتصحح
-- تلقائيًا حسب الجدول ده وقت الاسترجاع.
-- ============================================================

create table if not exists restore_account_remap (
  old_id uuid primary key,
  new_id uuid not null
);
alter table restore_account_remap enable row level security;
drop policy if exists "أدمن بس" on restore_account_remap;
create policy "أدمن بس" on restore_account_remap for all using (fn_has_permission('Reports','تعديل'));

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
  v_existing_id uuid; v_old_id uuid; v_debit uuid; v_credit uuid; v_acct uuid;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية لاسترجاع نسخة احتياطية'; end if;
  if not (p_table = any(v_allowed)) then raise exception 'جدول غير مسموح بيه في الاسترجاع: %', p_table; end if;
  if p_rows is null or jsonb_array_length(p_rows) = 0 then return jsonb_build_object('inserted', 0, 'failed', 0); end if;

  -- ✅ حالة خاصة: الحسابات — لو الكود موجود، منسجلش تكرار، بس نسجل
  -- في جدول التحويل إن الـ ID القديم ده بقى يقصد الحساب الموجود ده
  if p_table = 'accounts' then
    delete from restore_account_remap; -- بداية جلسة استرجاع جديدة، نمسح أي تحويلات قديمة
    v_remaining := p_rows;
    for v_pass in 1..4 loop
      exit when jsonb_array_length(v_remaining) = 0;
      v_next_remaining := '[]'::jsonb;
      for v_row in select * from jsonb_array_elements(v_remaining) loop
        begin
          v_old_id := (v_row->>'id')::uuid;
          select id into v_existing_id from accounts where code = (v_row->>'code');
          if v_existing_id is not null then
            insert into restore_account_remap (old_id, new_id) values (v_old_id, v_existing_id) on conflict (old_id) do update set new_id = excluded.new_id;
          else
            insert into accounts (id, code, name, type, parent_id, is_group, active)
            values (v_old_id, v_row->>'code', v_row->>'name', v_row->>'type',
              case when v_row->>'parent_id' is not null then coalesce((select new_id from restore_account_remap where old_id = (v_row->>'parent_id')::uuid), (v_row->>'parent_id')::uuid) else null end,
              coalesce((v_row->>'is_group')::boolean, false), coalesce((v_row->>'active')::boolean, true));
            insert into restore_account_remap (old_id, new_id) values (v_old_id, v_old_id) on conflict (old_id) do update set new_id = excluded.new_id;
          end if;
          v_count := v_count + 1;
        exception when others then
          v_last_error := sqlerrm;
          v_next_remaining := v_next_remaining || jsonb_build_array(v_row);
        end;
      end loop;
      v_remaining := v_next_remaining;
    end loop;
    return jsonb_build_object('inserted', v_count, 'failed', jsonb_array_length(v_remaining), 'lastError', v_last_error);
  end if;

  v_remaining := p_rows;
  for v_pass in 1..4 loop
    exit when jsonb_array_length(v_remaining) = 0;
    v_next_remaining := '[]'::jsonb;
    for v_row in select * from jsonb_array_elements(v_remaining) loop
      begin
        -- ✅ نصحح مراجع الحسابات في القيود اليومية وأرصدة أول المدة حسب جدول التحويل
        if p_table = 'journal_entries' and (v_row ? 'debit_account_id' or v_row ? 'credit_account_id') then
          v_debit := coalesce((select new_id from restore_account_remap where old_id = (v_row->>'debit_account_id')::uuid), (v_row->>'debit_account_id')::uuid);
          v_credit := coalesce((select new_id from restore_account_remap where old_id = (v_row->>'credit_account_id')::uuid), (v_row->>'credit_account_id')::uuid);
          v_row := v_row || jsonb_build_object('debit_account_id', v_debit, 'credit_account_id', v_credit);
        elsif p_table = 'opening_balances' and v_row ? 'account_id' and v_row->>'account_id' is not null then
          v_acct := coalesce((select new_id from restore_account_remap where old_id = (v_row->>'account_id')::uuid), (v_row->>'account_id')::uuid);
          v_row := v_row || jsonb_build_object('account_id', v_acct);
        end if;

        execute format('insert into %I overriding system value select * from jsonb_populate_record(null::%I, $1) on conflict do nothing', p_table, p_table) using v_row;
        v_count := v_count + 1;
      exception when others then
        v_last_error := sqlerrm;
        v_next_remaining := v_next_remaining || jsonb_build_array(v_row);
      end;
    end loop;
    v_remaining := v_next_remaining;
  end loop;

  -- ✅ الجداول اللي بترقّم صفوفها تلقائيًا (identity) لازم "نزبط" العداد
  -- بعد ما نحط فيها IDs جاهزة يدويًا، وإلا أول عملية تسجيل تلقائية
  -- بعد كده هتصطدم بنفس الرقم وتدي خطأ "duplicate key"
  if p_table in ('operations_log', 'webhooks_log', 'backup_log') then
    execute format('select setval(pg_get_serial_sequence(%L, ''id''), coalesce((select max(id) from %I), 1))', p_table, p_table);
  end if;

  perform fn_log_operation('ADMIN_RESTORE_TABLE', jsonb_build_object('table', p_table, 'inserted', v_count, 'failed', jsonb_array_length(v_remaining)));
  return jsonb_build_object('inserted', v_count, 'failed', jsonb_array_length(v_remaining), 'lastError', v_last_error);
end;
$$;

grant execute on all functions in schema public to authenticated;
