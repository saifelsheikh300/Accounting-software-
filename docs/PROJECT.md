# نظام الحسابات الشامل — توثيق المشروع

آخر تحديث: بيتحدث مع كل تعديل جوهري. لو بتفتحي شات جديد وربطتي الريبو ده، اقرأي الملف ده الأول قبل أي حاجة.

## نظرة عامة
نظام حسابات ومخزون شامل (ERP) لبراند ملابس (دليفري/محل فيزيائي + متجر أونلاين).
- **الواجهة:** HTML/CSS/JS عادي (بدون أي Framework)، مستضافة على **GitHub Pages**
- **الرابط الحي:** https://saifelsheikh300.github.io/Accounting-software-/
- **قاعدة البيانات:** Supabase (Postgres) — كل منطق الأعمال في RPC functions (PL/pgSQL)، مش في الواجهة
- **الريبو:** saifelsheikh300/Accounting-software- (فرع main)
- **النشر:** GitHub Actions (`.github/workflows/deploy.yml`) — النظام القديم (Legacy Jekyll) كان بيفشل باستمرار، اتحول لـ GitHub Actions بشكل نهائي. لو النشر وقف تاني، شغّلي الـ workflow يدويًا من تاب Actions في الريبو

## هيكل الملفات
```
index.html          — الصفحة الوحيدة (SPA)، فيها نظام قوائم منسدلة مخصص (لازم enhanceSelects_() بعد أي setContent_ يدوي)
css/style.css        — كل التنسيق
js/supabaseClient.js — إعداد الاتصال بـ Supabase
js/api.js            — كل استدعاءات قاعدة البيانات (RPC + Table queries)
js/app.js            — كل منطق الواجهة والصفحات
sql/                  — كل ملفات SQL بالترتيب (يتحدث مع كل تعديل في قاعدة البيانات)
docs/PROJECT.md       — الملف ده
```

## قاعدة البيانات — أهم الجداول
- `products` / `product_variants` — المنتجات ومتغيراتها (لون/مقاس). **كل منتج لازم يكون له متغير واحد على الأقل** وإلا هيبقى غير قابل للبيع
- `sales` / `sale_items` — المبيعات وبنودها (بيسجّل `unit_cost` وقت البيع كـ Snapshot)
- `purchase_orders` / `purchase_order_items` — أوردرات الشراء (تحديث تكلفة بمتوسط مرجح)
- `suppliers`, `customers`, `invoices` — الموردين والعملاء والفواتير (حساب مفتوح)
- `expenses`, `other_revenue`, `fixed_assets` — المصروفات والإيرادات الأخرى والأصول الثابتة
- `partners`, `capital_movements`, `admin_rights` — الشركاء ورأس المال ونسبة الإدارة
- `petty_cash`, `cash_flow`, `treasury_accounts` — العهدة والخزنة والحسابات البنكية المتعددة
- `accounts`, `journal_entries` — شجرة الحسابات ودفتر اليومية (**المصدر الحقيقي لكل التقارير المالية** — قائمة الدخل، ميزان المراجعة، الميزانية العمومية كلهم بيتحسبوا منه، مش من الجداول التشغيلية)
- `accounting_periods` — قفل الفترات المحاسبية (منع التعديل على شهر مقفول)
- `checks`, `currencies`, `exchange_rates`, `cost_centers` — شيكات، عملات متعددة، مراكز تكلفة

## دوال RPC مهمة (كلها SECURITY DEFINER، بتتحقق من الصلاحية بنفسها)
- `rpc_record_sale` — تسجيل بيعة (خزنة حقيقية + قيد COGS + دعم عملات + قفل فترات)
- `rpc_record_return` — مرتجع **مرتبط ببيعة معينة** (من صفحة سجل المبيعات)
- `rpc_record_standalone_return` — مرتجع **مباشر بالبحث عن المنتج** (من شاشة الكاشير)، بربط اختياري برقم فاتورة
- `rpc_create_purchase_order`, `rpc_pay_supplier_installment` — المشتريات
- `rpc_add_expense`, `rpc_add_petty_cash`, `rpc_add_other_revenue` — المصروفات/العهدة/الإيرادات
- `rpc_add_capital_movement`, `rpc_run_monthly_admin_fee`, `rpc_withdraw_admin_right` — رأس المال والشركاء
- `rpc_trial_balance`, `rpc_balance_sheet`, `rpc_income_statement`, `rpc_get_dashboard_data` — التقارير
- `rpc_close_period` / `rpc_reopen_period` — قفل/فتح فترة محاسبية
- `fn_move_treasury`, `fn_journal_entry` — هيلبرز داخلية بيتم استدعاؤهم من كل الدوال المالية

## ⚠️ درس مهم اتعلمناه: تضارب الدوال المكررة (Overloading)
لما بنعدّل دالة RPC ونضيفلها باراميتر جديد، `create or replace function` **بيعمل نسخة جديدة جنب القديمة** لو البصمة (الباراميترات) اتغيرت، مش بيستبدلها. ده سبب مشكلة "Could not choose the best candidate function" مرتين. **القاعدة من دلوقتي: أي تعديل على باراميترات دالة موجودة، لازم ملف الـ SQL يبدأ بـ:**
```sql
do $$
declare v_sig record;
begin
  for v_sig in select oid::regprocedure as sig from pg_proc where proname = 'اسم_الدالة'
  loop
    execute 'drop function if exists ' || v_sig.sig || ' cascade';
  end loop;
end $$;
```
**قبل ما نعمل `create or replace` بالنسخة الجديدة.**

