-- ============================================================
-- الدفعة 43: إصلاح كراش "duplicate key ... accounts_code_key" في
-- دالة تعمير شجرة الحسابات (رقم 42).
--
-- السبب: الدالة كانت بتتأكد إن الاسم مش موجود بس، مش الكود. لو
-- كان فيه حساب اتعمل قبل كده تلقائي (زي "رأس المال" أو غيره) من
-- خلال fn_resolve_account بكود تلقائي زي 3.001، والدالة بتحاول
-- تضيف حساب جديد بنفس الكود ده باسم مختلف شوية، بيحصل تصادم.
--
-- الإصلاح: بقت بتتأكد إن الكود أو الاسم مش موجودين قبل ما تضيف
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

create or replace function rpc_seed_default_chart_of_accounts()
returns void language plpgsql security definer as $$
declare
  v_1 uuid; v_11 uuid; v_12 uuid; v_2 uuid; v_21 uuid;
begin
  insert into accounts (code, name, type, is_group)
  select code, name, type, true from (values
    ('1','الأصول','أصول'), ('2','الخصوم','خصوم'), ('3','حقوق الملكية','حقوق ملكية'),
    ('4','الإيرادات','إيرادات'), ('5','المصروفات','مصروفات')
  ) as t(code, name, type)
  where not exists (select 1 from accounts a where a.code = t.code or a.name = t.name);

  select id into v_1 from accounts where code = '1';
  select id into v_2 from accounts where code = '2';

  insert into accounts (code, name, type, is_group, parent_id)
  select '1.1', 'أصول متداولة', 'أصول', true, v_1 where not exists (select 1 from accounts where code = '1.1' or name = 'أصول متداولة');
  insert into accounts (code, name, type, is_group, parent_id)
  select '1.2', 'أصول ثابتة', 'أصول', true, v_1 where not exists (select 1 from accounts where code = '1.2' or name = 'أصول ثابتة');
  insert into accounts (code, name, type, is_group, parent_id)
  select '2.1', 'خصوم متداولة', 'خصوم', true, v_2 where not exists (select 1 from accounts where code = '2.1' or name = 'خصوم متداولة');
  insert into accounts (code, name, type, is_group, parent_id)
  select '2.2', 'خصوم طويلة الأجل', 'خصوم', true, v_2 where not exists (select 1 from accounts where code = '2.2' or name = 'خصوم طويلة الأجل');

  select id into v_11 from accounts where code = '1.1';
  select id into v_12 from accounts where code = '1.2';
  select id into v_21 from accounts where code = '2.1';

  insert into accounts (code, name, type, is_group, parent_id, sub_group)
  select v.code, v.name, v.type, false, v.parent_id, v.sub_group from (values
    ('1.1.001', 'الخزينة', 'أصول', v_11, 'أصول متداولة'),
    ('1.1.002', 'العملاء (مدينون)', 'أصول', v_11, 'أصول متداولة'),
    ('1.1.003', 'العهدة', 'أصول', v_11, 'أصول متداولة'),
    ('1.1.004', 'المخزون', 'أصول', v_11, 'أصول متداولة'),
    ('1.2.001', 'الأصول الثابتة', 'أصول', v_12, null),
    ('1.2.002', 'مجمع إهلاك الأصول', 'أصول', v_12, null),
    ('2.1.001', 'الموردون', 'خصوم', v_21, 'خصوم متداولة'),
    ('3.001', 'رأس المال', 'حقوق ملكية', null, null),
    ('3.002', 'رصيد افتتاحي', 'حقوق ملكية', null, null),
    ('4.001', 'المبيعات', 'إيرادات', null, null),
    ('4.002', 'إيرادات أخرى', 'إيرادات', null, null),
    ('5.001', 'تكلفة البضاعة المباعة', 'مصروفات', null, null),
    ('5.002', 'المرتبات', 'مصروفات', null, null),
    ('5.003', 'المصروفات: إيجار', 'مصروفات', null, null),
    ('5.004', 'المصروفات: كهرباء ومياه', 'مصروفات', null, null),
    ('5.005', 'المصروفات: مواصلات', 'مصروفات', null, null),
    ('5.006', 'المصروفات: صيانة', 'مصروفات', null, null),
    ('5.007', 'المصروفات: تسويق وإعلان', 'مصروفات', null, null),
    ('5.008', 'المصروفات: أخرى', 'مصروفات', null, null)
  ) as v(code, name, type, parent_id, sub_group)
  where not exists (select 1 from accounts a where a.code = v.code or a.name = v.name);
end;
$$;

grant execute on all functions in schema public to authenticated;

select rpc_seed_default_chart_of_accounts();
