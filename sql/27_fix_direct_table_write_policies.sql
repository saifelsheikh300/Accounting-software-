-- ============================================================
-- الدفعة 27: إغلاق ثغرة الكتابة المباشرة على الجداول المالية
-- الجداول دي عليها policy من نوع "for all" مبنية على صلاحية واحدة
-- (زي "مبيعات - تعديل")، ومعناها إن أي حد عنده الصلاحية دي يقدر
-- يعمل INSERT/UPDATE/DELETE مباشر على الجدول نفسه من غير ما يمر
-- على الدوال (RPC) اللي بتعمل القيد المحاسبي وتحديث الخزنة والمخزون
-- (rpc_record_sale, fn_journal_entry, fn_move_treasury...).
-- ده بيسمح بتلاعب صامت: مسح بيعة، تغيير رصيد خزنة، تغيير كمية
-- صنف — من غير ما يفضل أي أثر في دفتر اليومية.
--
-- الحل: نفس أسلوب جدول journal_entries المعمول صح من الأول —
-- القراءة بصلاحية، والكتابة المباشرة ممنوعة تمامًا (كل التعديل
-- لازم يعدي من خلال الدوال اللي بتعمل القيد الصحيح معاه).
--
-- المجموعة (أ): قفل كامل (SELECT بس) — تأكدنا إن الواجهة (app.js
-- و api.js) مش بتكتب على الجداول دي مباشرة أصلاً، كله من خلال RPC:
--   sales, purchase_orders, expenses, other_revenue,
--   capital_movements, advances, petty_cash, accounts
--
-- المجموعة (ب): قفل جزئي (INSERT بس، ممنوع UPDATE/DELETE) — لأن
-- فيه شاشات موجودة فعلاً بتضيف صف جديد مباشرة (إضافة حساب خزنة/بنك
-- جديد، إنشاء فاتورة حساب مفتوح، تسجيل شيك) لكن معدلش رصيد موجود:
--   treasury_accounts, invoices, checks
--
-- ملحوظة: sale_items, purchase_order_items, journal_entries,
-- cash_flow أصلاً محميين من قبل (SELECT بس)، مفيش داعي نلمسهم.
-- ملحوظة تانية: product_variants و salaries متعمدش نلمسهم في
-- الملف ده لأن فيه شاشات حالية بتعدل عليهم مباشرة (تصحيح كمية/
-- تكلفة يدوي، وشاشة الرواتب) — ده يحتاج قرار منفصل بعدين.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

-- ------------------------------------------------------------
-- المجموعة (أ): قفل كامل — تصبح كتابة بس من خلال RPC
-- ------------------------------------------------------------
drop policy if exists "تعديل بصلاحية sales" on sales;

drop policy if exists "تعديل بصلاحية po" on purchase_orders;

drop policy if exists "تعديل بصلاحية expenses" on expenses;

drop policy if exists "تعديل بصلاحية other_revenue" on other_revenue;

drop policy if exists "تعديل بصلاحية capital_movements" on capital_movements;

drop policy if exists "تعديل بصلاحية advances" on advances;

drop policy if exists "تعديل بصلاحية petty_cash" on petty_cash;

drop policy if exists "تعديل بصلاحية accounts" on accounts;

-- ------------------------------------------------------------
-- المجموعة (ب): قفل جزئي — INSERT مسموح، UPDATE/DELETE ممنوع
-- ------------------------------------------------------------
drop policy if exists "تعديل بصلاحية treasury_accounts" on treasury_accounts;
drop policy if exists "إضافة حساب خزنة جديد" on treasury_accounts;
create policy "إضافة حساب خزنة جديد" on treasury_accounts for insert with check (fn_has_permission('Reports','تعديل'));

drop policy if exists "تعديل بصلاحية invoices" on invoices;
drop policy if exists "إنشاء فاتورة جديدة" on invoices;
create policy "إنشاء فاتورة جديدة" on invoices for insert with check (fn_has_permission('Invoices','تعديل'));

drop policy if exists "تعديل بصلاحية checks" on checks;
drop policy if exists "تسجيل شيك جديد" on checks;
create policy "تسجيل شيك جديد" on checks for insert with check (fn_has_permission('Reports','تعديل'));
