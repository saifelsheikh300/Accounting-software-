-- ============================================================
-- ⚠️⚠️⚠️ تحذير: السكريبت ده بيمسح كل بيانات البرنامج نهائيًا وبدون
-- رجعة، ما عدا: المخزون (منتجات/مخازن/فئات) بمورديه، المستخدمين،
-- الإعدادات، وأرصدة الخزنة والبنوك الحالية زي ما هي.
--
-- لازم تكون عملت نسخة احتياطية قبل ما تشغّل السطر ده (الإعدادات
-- → تنزيل نسخة احتياطية). مفيش استرجاع بعد التشغيل غير من نسخة
-- احتياطية.
-- ============================================================

truncate table
  accounts, journal_entries, opening_balances,
  customers, orders, order_items, sales, sale_items, invoices,
  purchase_orders, purchase_order_items, supplier_payments, purchase_requests, purchase_request_items, supplier_returns,
  cash_flow, checks, petty_cash,
  partners, capital_movements, admin_rights, profits_distribution,
  employees, salaries, advances, attendance, fixed_assets,
  expenses, other_revenue, prepaid_expenses,
  loans, loan_log,
  stock_transfers, stock_transfer_items,
  notifications, operations_log, webhooks_log, backup_log, attachments
restart identity cascade;

-- الأصول الثابتة عندها عمود last_depreciated_month وربنا مش محتاجينه بعد المسح، تركته زي ما هو (الجدول فاضي أصلًا)

select 'تم المسح ✅ — المخزون والموردين والمستخدمين والخزنة زي ما هما' as result;
