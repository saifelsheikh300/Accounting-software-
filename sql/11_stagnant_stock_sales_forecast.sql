-- ============================================================
-- الدفعة 5: تحليلات ذكية — توقع مبيعات + تنبيه أصناف راكدة
-- (مبني على إحصائيات حقيقية من بياناتك، قابل لإعادة التشغيل بأمان)
-- ============================================================

-- ------------------------------------------------------------
-- أصناف راكدة: مالهاش أي حركة بيع منذ X يوم (افتراضي 60)
-- ------------------------------------------------------------
create or replace function rpc_stagnant_stock(p_days int default 60)
returns jsonb language plpgsql security definer as $$
declare v_result jsonb;
begin
  if not fn_has_permission('Reports', 'عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'productName', p.name, 'variantCode', pv.code, 'quantity', pv.quantity,
    'lastSaleDate', t.last_sale, 'daysSinceLastSale', case when t.last_sale is null then null else (current_date - t.last_sale::date) end
  ) order by coalesce(t.last_sale, '1970-01-01'::timestamptz)), '[]'::jsonb) into v_result
  from product_variants pv
  join products p on p.id = pv.product_id
  left join (
    select si.variant_id, max(s.sale_date) last_sale from sale_items si join sales s on s.id = si.sale_id
    where s.status <> 'مرتجع كلي' group by si.variant_id
  ) t on t.variant_id = pv.id
  where pv.deleted_at is null and pv.status = 'نشط' and pv.quantity > 0
    and (t.last_sale is null or t.last_sale < now() - (p_days || ' days')::interval);

  return v_result;
end;
$$;

-- ------------------------------------------------------------
-- توقع مبيعات بسيط: متوسط متحرك لآخر 4 أسابيع + اتجاه الأسبوع الجاي
-- (إحصائي حقيقي مبني على بياناتك، مش موديل AI خارجي)
-- ------------------------------------------------------------
create or replace function rpc_sales_forecast()
returns jsonb language plpgsql security definer as $$
declare
  v_weeks jsonb; v_avg numeric; v_trend numeric; v_forecast numeric; v_result jsonb;
begin
  if not fn_has_permission('Reports', 'عرض') then raise exception 'لا تملك صلاحية كافية'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('weekStart', week_start, 'total', total) order by week_start), '[]'::jsonb),
         coalesce(avg(total), 0)
  into v_weeks, v_avg
  from (
    select date_trunc('week', sale_date)::date week_start, sum(total) total
    from sales where sale_date >= now() - interval '8 weeks' and status <> 'مرتجع كلي'
    group by 1 order by 1
  ) t;

  -- اتجاه بسيط: فرق آخر أسبوعين كنسبة
  with weekly as (
    select date_trunc('week', sale_date)::date week_start, sum(total) total
    from sales where sale_date >= now() - interval '3 weeks' and status <> 'مرتجع كلي'
    group by 1 order by 1
  )
  select case when count(*) >= 2 then
    (array_agg(total order by week_start desc))[1] - (array_agg(total order by week_start desc))[2]
  else 0 end into v_trend from weekly;

  v_forecast := greatest(v_avg + coalesce(v_trend, 0), 0);

  v_result := jsonb_build_object('weeklyHistory', v_weeks, 'averageWeekly', round(v_avg,2), 'trend', round(coalesce(v_trend,0),2), 'nextWeekForecast', round(v_forecast,2));
  return v_result;
end;
$$;

grant execute on all functions in schema public to authenticated;
