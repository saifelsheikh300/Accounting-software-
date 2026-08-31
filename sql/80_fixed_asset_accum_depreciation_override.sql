-- ============================================================
-- الدفعة 80: دعم إدخال مجمع الإهلاك بالظبط (لو معروف) بدل حسابه
-- تقريبيًا من عدد الشهور المنقضية — عشان أرقام زي 5,800 (مش قسمة
-- صحيحة على شهور) تتسجل بالظبط زي ما هي.
-- ============================================================

create or replace function rpc_add_opening_fixed_asset(
  p_description text, p_amount numeric, p_useful_life_months int,
  p_already_elapsed_months int default 0, p_depreciation_method text default 'شهري',
  p_accumulated_depreciation_override numeric default null
)
returns uuid language plpgsql security definer as $$
declare v_id uuid; v_accum numeric; v_net numeric;
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_description is null or trim(p_description) = '' then raise exception 'اسم الأصل مطلوب'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'التكلفة مطلوبة'; end if;
  if p_useful_life_months is null or p_useful_life_months <= 0 then raise exception 'العمر الافتراضي مطلوب'; end if;

  if p_accumulated_depreciation_override is not null then
    v_accum := least(p_amount, greatest(p_accumulated_depreciation_override, 0));
  else
    v_accum := round(least(p_amount, p_amount * greatest(coalesce(p_already_elapsed_months,0),0) / p_useful_life_months::numeric), 0);
  end if;
  v_net := p_amount - v_accum;

  insert into fixed_assets (description, amount, acquired_at, useful_life_months, accumulated_depreciation, depreciation_method)
  values (p_description, p_amount, now() - (coalesce(p_already_elapsed_months,0) || ' months')::interval, p_useful_life_months, v_accum, coalesce(p_depreciation_method,'شهري'))
  returning id into v_id;

  perform fn_journal_entry('الأصول الثابتة', 'رصيد افتتاحي', v_net, 'OB-FA-' || v_id::text, 'رصيد افتتاحي أصل ثابت — ' || p_description);
  if v_accum > 0 then
    perform fn_journal_entry('رصيد افتتاحي', 'مجمع إهلاك الأصول', v_accum, 'OB-FA-' || v_id::text, 'مجمع إهلاك سابق — ' || p_description);
  end if;

  perform fn_log_operation('ADD_OPENING_FIXED_ASSET', jsonb_build_object('description', p_description, 'amount', p_amount, 'accumulated', v_accum));
  return v_id;
end;
$$;

grant execute on all functions in schema public to authenticated;
