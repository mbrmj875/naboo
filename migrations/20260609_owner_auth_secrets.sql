-- مرحلة 5 — القرار 1: PIN المالك cross-device (hash+salt على السحابة، بدون plaintext).
-- يُستدعى من Flutter بعد completeGoogleOwnerProfile / finalizeOwnerPin
-- ويُقرأ على الجهاز الثاني بعد Google OAuth.

create table if not exists public.owner_auth_secrets (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  phone      text not null default '',
  pin_hash   text not null default '',
  pin_salt   text not null default '',
  updated_at timestamptz not null default now(),
  constraint owner_auth_secrets_phone_len check (char_length(trim(phone)) <= 32),
  constraint owner_auth_secrets_hash_len check (char_length(pin_hash) <= 256),
  constraint owner_auth_secrets_salt_len check (char_length(pin_salt) <= 256)
);

comment on table public.owner_auth_secrets is
  'Owner local PIN material for cross-device restore: SHA-256 hash + salt only — never plaintext PIN.';

alter table public.owner_auth_secrets enable row level security;

drop policy if exists owner_auth_secrets_select on public.owner_auth_secrets;
create policy owner_auth_secrets_select on public.owner_auth_secrets
  for select
  using (user_id = auth.uid());

drop policy if exists owner_auth_secrets_insert on public.owner_auth_secrets;
create policy owner_auth_secrets_insert on public.owner_auth_secrets
  for insert
  with check (user_id = auth.uid());

drop policy if exists owner_auth_secrets_update on public.owner_auth_secrets;
create policy owner_auth_secrets_update on public.owner_auth_secrets
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists owner_auth_secrets_delete on public.owner_auth_secrets;
create policy owner_auth_secrets_delete on public.owner_auth_secrets
  for delete
  using (user_id = auth.uid());

create or replace function public.app_upsert_owner_auth_secret(
  p_phone    text,
  p_pin_hash text,
  p_pin_salt text
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;

  if p_phone is null
     or length(trim(p_phone)) = 0
     or length(trim(p_phone)) > 32 then
    raise exception 'INVALID_PHONE' using errcode = 'P0001';
  end if;

  if p_pin_hash is null
     or length(trim(p_pin_hash)) = 0
     or p_pin_salt is null
     or length(trim(p_pin_salt)) = 0 then
    raise exception 'INVALID_PIN_MATERIAL' using errcode = 'P0001';
  end if;

  insert into public.owner_auth_secrets as s (
    user_id,
    phone,
    pin_hash,
    pin_salt,
    updated_at
  )
  values (
    v_uid,
    trim(p_phone),
    trim(p_pin_hash),
    trim(p_pin_salt),
    now()
  )
  on conflict (user_id) do update
  set phone      = excluded.phone,
      pin_hash   = excluded.pin_hash,
      pin_salt   = excluded.pin_salt,
      updated_at = now();
end;
$$;

revoke all on function public.app_upsert_owner_auth_secret(text, text, text) from public;
grant execute on function public.app_upsert_owner_auth_secret(text, text, text) to authenticated;

comment on function public.app_upsert_owner_auth_secret(text, text, text) is
  'Stores owner phone + PIN hash/salt for cross-device restore. Caller must be auth.uid().';

create or replace function public.app_get_owner_auth_secret()
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_row public.owner_auth_secrets%rowtype;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED' using errcode = 'P0001';
  end if;

  select * into v_row
  from public.owner_auth_secrets
  where user_id = v_uid;

  if not found then
    return null;
  end if;

  return jsonb_build_object(
    'phone',     v_row.phone,
    'pin_hash',  v_row.pin_hash,
    'pin_salt',  v_row.pin_salt,
    'updated_at', v_row.updated_at
  );
end;
$$;

revoke all on function public.app_get_owner_auth_secret() from public;
grant execute on function public.app_get_owner_auth_secret() to authenticated;

comment on function public.app_get_owner_auth_secret() is
  'Returns owner phone + PIN hash/salt for the signed-in user, or null if unset.';
