-- إصلاح: الإصدار السابق كان يحذف claim "role" بالكامل
-- لكن Supabase يتطلب وجوده (عادةً "authenticated").
-- الحل: نعيد تعيينه إلى "authenticated" بدلاً من حذفه.

create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_app_role  text;
  v_tenant_id text;
  v_user_id   uuid;
  v_claims    jsonb;
begin
  v_user_id := (event ->>'userId')::uuid;

  select role into v_app_role
  from public.profiles
  where id = v_user_id;

  v_tenant_id := coalesce(
    nullif(event->'claims'->>'tenant_id', ''),
    v_user_id::text
  );

  v_app_role := coalesce(nullif(v_app_role, ''), 'staff');

  v_claims := coalesce(event->'claims', '{}'::jsonb)
    || jsonb_build_object(
         'app_role',  v_app_role,
         'tenant_id', v_tenant_id
       );

  -- تأكد أن role يبقى "authenticated" (مطلوب من Supabase).
  -- لا تحذفه! فقط أعده للقيمة الصحيحة إذا كان قد تغيّر.
  v_claims := jsonb_set(v_claims, '{role}', '"authenticated"');

  return jsonb_set(event, '{claims}', v_claims);
end;
$$;

grant execute
  on function public.custom_access_token_hook(jsonb)
  to supabase_auth_admin;
