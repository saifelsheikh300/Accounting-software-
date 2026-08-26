-- ============================================================
-- الدفعة 68: تقريب الإهلاك الشهري لأقرب رقم صحيح (مش كسور)
--
-- كان الإهلاك الشهري بيتحسب بدقة قرشين (round(...,2))، يعني أصل
-- بتكلفة 1000 جنيه وعمره 36 شهر كان بيظهر إهلاكه الشهري 27.78
-- جنيه. المستخدم عايز رقم صحيح واضح (28 مثلاً) حتى لو مش دقيق
-- 100% لآخر قرش — التقريب هنا مقصود ومقبول محاسبيًا لأصول صغيرة
-- القيمة، والفرق البسيط (كسور القرش) بيتجمع في آخر شهر ضمن
-- "كل المتبقي" عشان مجمع الإهلاك يوصل بالظبط لتكلفة الأصل الأصلية
-- في نهاية عمره الافتراضي (مفيش فلوس بتضيع أو تتزود).
-- ============================================================

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
      v_monthly := least(round(v_asset.amount / greatest(v_asset.useful_life_months,1), 0), v_asset.amount - v_asset.accumulated_depreciation);
    end if;

    if v_monthly > 0 then
      update fixed_assets set accumulated_depreciation = accumulated_depreciation + v_monthly where id = v_asset.id;
      perform fn_journal_entry('المصروفات: إهلاك', 'مجمع إهلاك الأصول', v_monthly, v_asset.id::text, 'إهلاك — ' || coalesce(v_asset.description,'') || ' — ' || v_month);
    end if;
  end loop;

  perform fn_log_operation('RUN_MONTHLY_DEPRECIATION', jsonb_build_object('month', v_month));
end;
$$;

create or replace function rpc_add_opening_fixed_asset(
  p_description text, p_amount numeric, p_useful_life_months int,
  p_already_elapsed_months int default 0, p_depreciation_method text default 'شهري'
)
returns uuid language plpgsql security definer as $$
declare v_id uuid; v_accum numeric; v_net numeric;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_description is null or trim(p_description) = '' then raise exception 'اسم الأصل مطلوب'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'التكلفة مطلوبة'; end if;
  if p_useful_life_months is null or p_useful_life_months <= 0 then raise exception 'العمر الافتراضي مطلوب'; end if;

  v_accum := round(least(p_amount, p_amount * greatest(coalesce(p_already_elapsed_months,0),0) / p_useful_life_months::numeric), 0);
  v_net := p_amount - v_accum;

  insert into fixed_assets (description, amount, acquired_at, useful_life_months, accumulated_depreciation, depreciation_method)
  values (p_description, p_amount, now() - (coalesce(p_already_elapsed_months,0) || ' months')::interval, p_useful_life_months, v_accum, coalesce(p_depreciation_method,'شهري'))
  returning id into v_id;

  -- الأصل بالتكلفة الكاملة، مقابله رصيد افتتاحي بصافي القيمة + مجمع الإهلاك اللي فات
  perform fn_journal_entry('الأصول الثابتة', 'رصيد افتتاحي', v_net, 'OB-FA-' || v_id::text, 'رصيد افتتاحي أصل ثابت — ' || p_description);
  if v_accum > 0 then
    perform fn_journal_entry('رصيد افتتاحي', 'مجمع إهلاك الأصول', v_accum, 'OB-FA-' || v_id::text, 'مجمع إهلاك سابق — ' || p_description);
  end if;

  perform fn_log_operation('ADD_OPENING_FIXED_ASSET', jsonb_build_object('description', p_description, 'amount', p_amount, 'accumulated', v_accum));
  return v_id;
end;
$$;

grant execute on all functions in schema public to authenticated;
