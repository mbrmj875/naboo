-- ⚠️ ملغي: هذا الإصلاح كان يحذف claim "role" مما يكسر Supabase.
-- استخدم 20260529_jwt_fix_keep_role_claim.sql بدلاً منه.
-- إصلاح: claim JWT باسم role كان يستبدل authenticated بـ staff/owner
-- فيسبب: role "staff" does not exist عند rpc_process_sync_queue.
-- بعد التطبيق: سجّل خروج ثم دخول مرة أخرى لإصدار JWT جديد.

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
  v_user_id := (event ->> 'userId')::uuid;

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

  -- أزل claim خاطئ إن وُجد من إصدار سابق للهوك.
  v_claims := v_claims - 'role';

  return jsonb_set(event, '{claims}', v_claims);
end;
$$;

grant execute
  on function public.custom_access_token_hook(jsonb)
  to supabase_auth_admin;
