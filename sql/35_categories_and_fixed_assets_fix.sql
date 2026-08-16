-- ============================================================
-- الدفعة 35: تحويل نوع الفئة + إصلاح جوهري للأصول الثابتة
--
-- 1) تحويل فئة رئيسية غلط لفئة فرعية تحت فئة رئيسية تانية — من غير
--    ما تتأثر المنتجات المرتبطة بيها (نفس الكود فاضل زي ما هو)
--
-- 2) الأصول الثابتة: كان تسجيل مصروف كـ"أصل ثابت" بيسجله كمصروف
--    عادي بس (بيأثر على قائمة الدخل فورًا) ومكانش بيضيف صف في جدول
--    fixed_assets خالص — يعني شاشة "الأصول الثابتة" كانت فاضية
--    دايمًا. دلوقتي: أصل ثابت بيترسمل صح (Dr الأصول الثابتة /
--    Cr الخزينة) مش بيتحمّل كمصروف فوري، وبيتسجل فعليًا في جدول
--    الأصول، وظاهر في شجرة الحسابات والميزانية العمومية. وضفت
--    خيار طريقة الإهلاك: شهري (زي ما كان) أو دفعة واحدة في نهاية
--    العمر الافتراضي.
-- (قابل لإعادة التشغيل بأمان بالكامل)
-- ============================================================

-- ------------------------------------------------------------
-- 1) تحويل فئة رئيسية إلى فرعية
-- ------------------------------------------------------------
create or replace function rpc_convert_category_to_sub(p_code text, p_new_parent_code text)
returns void language plpgsql security definer as $$
declare v_has_children int; v_type text;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  select type into v_type from product_tree where code = p_code;
  if v_type is null then raise exception 'الفئة غير موجودة'; end if;
  if v_type <> 'رئيسية' then raise exception 'الفئة دي فرعية أصلاً'; end if;
  if p_code = p_new_parent_code then raise exception 'متقدريش تخليها فرعية تحت نفسها'; end if;

  select count(*) into v_has_children from product_tree where parent_id = (select id from product_tree where code = p_code);
  if v_has_children > 0 then
    raise exception 'الفئة دي ليها % فئة فرعية تحتها — انقليهم لفئة تانية الأول قبل التحويل', v_has_children;
  end if;

  update product_tree set type = 'فرعية', parent_id = (select id from product_tree where code = p_new_parent_code)
  where code = p_code;

  perform fn_log_operation('CONVERT_CATEGORY', jsonb_build_object('code', p_code, 'new_parent', p_new_parent_code));
end;
$$;

-- ------------------------------------------------------------
-- 2) حسابات الأصول الثابتة ومجمع الإهلاك (لو مش موجودين)
-- ------------------------------------------------------------
insert into accounts (code, name, type, is_group)
select 'AS-FIX', 'الأصول الثابتة', 'أصول', false
where not exists (select 1 from accounts where name = 'الأصول الثابتة');

insert into accounts (code, name, type, is_group)
select 'AS-DEP', 'مجمع إهلاك الأصول', 'أصول', false
where not exists (select 1 from accounts where name = 'مجمع إهلاك الأصول');

-- ------------------------------------------------------------
-- 3) طريقة الإهلاك على جدول الأصول
-- ------------------------------------------------------------
alter table fixed_assets add column if not exists depreciation_method text not null default 'شهري' check (depreciation_method in ('شهري', 'دفعة نهائية'));
alter table fixed_assets add column if not exists treasury_account_id uuid references treasury_accounts(id);

-- ------------------------------------------------------------
-- 4) إعادة بناء rpc_add_expense — أصل ثابت بيترسمل، مش بيتحمّل كمصروف
-- ------------------------------------------------------------
do $$
declare v_sig record;
begin
  for v_sig in select oid::regprocedure as sig from pg_proc where proname = 'rpc_add_expense'
  loop
    execute 'drop function if exists ' || v_sig.sig || ' cascade';
  end loop;
end $$;

