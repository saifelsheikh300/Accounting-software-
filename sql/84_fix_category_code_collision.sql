-- ============================================================
-- الدفعة 84: إصلاح تصادم أكواد الفئات (رئيسية/فرعية)
--
-- المشكلة: كود الفئة الفرعية بيتكوّن من (كود الفئة الرئيسية + رقم)،
-- وكل الأكواد (رئيسية وفرعية مع بعض) بتشترك في نفس عمود code اللي
-- لازم يكون فريد. فمثلاً فئة فرعية كود "12" (تحت فئة رئيسية "1")
-- ممكن تتصادم مع فئة رئيسية تانية كودها "12" لو وصلتي لعدد فئات
-- رئيسية كبير — وده اللي سبب خطأ "duplicate key" اللي ظهرلك.
--
-- الحل: قبل ما نحفظ أي كود جديد (رئيسي أو فرعي)، بنتأكد إنه مش
-- مستخدم فعلاً في أي مكان، ولو كان مستخدم بنجرب اللي بعده لحد ما
-- نلاقي كود فاضي فعلاً.
-- ============================================================

create or replace function rpc_create_category(p_name text, p_type text, p_parent_code text default null)
returns table(code text, name text) language plpgsql security definer as $$
declare
  v_code text; v_max int; v_parent_id uuid; v_attempt int := 0;
begin
  if not fn_has_permission('Inventory', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;

  if p_type = 'رئيسية' then
    select coalesce(max(pt.code::int), 0) into v_max from product_tree pt where pt.type = 'رئيسية';
    loop
      v_attempt := v_attempt + 1;
      v_code := (v_max + v_attempt)::text;
      exit when not exists (select 1 from product_tree where product_tree.code = v_code);
      if v_attempt > 500 then raise exception 'تعذر توليد كود فريد للفئة'; end if;
    end loop;
    insert into product_tree (code, name, type) values (v_code, p_name, 'رئيسية');
  else
    select id into v_parent_id from product_tree where product_tree.code = p_parent_code;
    if v_parent_id is null then raise exception 'الفئة الرئيسية غير موجودة'; end if;

    select coalesce(max(substring(pt.code from length(p_parent_code)+1)::int), 0) into v_max
    from product_tree pt where pt.parent_id = v_parent_id and pt.type = 'فرعية';
    loop
      v_attempt := v_attempt + 1;
      v_code := p_parent_code || (v_max + v_attempt)::text;
      exit when not exists (select 1 from product_tree where product_tree.code = v_code);
      if v_attempt > 500 then raise exception 'تعذر توليد كود فريد للفئة'; end if;
    end loop;
    insert into product_tree (code, name, type, parent_id) values (v_code, p_name, 'فرعية', v_parent_id);
  end if;

  perform fn_log_operation('CREATE_CATEGORY', jsonb_build_object('code', v_code, 'name', p_name));
  return query select v_code, p_name;
end;
$$;

grant execute on all functions in schema public to authenticated;
