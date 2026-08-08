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
انظري مجلد `sql/` — كل ملف فيه رقمه في اسمه. الملفات الأساسية (1-20: الـSchema الكامل + كل الإصلاحات المحاسبية الأولى) اتبعتت كنصوص في المحادثات الأولى قبل ما نبدأ نحفظها كملفات فعلية في الريبو — لو محتاجة نسخة منها، قوليلي وهعيد إنشاءها من سجل المحادثة. من رقم 21 وطالع، كل حاجة محفوظة هنا فعليًا.

| # | الملف | الوصف المختصر |
|---|---|---|
| 21 | `21_fix_overloaded_functions.sql` | إصلاح تضارب 8 دوال كانت متكررة (rpc_record_sale, rpc_create_purchase_order, rpc_add_expense, rpc_add_petty_cash, rpc_pay_invoice_installment, rpc_pay_supplier_installment, rpc_update_check_status, rpc_add_capital_movement) |
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