create or replace function rpc_add_expense(
  p_main_category text, p_amount numeric, p_sub_category text default '', p_description text default '',
  p_is_recurring boolean default false, p_recurrence_days int default null, p_is_fixed_asset boolean default false,
  p_payment_method text default 'كاش', p_employee_id uuid default null, p_bonus numeric default null,
  p_expense_date timestamptz default now(), p_treasury_account_id uuid default null,
  p_useful_life_months int default 36, p_depreciation_method text default 'شهري'
)
returns uuid language plpgsql security definer as $$
declare v_id uuid;
begin
  perform fn_check_period_open(p_expense_date);
  if not fn_has_permission('Expenses', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'المبلغ لازم يكون أكبر من صفر'; end if;
  if p_main_category is null or trim(p_main_category) = '' then raise exception 'الفئة الرئيسية مطلوبة'; end if;

  if p_is_fixed_asset then
    -- أصل ثابت: بيترسمل، مش بيتحمّل كمصروف على قائمة الدخل فورًا
    insert into fixed_assets (description, amount, acquired_at, useful_life_months, depreciation_method, treasury_account_id)
    values (coalesce(nullif(p_description,''), p_main_category), p_amount, p_expense_date, greatest(coalesce(p_useful_life_months,36),1), coalesce(p_depreciation_method,'شهري'), p_treasury_account_id)
    returning id into v_id;

    if p_payment_method <> 'آجل' then
      perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, coalesce(nullif(p_description,''), p_main_category));
    end if;

    perform fn_journal_entry('الأصول الثابتة', case when p_payment_method = 'آجل' then 'دائنون آخرون' else 'الخزينة' end,
      p_amount, p_main_category, 'شراء أصل ثابت — ' || coalesce(nullif(p_description,''), p_main_category));

    perform fn_log_operation('ADD_FIXED_ASSET', jsonb_build_object('description', p_description, 'amount', p_amount));
    return v_id;
  end if;

  insert into expenses (expense_date, main_category, sub_category, description, amount, is_recurring, recurrence_days, is_fixed_asset, payment_method, employee_id, bonus, treasury_account_id, created_by)
  values (p_expense_date, p_main_category, coalesce(p_sub_category,''), coalesce(p_description,''), p_amount, p_is_recurring, p_recurrence_days, false, p_payment_method, p_employee_id, p_bonus, p_treasury_account_id, auth.uid())
  returning id into v_id;

  if p_payment_method <> 'آجل' then
    perform fn_move_treasury('خارج', p_amount, p_treasury_account_id, coalesce(nullif(p_description,''), p_main_category));
  end if;

  perform fn_journal_entry('المصروفات: ' || p_main_category, case when p_payment_method = 'آجل' then 'دائنون آخرون' else 'الخزينة' end,
    p_amount, p_main_category, coalesce(nullif(p_description,''), p_main_category));

  perform fn_log_operation('ADD_EXPENSE', jsonb_build_object('category', p_main_category, 'amount', p_amount));
  return v_id;
end;
$$;

-- ------------------------------------------------------------
-- 5) تحديث الإهلاك الشهري عشان يحترم طريقة الإهلاك المختارة
-- ------------------------------------------------------------
create or replace function rpc_run_monthly_depreciation()
returns void language plpgsql security definer as $$
declare v_asset record; v_monthly numeric; v_month text := to_char(now(),'YYYY-MM'); v_age_months int;
begin
  if not fn_has_permission('Reports','تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  for v_asset in select * from fixed_assets where accumulated_depreciation < amount loop
    if v_asset.depreciation_method = 'دفعة نهائية' then
      v_age_months := extract(year from age(now(), v_asset.acquired_at)) * 12 + extract(month from age(now(), v_asset.acquired_at));
      if v_age_months >= v_asset.useful_life_months then
        v_monthly := v_asset.amount - v_asset.accumulated_depreciation; -- كل المتبقي دفعة واحدة
      else
        v_monthly := 0;
      end if;
    else
      v_monthly := least(round(v_asset.amount / greatest(v_asset.useful_life_months,1), 2), v_asset.amount - v_asset.accumulated_depreciation);
    end if;

    if v_monthly > 0 then
      update fixed_assets set accumulated_depreciation = accumulated_depreciation + v_monthly where id = v_asset.id;
      perform fn_journal_entry('المصروفات: إهلاك', 'مجمع إهلاك الأصول', v_monthly, v_asset.id::text, 'إهلاك — ' || coalesce(v_asset.description,'') || ' — ' || v_month);
    end if;
  end loop;

  perform fn_log_operation('RUN_MONTHLY_DEPRECIATION', jsonb_build_object('month', v_month));
end;
$$;

grant execute on all functions in schema public to authenticated;
