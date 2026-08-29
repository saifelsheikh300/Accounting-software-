-- ============================================================
-- الدفعة 75: تفعيل الجدولة التلقائية (بدل الزراير اليدوية)
--
-- ده بيشغّل تلقائيًا أول كل شهر:
--   - إهلاك الأصول الثابتة
--   - نسبة إدارة الشركاء الشهرية
-- وكل يوم الساعة 8 الصبح:
--   - تذكير بالشيكات المستحقة قريبًا
--
-- ⚠️ مهم: لازم "Extension" اسمه pg_cron يكون مفعّل في مشروعك على
-- Supabase الأول، وإلا السطر الأول هيدي خطأ. فعّليه من:
-- Database → Extensions → دوري على pg_cron → فعّليه (Enable)
-- بعد كده ارجعي شغّلي السكريبت ده تاني.
-- ============================================================

create extension if not exists pg_cron;

-- بنمسح أي جدولة قديمة بنفس الاسم عشان التشغيل يكون آمن لو كررناه
do $$
begin
  if exists (select 1 from cron.job where jobname = 'monthly-depreciation') then perform cron.unschedule('monthly-depreciation'); end if;
  if exists (select 1 from cron.job where jobname = 'monthly-admin-fee') then perform cron.unschedule('monthly-admin-fee'); end if;
  if exists (select 1 from cron.job where jobname = 'daily-check-reminders') then perform cron.unschedule('daily-check-reminders'); end if;
exception when others then null; -- لو الجدولة مكنتش موجودة أصلًا، تجاهلي الخطأ
end $$;

-- أول يوم في الشهر الساعة 2 بالليل: إهلاك الأصول
select cron.schedule('monthly-depreciation', '0 2 1 * *', $$select rpc_run_monthly_depreciation()$$);

-- أول يوم في الشهر الساعة 2:05 بالليل: نسبة إدارة الشركاء
select cron.schedule('monthly-admin-fee', '5 2 1 * *', $$select rpc_run_monthly_admin_fee()$$);

-- كل يوم الساعة 8 الصبح: تذكير بالشيكات المستحقة (لو الفنكشن دي موجودة عندك)
do $$
begin
  if exists (select 1 from pg_proc where proname = 'rpc_check_upcoming_checks_due') then
    perform cron.schedule('daily-check-reminders', '0 8 * * *', $$select rpc_check_upcoming_checks_due()$$);
  end if;
end $$;
