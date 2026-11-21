-- سحب JWT التفعيل للحساب الحالي (بدون لصق يدوي) + ترتيب حد الأجهزة يفضّل مدى الحياة.
-- نفّذ في Supabase SQL Editor.

create or replace function public.app_user_max_devices()
returns int
language sql
stable
security invoker
as $$
  select
    coalesce(
      (
        select l.max_devices
        from public.licenses l
        where l.assigned_user_id = auth.uid()
          and lower(coalesce(l.status, '')) in ('active', 'trial')
        order by
          case lower(coalesce(l.plan, ''))
            when 'lifetime' then 0
            when 'annual' then 1
            when 'monthly' then 2
            else 9
          end,
          coalesce(l.max_devices, 0) desc,
          case lower(coalesce(l.status, ''))
            when 'active' then 0
            when 'trial' then 1
            else 9
          end,
          l.id desc
        limit 1
      ),
      2
    )::int;
$$;

create or replace function public.app_my_license_jwt()
returns table (
  license_id bigint,
  jwt text,
  max_devices int,
  plan text
)
language sql
stable
security invoker
as $$
  select
    l.id::bigint as license_id,
    nullif(trim(l.license_jwt), '') as jwt,
    coalesce(l.max_devices, 0)::int as max_devices,
    coalesce(l.plan, '')::text as plan
  from public.licenses l
  where l.assigned_user_id = auth.uid()
    and lower(coalesce(l.status, '')) in ('active', 'trial')
    and nullif(trim(l.license_jwt), '') is not null
  order by
    case lower(coalesce(l.plan, ''))
      when 'lifetime' then 0
      when 'annual' then 1
      when 'monthly' then 2
      else 9
    end,
    coalesce(l.max_devices, 0) desc,
    case lower(coalesce(l.status, ''))
      when 'active' then 0
      when 'trial' then 1
      else 9
    end,
    l.id desc
  limit 1;
$$;

revoke all on function public.app_my_license_jwt() from public;
grant execute on function public.app_my_license_jwt() to authenticated;

revoke all on function public.app_user_max_devices() from public;
grant execute on function public.app_user_max_devices() to authenticated;
grant execute on function public.app_user_max_devices() to service_role;