## سجل ملفات SQL (بالترتيب — شغّليهم بالترتيب ده لو بتبنيها من الصفر)
كل ملفات الـSQL من 1 لـ25 محفوظة فعليًا في مجلد `sql/`، بدون أي فجوة.

| # | الملف | الوصف المختصر |
|---|---|---|
| 1 | `01_schema_users_settings.sql` | المستخدمون، الصلاحيات، الإعدادات، المخازن، المنتجات والمتغيرات |
| 2 | `02_schema_sales_purchases.sql` | المبيعات، المصروفات، الموردين، الأوردرات، الفواتير |
| 3 | `03_schema_capital_hr_journal.sql` | رأس المال، الشركاء، العهدة، الموارد البشرية، دفتر اليومية |
| 4 | `04_rpc_helpers_categories_sales.sql` | هيلبرز عامة، الفئات، تسجيل بيعة، مرتجع |
| 5 | `05_rpc_purchases_capital_pettycash.sql` | المشتريات، رأس المال، العهدة، الفواتير |
| 6 | `06_rpc_dashboard_reports_cron.sql` | الداشبورد المجمّع، قائمة الدخل، كشف حساب مورد |
| 7 | `07_accounts_opening_balances_treasury.sql` | شجرة الحسابات، أرصدة أول مدة، خزنة وبنوك متعددة، سلة محذوفات، مراكز تكلفة |
| 8 | `08_stock_transfers_purchase_requests.sql` | نقل مخزون بين المخازن، طلبات شراء واعتماد |
| 9 | `09_profitability_currencies_checks.sql` | تقييم مخزون بمتوسط مرجح، ربحية بالصنف/العميل، عملات متعددة، شيكات |
| 10 | `10_notifications_search_attachments.sql` | إشعارات داخلية، بحث موحّد، مرفقات |
| 11 | `11_stagnant_stock_sales_forecast.sql` | أصناف راكدة، توقع مبيعات إحصائي |
| 12 | `12_secure_easyorders_settings.sql` | تحصين مفاتيح EasyOrders من القراءة العامة |
| 13 | `13_update_category_product_add_with_variants.sql` | تعديل الفئات والمنتجات، إضافة منتج مع متغيراته دفعة واحدة |
| 14 | `14_open_invoice_add_items.sql` | فواتير حساب مفتوح مع أصناف حقيقية من المخزون |
| 15 | `15_fix_capital_movement_where_clause.sql` | إصلاح خطأ UPDATE بدون WHERE في حركة رأس المال |
| 16 | `16_capital_treasury_link_stock_guard.sql` | ربط رأس المال بالخزنة فعليًا، منع البيع بكمية أكبر من المتاح |
| 17 | `17_treasury_unification_cogs_expense_rpc.sql` | توحيد الخزنة الحقيقية، قيود COGS، مصروفات كـRPC آمن |
| 18 | `18_fix_cash_flow_balance_after.sql` | إصلاح باج balance_after في cash_flow + تصحيح تاريخي |
| 19 | `19_transfer_fix_return_cash_vs_credit.sql` | إصلاح التحويل بين الخزن، مرتجع يفرّق بين كاش وآجل |
| 20 | `20_comprehensive_accounting_audit_fix.sql` | فحص محاسبي شامل: شجرة حسابات فعّالة، ميزان مراجعة، ميزانية عمومية، إهلاك، قفل فترات، وأكتر |
| 21 | `21_dashboard_treasury_cash_bank_fix.sql` | إصلاح كارت الخزنة في الداشبورد (كاش/بنك من الأرصدة الفعلية بدل التخمين) |
| 22 | `22_product_no_variants_fix.sql` | إصلاح جذري: منتج بدون متغيرات كان غير قابل للبيع أو الظهور في البحث |
| 23 | `23_fix_overloaded_functions.sql` | إصلاح تضارب 8 دوال كانت متكررة (Overloading) |
| 24 | `24_standalone_return.sql` | مرتجع منتج مباشر (بحث عن منتج بدل البحث عن فاتورة) |
| 25 | `25_return_invoice_link.sql` | إضافة ربط اختياري للمرتجع المباشر برقم فاتورة |

## حالات معروفة / قيود حالية
- المرتجع المباشر (`rpc_record_standalone_return`) لا يتحقق من كمية أصلية في فاتورة — لو ربطتيه بفاتورة، الربط للمرجعية بس مش تحقق فعلي من الكمية
- `rpc_record_return` (مرتجع مرتبط ببيعة) بيوري "الكمية الأصلية" في الفاتورة مش "المتبقي بعد مرتجع سابق" — لو رجعتي جزء من فاتورة مرتين، محتاجة تكوني واعية للكمية يدويًا
- الفئات (`product_tree`) اختيارية — أي منتج من غير فئة محددة بيتحط في فئة "عام" تلقائيًا

## طريقة العمل المتفق عليها
- كل تعديل SQL بيتحفظ في `sql/` برقمه بالترتيب
- الملف ده (`docs/PROJECT.md`) بيتحدث مع أي تغيير جوهري في البنية أو الميزات
- كل تعديل في `js/app.js` أو `js/api.js` بيترفع فورًا على GitHub، ورقم الإصدار `?v=` في `index.html` بيتزود عشان نتجنب مشاكل الكاش
