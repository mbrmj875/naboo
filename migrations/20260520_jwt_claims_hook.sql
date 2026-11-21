create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role      text;
  v_tenant_id text;
  v_user_id   uuid;
begin
  v_user_id := (event ->> 'userId')::uuid;

  select role into v_role
  from public.profiles
  where id = v_user_id;

  v_tenant_id := coalesce(
    nullif(event->'claims'->>'tenant_id', ''),
    v_user_id::text
  );

  v_role := coalesce(nullif(v_role, ''), 'staff');

  -- لا تكتب claim باسم role: PostgREST يستخدمه كدور Postgres (authenticated/anon).
  -- دور التطبيق (owner/admin/staff) يذهب في app_role فقط.
  return jsonb_set(
    event,
    '{claims}',
    coalesce(event->'claims', '{}'::jsonb)
      || jsonb_build_object(
          'app_role',  v_role,
          'tenant_id', v_tenant_id
         )
  );
end;
$$;

grant execute
  on function public.custom_access_token_hook
  to supabase_auth_admin;
