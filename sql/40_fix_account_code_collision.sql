-- ============================================================
-- الدفعة 40: إصلاح خطأ "duplicate key value violates unique
-- constraint accounts_code_key" اللي كان بيحصل عند إنشاء أمر
-- شراء أو أي عملية بتحتاج تنشئ حساب جديد تلقائيًا (مورد جديد،
-- مصروف جديد، إلخ)
--
-- السبب: fn_resolve_account كانت بتحسب رقم الحساب الجديد
-- بـ COUNT(*) لعدد الحسابات الموجودة تحت نفس المجموعة. لو فيه
-- أي فجوة في الترقيم (حساب اتمسح قبل كده، أو الترقيم اتغيّر في
-- تحديثات سابقة زي 36/37/39)، الـ COUNT بيديها رقم أقل من اللازم
-- فبيحاول يستخدم كود مستخدم بالفعل → تصادم.
--
-- الإصلاح: بقت بتحسب أعلى رقم فعلي مستخدم فعلاً (MAX) مش عدد
-- الصفوف، بالإضافة لإعادة محاولة تلقائية (retry loop) لو حصل
-- تصادم برضو لأي سبب (حماية إضافية لو عمليتين حصلوا في نفس اللحظة)
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

create or replace function fn_resolve_account(p_name text)
returns uuid language plpgsql security definer as $$
declare
  v_id uuid; v_type text; v_parent_code text; v_parent_id uuid;
  v_max_n int; v_new_code text; v_sub_group text; v_attempt int;
begin
  if p_name is null or trim(p_name) = '' then return null; end if;

  select id into v_id from accounts where name = p_name;
  if v_id is not null then return v_id; end if;

  v_type := case
    when p_name ilike 'المصروفات%' or p_name ilike 'تكلفة البضاعة%' or p_name ilike '%اهلاك%' or p_name ilike '%إهلاك%' or p_name ilike 'المرتبات%' then 'مصروفات'
    when p_name ilike 'المبيعات%' or p_name ilike '%إيرادات%' then 'إيرادات'
    when p_name ilike '%رأس المال%' then 'حقوق ملكية'
    when p_name ilike '%الموردون%' or p_name ilike '%دائن%' or p_name ilike 'شيكات دفع%' or p_name ilike 'مستحقات%' then 'خصوم'
    else 'أصول'
  end;

  v_parent_code := case v_type
    when 'مصروفات' then '5' when 'إيرادات' then '4' when 'حقوق ملكية' then '3'
    when 'خصوم' then '2.1'
    else '1.1'
  end;
  v_sub_group := case v_parent_code when '1.1' then 'أصول متداولة' when '2.1' then 'خصوم متداولة' else null end;
  select id into v_parent_id from accounts where code = v_parent_code;

  v_attempt := 0;
  loop
    v_attempt := v_attempt + 1;

    -- أعلى رقم فعلي مستخدم تحت المجموعة دي (مش عدد الصفوف)
    select coalesce(max(substring(code from '([0-9]+)$')::int), 0)
      into v_max_n
      from accounts where parent_id = v_parent_id;

    v_new_code := v_parent_code || '.' || lpad((v_max_n + 1 + (v_attempt - 1))::text, 3, '0');

    begin
      insert into accounts (code, name, type, is_group, parent_id, sub_group)
      values (v_new_code, p_name, v_type, false, v_parent_id, v_sub_group)
      returning id into v_id;
      return v_id;
    exception when unique_violation then
      if v_attempt >= 20 then raise; end if;
      -- فيه تصادم رغم ده (نادر جدًا) — كرري بمحاولة تالية
    end;
  end loop;
end;
$$;

grant execute on all functions in schema public to authenticated;
