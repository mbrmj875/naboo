-- يمنع ربط Google OAuth بحساب auth.users مختلف لنفس البريد (multi-tenant safety).
-- يُستدعى من Flutter بعد OAuth وقبل أي _bindAccountDataScope / upsert محلي.

create or replace function public.assert_identity_link_allowed(
  p_email        text,
  p_supabase_uid uuid
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_bound uuid;
begin
  if auth.uid() is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;

  if p_supabase_uid is null or p_supabase_uid is distinct from auth.uid() then
    raise exception 'UID_MISMATCH' using errcode = 'P0001';
  end if;

  if p_email is null or length(trim(p_email)) = 0 then
    raise exception 'INVALID_EMAIL' using errcode = 'P0001';
  end if;

  select id into v_bound
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if v_bound is not null and v_bound <> p_supabase_uid then
    raise exception 'EMAIL_BOUND_TO_OTHER_ACCOUNT' using errcode = 'P0001';
  end if;
end;
$$;

revoke all on function public.assert_identity_link_allowed(text, uuid) from public;
grant execute on function public.assert_identity_link_allowed(text, uuid) to authenticated;

comment on function public.assert_identity_link_allowed(text, uuid) is
  'Google/identity link guard: rejects when email is already bound to a different auth.users id. Caller must match auth.uid().';
