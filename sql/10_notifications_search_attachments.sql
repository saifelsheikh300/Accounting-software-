-- ============================================================
-- الدفعة 4: إشعارات داخلية + Smart Search + مرفقات
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

-- ------------------------------------------------------------
-- 1) إشعارات داخلية
-- ------------------------------------------------------------
create table if not exists notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references profiles(id), -- null = إشعار عام لكل المستخدمين
  title text not null,
  body text default '',
  link_page text default '', -- مثال: 'inventory' عشان الضغط يوديها للصفحة
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists idx_notifications_user on notifications(user_id, is_read);

alter table notifications enable row level security;
drop policy if exists "المستخدم يشوف إشعاراته" on notifications;
create policy "المستخدم يشوف إشعاراته" on notifications for select using (user_id = auth.uid() or user_id is null);
drop policy if exists "المستخدم يعدل إشعاراته" on notifications;
create policy "المستخدم يعدل إشعاراته" on notifications for update using (user_id = auth.uid());
drop policy if exists "إنشاء إشعارات بصلاحية" on notifications;
create policy "إنشاء إشعارات بصلاحية" on notifications for insert with check (auth.role() = 'authenticated');

create or replace function fn_create_notification(p_user_id uuid, p_title text, p_body text default '', p_link text default '')
returns void language plpgsql security definer as $$
begin
  insert into notifications (user_id, title, body, link_page) values (p_user_id, p_title, p_body, p_link);
end;
$$;

-- إشعار تلقائي لكل الأدمن/الشركاء عند نفاد صنف عن الحد الأدنى
create or replace function fn_notify_low_stock()
returns trigger language plpgsql security definer as $$
begin
  if new.quantity <= new.low_stock_threshold and (old.quantity is null or old.quantity > new.low_stock_threshold) then
    perform fn_create_notification(p.id, 'مخزون منخفض ⚠️', 'الصنف ' || new.code || ' وصل لحد إعادة الطلب', 'inventory')
    from profiles p where p.role in ('أدمن','شريك');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_low_stock on product_variants;
create trigger trg_notify_low_stock after update of quantity on product_variants
  for each row execute function fn_notify_low_stock();

-- إشعار عند استحقاق شيك خلال 3 أيام (تُنفَّذ يدويًا أو عبر Cron يومي)
create or replace function rpc_check_upcoming_checks_due()
returns void language plpgsql security definer as $$
declare v_check record;
begin
  for v_check in select * from checks where status = 'تحت التحصيل' and due_date between current_date and current_date + 3 loop
    perform fn_create_notification(p.id, 'شيك مستحق قريبًا 📑', 'شيك ' || v_check.check_number || ' — ' || v_check.party_name || ' مستحق في ' || v_check.due_date, 'checks')
    from profiles p where p.role in ('أدمن','شريك');
  end loop;
end;
$$;
-- select cron.schedule('daily-check-reminders', '0 8 * * *', $$select rpc_check_upcoming_checks_due()$$);

-- ------------------------------------------------------------
-- 2) Smart Search شامل — بحث موحّد عبر منتجات/عملاء/موردين/فواتير
-- ------------------------------------------------------------
create or replace function rpc_global_search(p_query text)
returns jsonb language plpgsql security definer as $$
declare v_result jsonb;
begin
  if not fn_has_permission('Dashboard', 'عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select jsonb_build_object(
    'products', coalesce((select jsonb_agg(jsonb_build_object('type','منتج','code', pv.code, 'label', p.name || ' - ' || pv.code, 'page', 'inventory'))
      from product_variants pv join products p on p.id = pv.product_id
      where pv.deleted_at is null and (pv.code ilike '%'||p_query||'%' or p.name ilike '%'||p_query||'%') limit 8), '[]'::jsonb),
    'customers', coalesce((select jsonb_agg(jsonb_build_object('type','عميل','code', phone, 'label', coalesce(name,phone), 'page','orders'))
      from customers where deleted_at is null and (name ilike '%'||p_query||'%' or phone ilike '%'||p_query||'%') limit 8), '[]'::jsonb),
    'suppliers', coalesce((select jsonb_agg(jsonb_build_object('type','مورد','code', id::text, 'label', name, 'page','suppliers'))
      from suppliers where deleted_at is null and name ilike '%'||p_query||'%' limit 8), '[]'::jsonb),
    'invoices', coalesce((select jsonb_agg(jsonb_build_object('type','فاتورة','code', invoice_number, 'label', invoice_number || ' - ' || customer_name, 'page','invoices'))
      from invoices where invoice_number ilike '%'||p_query||'%' or customer_name ilike '%'||p_query||'%' limit 8), '[]'::jsonb)
  ) into v_result;

  return v_result;
end;
$$;

-- ------------------------------------------------------------
-- 3) نظام المرفقات — رابط لملف مرفوع على Supabase Storage
-- (لازم تعملي Bucket اسمه "attachments" من Storage في Supabase يدوي، Public أو Private حسب رغبتك)
-- ------------------------------------------------------------
create table if not exists attachments (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null, -- 'purchase_order','invoice','expense','employee', ...
  entity_id text not null,
  file_name text not null,
  file_url text not null,
  uploaded_by uuid references profiles(id),
  uploaded_at timestamptz not null default now()
);
create index if not exists idx_attachments_entity on attachments(entity_type, entity_id);

alter table attachments enable row level security;
drop policy if exists "قراءة عامة attachments" on attachments;
create policy "قراءة عامة attachments" on attachments for select using (auth.role() = 'authenticated');
drop policy if exists "إضافة مرفقات بصلاحية" on attachments;
create policy "إضافة مرفقات بصلاحية" on attachments for insert with check (auth.role() = 'authenticated');
drop policy if exists "حذف مرفقات بصلاحية" on attachments;
create policy "حذف مرفقات بصلاحية" on attachments for delete using (auth.role() = 'authenticated');

grant execute on all functions in schema public to authenticated;
