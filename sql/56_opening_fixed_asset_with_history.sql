-- ============================================================
-- الدفعة 56: تسجيل أصل ثابت مباشرة من شاشة "الأصول الثابتة"
-- (مش لازم تعديه من المصروفات)، مع تحديد "استحملت قد إيه لحد
-- دلوقتي" فبيحسب مجمع الإهلاك المتراكم تلقائي بدل ما يبدأ من صفر.
--
-- ده تسجيل رصيد افتتاحي (أصل موجود بالفعل)، مش شراء جديد —
-- فمش بيتحرك أي فلوس من الخزنة، الفرق بين التكلفة الأصلية
-- ومجمع الإهلاك بيتحط في "رصيد افتتاحي".
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

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

  v_accum := round(least(p_amount, p_amount * greatest(coalesce(p_already_elapsed_months,0),0) / p_useful_life_months::numeric), 2);
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
