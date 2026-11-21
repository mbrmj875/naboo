-- Round-2 security hardening (live apply):
-- 1) Protect privileged profiles columns from self-write
-- 2) Block device self-unrevoke while other devices remain active
-- 3) Narrow restaurant anon SELECT (public menu uses service_role)

-- ── profiles privileged columns ─────────────────────────────────────────────
create or replace function public.protect_profiles_privileged_cols()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- service_role / postgres bypass (admin-web, Edge)
  if coalesce(auth.role(), '') = 'service_role' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.role is distinct from old.role then
      raise exception 'profiles.role is admin-only';
    end if;
    if new.license_system_version is distinct from old.license_system_version then
      raise exception 'profiles.license_system_version is admin-only';
    end if;
    if new.trial_started_at is distinct from old.trial_started_at then
      raise exception 'profiles.trial_started_at is admin-only';
    end if;
    if new.custom_message_title_ar is distinct from old.custom_message_title_ar
       or new.custom_message_body_ar is distinct from old.custom_message_body_ar
       or new.custom_message_active is distinct from old.custom_message_active
       or new.custom_message_updated_at is distinct from old.custom_message_updated_at then
      raise exception 'profiles custom_message_* is admin-only';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_protect_profiles_privileged on public.profiles;
create trigger trg_protect_profiles_privileged
  before update on public.profiles
  for each row
  execute function public.protect_profiles_privileged_cols();

-- ── account_devices: orphan-only unrevoke ───────────────────────────────────
create or replace function public.prevent_device_self_unrevoke()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') = 'service_role' then
    return new;
  end if;
  if tg_op = 'UPDATE'
     and lower(coalesce(old.access_status, 'active')) = 'revoked'
     and lower(coalesce(new.access_status, 'active')) is distinct from 'revoked' then
    if exists (
      select 1
      from public.account_devices d
      where d.user_id = new.user_id
        and d.device_id is distinct from new.device_id
        and lower(coalesce(d.access_status, 'active')) <> 'revoked'
    ) then
      raise exception 'cannot_unrevoke_while_other_devices_active';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_prevent_device_self_unrevoke on public.account_devices;
create trigger trg_prevent_device_self_unrevoke
  before update on public.account_devices
  for each row
  execute function public.prevent_device_self_unrevoke();

-- ── restaurant: drop cross-tenant anon SELECT (SSR uses service_role) ────────
drop policy if exists restaurant_menu_images_public_select
  on public.restaurant_menu_item_images;
drop policy if exists restaurant_menu_theme_public_select
  on public.restaurant_menu_theme;

-- Keep slug lookup for Edge resolveTenantUuid when called with anon — still
-- exposes directory of slugs. Prefer authenticated/service; drop open SELECT.
drop policy if exists restaurant_tenant_slugs_public_select
  on public.restaurant_tenant_slugs;

-- Authenticated merchants may read their own slug rows (tenant_uuid = auth.uid()).
drop policy if exists restaurant_tenant_slugs_own_select
  on public.restaurant_tenant_slugs;
create policy restaurant_tenant_slugs_own_select
  on public.restaurant_tenant_slugs
  for select
  to authenticated
  using (tenant_uuid = auth.uid()::text);
