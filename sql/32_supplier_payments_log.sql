-- ============================================================
-- الدفعة 32: سجل دفعات تفصيلي لكل مورد (كل دفعة سطر منفصل)
-- قبل كده، كل دفعة كانت بترفع رقم "amount_paid" الإجمالي بس من غير
-- سجل منفصل لكل دفعة على حدة. دلوقتي كل دفعة بتتسجل كصف مستقل
-- (المبلغ، التاريخ، أوردر الشراء) — فلو حصل أي خلاف مع مورد،
-- كل دفعة موثقة بتاريخها بالظبط.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

create table if not exists supplier_payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references purchase_orders(id) on delete cascade,
  supplier_id uuid not null references suppliers(id) on delete cascade,
  amount numeric(12,2) not null,
  paid_at timestamptz not null default now(),
  treasury_account_id uuid references treasury_accounts(id)
);

alter table supplier_payments enable row level security;
drop policy if exists "قراءة بصلاحية عرض supplier_payments" on supplier_payments;
create policy "قراءة بصلاحية عرض supplier_payments" on supplier_payments for select using (fn_has_permission('Suppliers','عرض'));

-- إعادة إنشاء الدالة عشان تسجل كل دفعة كصف منفصل بالإضافة للرقم الإجمالي
do $$
declare v_sig record;
begin
  for v_sig in select oid::regprocedure as sig from pg_proc where proname = 'rpc_pay_supplier_installment'
  loop
    execute 'drop function if exists ' || v_sig.sig || ' cascade';
  end loop;
end $$;

create or replace function rpc_pay_supplier_installment(p_order_id uuid, p_amount numeric, p_treasury_account_id uuid default null)
returns void language plpgsql security definer as $$
declare v_total numeric; v_paid numeric; v_new_paid numeric; v_new_remaining numeric; v_order_number text; v_supplier_id uuid;
begin
  if not fn_has_permission('Suppliers', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select total, amount_paid, order_number, supplier_id into v_total, v_paid, v_order_number, v_supplier_id from purchase_orders where id = p_order_id;
  v_new_paid := v_paid + p_amount;
  v_new_remaining := v_total - v_new_paid;
  if v_new_remaining < 0 then raise exception 'المبلغ أكبر من المتبقي'; end if;

  update purchase_orders set amount_paid = v_new_paid, remaining = v_new_remaining,
    payment_status = case when v_new_remaining = 0 then 'مدفوع بالكامل' else 'مدفوع جزئيًا' end
    where id = p_order_id;

  insert into supplier_payments (order_id, supplier_id, amount, treasury_account_id)
    values (p_order_id, v_supplier_id, p_amount, p_treasury_account_id);

  perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, 'دفعة أوردر شراء ' || v_order_number);
  perform fn_journal_entry('الموردون', 'الخزينة', p_amount, v_order_number, 'دفعة أوردر شراء ' || v_order_number);
  perform fn_log_operation('PAY_SUPPLIER_INSTALLMENT', jsonb_build_object('order_id', p_order_id, 'amount', p_amount));
end;
$$;

-- تحديث كشف الحساب عشان يرجع سجل الدفعات كمان
create or replace function rpc_get_supplier_statement(p_supplier_id uuid)
returns jsonb language plpgsql security definer as $$
declare
  v_supplier jsonb; v_purchases jsonb; v_payments jsonb; v_total numeric; v_paid numeric; v_remaining numeric;
begin
  select to_jsonb(s) into v_supplier from suppliers s where id = p_supplier_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'orderNumber', order_number, 'date', order_date, 'total', total,
    'paymentStatus', payment_status, 'amountPaid', amount_paid, 'remaining', remaining
  ) order by order_date desc), '[]'::jsonb),
  coalesce(sum(total), 0), coalesce(sum(amount_paid), 0), coalesce(sum(remaining), 0)
  into v_purchases, v_total, v_paid, v_remaining
  from purchase_orders where supplier_id = p_supplier_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'orderNumber', po.order_number, 'amount', sp.amount, 'paidAt', sp.paid_at
  ) order by sp.paid_at desc), '[]'::jsonb)
  into v_payments
  from supplier_payments sp join purchase_orders po on po.id = sp.order_id
  where sp.supplier_id = p_supplier_id;

  return jsonb_build_object(
    'supplier', v_supplier, 'purchases', v_purchases, 'payments', v_payments,
    'totalPurchases', v_total, 'totalPaid', v_paid, 'totalRemaining', v_remaining
  );
end;
$$;

grant execute on all functions in schema public to authenticated;
