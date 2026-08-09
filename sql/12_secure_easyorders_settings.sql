-- ============================================================
-- تحصين: منع أي مستخدم عادي (كاشير/بائع) من قراءة المفاتيح
-- الحساسة (EasyOrders) من جدول settings — بس الأدمن/الشريك يقدر
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

drop policy if exists "الكل يقرا الإعدادات" on settings;

create policy "قراءة الإعدادات العامة للكل" on settings for select using (
  key not in ('easyOrdersApiKey', 'easyOrdersSecret')
  or fn_has_permission('Settings', 'تعديل')
);

grant execute on all functions in schema public to authenticated;
