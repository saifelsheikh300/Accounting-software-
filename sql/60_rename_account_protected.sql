-- ============================================================
-- الدفعة 60: تعديل اسم حساب من شجرة الحسابات — بحماية إن الأسماء
-- الأساسية اللي البرنامج بيعتمد عليها في كل مكان (زي "الخزينة"،
-- "العملاء (مدينون)"، "المبيعات"، "رصيد افتتاحي"...) متتغيرش،
-- عشان لو اتغيرت البرنامج هيفضل يعمل حساب جديد بالاسم القديم في
-- كل عملية بيع/مصروف/تحصيل جاية، وهيحصل ازدواج.
--
-- الحسابات اللي مش من دول (زي فئات مصروفات معينة، أو شركاء)
-- ممكن تتغير عادي.
-- (قابلة لإعادة التشغيل بأمان)
-- ============================================================

create or replace function rpc_rename_account(p_account_id uuid, p_new_name text)
returns void language plpgsql security definer as $$
declare v_old_name text; v_protected text[] := array[
  'الخزينة','العملاء (مدينون)','الموردون','رصيد افتتاحي','المبيعات','تكلفة البضاعة المباعة',
  'المرتبات','أجور مستحقة','سلف الموظفين','العهدة','الأصول الثابتة','مجمع إهلاك الأصول',
  'دائنون آخرون','رأس المال','المخزون','إيرادات أخرى'
];
begin
  if not fn_has_permission('Reports', 'تعديل') then raise exception 'لا تملك صلاحية كافية'; end if;
  if p_new_name is null or trim(p_new_name) = '' then raise exception 'الاسم الجديد مطلوب'; end if;

  select name into v_old_name from accounts where id = p_account_id;
  if v_old_name is null then raise exception 'الحساب غير موجود'; end if;

  if v_old_name = any(v_protected) then
    raise exception 'الحساب ده اسمه أساسي والبرنامج بيعتمد عليه في كذا مكان (مبيعات، مصروفات، تحصيل...) — تغييره هيبوّظ عمليات تانية. لو محتاجة تعديل حقيقي قوليلي وأشوفه بنفسي';
  end if;

  if exists (select 1 from accounts where name = p_new_name and id <> p_account_id) then
    raise exception 'فيه حساب تاني بنفس الاسم ده بالفعل';
  end if;

  update accounts set name = p_new_name where id = p_account_id;
  update journal_entries set debit_account = p_new_name where debit_account = v_old_name;
  update journal_entries set credit_account = p_new_name where credit_account = v_old_name;

  perform fn_log_operation('RENAME_ACCOUNT', jsonb_build_object('old', v_old_name, 'new', p_new_name));
end;
$$;

grant execute on all functions in schema public to authenticated;
