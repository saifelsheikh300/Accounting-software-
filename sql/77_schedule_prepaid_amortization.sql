-- ============================================================
-- الدفعة 77: إضافة استهلاك المصروفات المقدمة للجدولة التلقائية
-- (لازم تكوني شغّلتي ملف 75 الأول عشان pg_cron يكون مفعّل)
-- ============================================================

do $$
begin
  if exists (select 1 from cron.job where jobname = 'monthly-prepaid-amortization') then
    perform cron.unschedule('monthly-prepaid-amortization');
  end if;
exception when others then null;
end $$;

-- أول يوم في الشهر الساعة 2:10 بالليل (بعد الإهلاك ونسبة الإدارة)
select cron.schedule('monthly-prepaid-amortization', '10 2 1 * *', $$select rpc_run_prepaid_amortization()$$);
