-- ============================================================
-- الدفعة 45: مسح حسابات المصروفات "الوهمية" اللي أنا اخترعتها
-- في ملف 42 (المرتبات، إيجار، كهرباء ومياه، مواصلات، صيانة،
-- تسويق وإعلان، أخرى) — دي مش معتمد عليها في أي مكان في الكود،
-- لأن فئات المصروفات عندك حرة (بتكتبيها بنفسك من "+ فئة جديدة")
-- والبرنامج بيعمل لها حساب مناسب تلقائي أول ما تستخدميها فعليًا
-- (زي "5.009 – مصاريف تشغيلية" اللي طلعت لوحدها). يعني الحسابات
-- الجاهزة دي كانت هتفضل فاضية من غير أي استخدام.
--
-- بيتمسحوا بس لو مالهمش أي حركة مسجلة عليهم فعليًا (حماية —
-- لو استخدمتي أي واحد فيهم بالفعل، هيتسيب زي ما هو من غير مسح).
-- تكلفة البضاعة المباعة (5.001) مش بتتمسح لأنها مرتبطة مباشرة
-- بمعادلة حساب الربح في كل عملية بيع.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

delete from accounts a
where a.code in ('5.002','5.003','5.004','5.005','5.006','5.007','5.008')
  and not exists (select 1 from journal_entries j where j.debit_account_id = a.id or j.credit_account_id = a.id);

create or replace function rpc_seed_default_chart_of_accounts()
returns void language plpgsql security definer as $$
declare
  v_1 uuid; v_11 uuid; v_12 uuid; v_2 uuid; v_21 uuid; v_3 uuid; v_4 uuid; v_5 uuid;
begin
  insert into accounts (code, name, type, is_group)
  select code, name, type, true from (values
    ('1','الأصول','أصول'), ('2','الخصوم','خصوم'), ('3','حقوق الملكية','حقوق ملكية'),
    ('4','الإيرادات','إيرادات'), ('5','المصروفات','مصروفات')
  ) as t(code, name, type)
  where not exists (select 1 from accounts a where a.code = t.code or a.name = t.name);

  select id into v_1 from accounts where code = '1';
  select id into v_2 from accounts where code = '2';
  select id into v_3 from accounts where code = '3';
  select id into v_4 from accounts where code = '4';
  select id into v_5 from accounts where code = '5';

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

  -- ✅ 45: بس الحسابات اللي فعلاً بيستخدمها الكود مباشرة بالاسم
  -- (مفيش تخمين لفئات مصروفات حرة المستخدم بيكتبها بنفسه)
  insert into accounts (code, name, type, is_group, parent_id, sub_group)
  select v.code, v.name, v.type, v.is_grp, v.parent_id, v.sub_group from (values
    ('1.1.001', 'الخزينة', 'أصول', false, v_11, 'أصول متداولة'),
    ('1.1.002', 'العملاء (مدينون)', 'أصول', false, v_11, 'أصول متداولة'),
    ('1.1.003', 'العهدة', 'أصول', false, v_11, 'أصول متداولة'),
    ('1.1.004', 'المخزون', 'أصول', false, v_11, 'أصول متداولة'),
    ('1.2.001', 'الأصول الثابتة', 'أصول', false, v_12, null),
    ('1.2.002', 'مجمع إهلاك الأصول', 'أصول', false, v_12, null),
    ('2.1.001', 'الموردون', 'خصوم', false, v_21, 'خصوم متداولة'),
    ('3.001', 'رأس المال', 'حقوق ملكية', true, v_3, null),
    ('3.002', 'رصيد افتتاحي', 'حقوق ملكية', false, v_3, null),
    ('4.001', 'المبيعات', 'إيرادات', false, v_4, null),
    ('4.002', 'إيرادات أخرى', 'إيرادات', false, v_4, null),
    ('5.001', 'تكلفة البضاعة المباعة', 'مصروفات', false, v_5, null)
  ) as v(code, name, type, is_grp, parent_id, sub_group)
  where not exists (select 1 from accounts a where a.code = v.code or a.name = v.name);

  update accounts a set parent_id = v_3 where a.code in ('3.002') and a.parent_id is null;
  update accounts a set parent_id = v_4 where a.code in ('4.001','4.002') and a.parent_id is null;
  update accounts a set parent_id = v_5 where a.code = '5.001' and a.parent_id is null;
end;
$$;

grant execute on all functions in schema public to authenticated;

select rpc_seed_default_chart_of_accounts();
