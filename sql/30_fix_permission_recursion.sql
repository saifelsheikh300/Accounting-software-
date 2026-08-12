-- ============================================================
-- الدفعة 30: إصلاح حلقة لا نهائية في fn_has_permission
-- (السبب الحقيقي وراء "stack depth limit exceeded")
--
-- الدالة كانت بتقرا من profiles وهي خاضعة لنفس سياسة الحماية اللي
-- بتستخدم الدالة نفسها → حلقة لا نهائية ممكن تحصل مع أي مستخدم في أي
-- وقت. الحل: SECURITY DEFINER بتخلي القراءة الداخلية من profiles
-- تتجاوز RLS تمامًا (تشتغل بصلاحية مالك الدالة، مش صلاحية الطالب)،
-- فمفيش استدعاء متكرر للدالة نفسها.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

create or replace function fn_has_permission(p_module text, p_level text)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_role text;
  v_perm text;
  v_levels text[] := array['مخفي', 'عرض', 'تعديل'];
begin
  select role, permissions->>p_module into v_role, v_perm
  from profiles where id = auth.uid();

  if v_role is null then return false; end if;
  if v_role = 'أدمن' then return true; end if;
  if v_role = 'شريك' and v_perm is null then v_perm := 'عرض'; end if;
  if v_perm is null then v_perm := 'مخفي'; end if;

  return array_position(v_levels, v_perm) >= array_position(v_levels, p_level);
end;
$$;

grant execute on function fn_has_permission(text, text) to authenticated, anon;
