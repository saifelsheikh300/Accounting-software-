-- ============================================================
-- الدفعة 69: منع ترحيل الإهلاك ونسبة إدارة الشركاء مرتين في نفس الشهر
--
-- المشكلتين اللي اتكشفتا في الفحص الشامل:
--
-- 1) rpc_run_monthly_depreciation: لو حد دوس على زرار "تشغيل
--    إهلاك الشهر الحالي" مرتين غلط في نفس الشهر، كانت هتترحّل
--    قيمة الإهلاك مرتين على كل الأصول اللي لسه ماكملتش عمرها
--    الافتراضي — يعني مصروف إهلاك مضاعف في الدفاتر غلط.
--    الحل: عمود last_depreciated_month على كل أصل، ومينفعش
--    يترحّل تاني لنفس الشهر.
--
-- 2) rpc_run_monthly_admin_fee: نفس المشكلة بالظبط (تكرار الترحيل)
--    + مكنش فيها أي فحص صلاحيات خالص، يعني أي مستخدم مسجل دخول
--    (حتى لو صلاحياته محدودة في الواجهة) يقدر يستدعيها مباشرة
--    ويرحّل مصروف نسبة إدارة وهمي.
-- ============================================================

alter table fixed_assets add column if not exists last_depreciated_month text;

create or replace function rpc_run_monthly_depreciation()
returns void language plpgsql security definer as $$
declare v_asset record; v_monthly numeric; v_month text := to_char(now(),'YYYY-MM'); v_age_months int;
begin
  if not fn_has_permission('Reports','تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  for v_asset in select * from fixed_assets
    where accumulated_depreciation < amount and coalesce(last_depreciated_month, '') <> v_month
  loop
    if v_asset.depreciation_method = 'دفعة نهائية' then
      v_age_months := extract(year from age(now(), v_asset.acquired_at)) * 12 + extract(month from age(now(), v_asset.acquired_at));
      if v_age_months >= v_asset.useful_life_months then
        v_monthly := v_asset.amount - v_asset.accumulated_depreciation;
      else
        v_monthly := 0;
      end if;
    else
      v_monthly := least(round(v_asset.amount / greatest(v_asset.useful_life_months,1), 0), v_asset.amount - v_asset.accumulated_depreciation);
    end if;

    if v_monthly > 0 then
      update fixed_assets set accumulated_depreciation = accumulated_depreciation + v_monthly, last_depreciated_month = v_month where id = v_asset.id;
      perform fn_journal_entry('المصروفات: إهلاك', 'مجمع إهلاك الأصول', v_monthly, v_asset.id::text, 'إهلاك — ' || coalesce(v_asset.description,'') || ' — ' || v_month);
    else
      update fixed_assets set last_depreciated_month = v_month where id = v_asset.id;
    end if;
  end loop;

  perform fn_log_operation('RUN_MONTHLY_DEPRECIATION', jsonb_build_object('month', v_month));
end;
$$;

create or replace function rpc_run_monthly_admin_fee()
returns void language plpgsql security definer as $$
declare
  v_partner record; v_month text := to_char(now(), 'YYYY-MM'); v_fee numeric; v_sales_total numeric; v_admin_enabled text;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  select value into v_admin_enabled from settings where key = 'adminFeeEnabled';
  if v_admin_enabled is distinct from 'true' then return; end if;

  select coalesce(sum(total), 0) into v_sales_total from sales where to_char(sale_date, 'YYYY-MM') = v_month and status <> 'مرتجع كلي';

  for v_partner in select * from partners where admin_rate is not null and admin_rate > 0 loop
    -- ✅ لو نسبة الإدارة لشهر ده اترحّلت للشريك ده قبل كده، متترحلش تاني
    if exists (select 1 from admin_rights where partner_id = v_partner.id and month_label = v_month) then
      continue;
    end if;

    v_fee := case when v_partner.admin_rate_type = 'نسبة %' then v_sales_total * (v_partner.admin_rate / 100) else v_partner.admin_rate end;
    if v_fee <= 0 then continue; end if;

    insert into expenses (main_category, sub_category, description, amount, is_recurring, recurrence_days, payment_method)
    values ('إدارية', 'نسبة إدارة شريك: ' || v_partner.name, 'نسبة إدارة شهرية — ' || v_month, v_fee, true, 30, 'آجل');

    perform fn_journal_entry('المصروفات: نسبة إدارة', 'مستحقات إدارة — ' || v_partner.name, v_fee, v_partner.name, 'نسبة إدارة شهرية — ' || v_month);

    insert into admin_rights (partner_id, month_label, earned, available)
    values (v_partner.id, v_month, v_fee, v_fee);
  end loop;

  perform fn_log_operation('RUN_MONTHLY_ADMIN_FEE', jsonb_build_object('month', v_month));
end;
$$;

grant execute on all functions in schema public to authenticated;
