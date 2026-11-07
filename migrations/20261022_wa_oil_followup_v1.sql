-- تذكير واتساب بعد غيار الزيت — قواعد + وظائف + جدولة

create table if not exists public.wa_oil_followup_rules (
  tenant_user_id uuid primary key references auth.users (id) on delete cascade,
  enabled boolean not null default false,
  delay_value integer not null default 3 check (delay_value > 0),
  delay_unit text not null default 'month'
    check (delay_unit in ('hour', 'day', 'week', 'month', 'year')),
  quiet_hours boolean not null default true,
  body_template text not null default '',
  updated_at timestamptz not null default now()
);

create table if not exists public.wa_oil_followup_jobs (
  id uuid primary key default gen_random_uuid(),
  tenant_user_id uuid not null references auth.users (id) on delete cascade,
  order_ref text not null,
  customer_phone text not null,
  due_at timestamptz not null,
  status text not null default 'queued'
    check (status in (
      'queued', 'sending', 'sent', 'skipped_no_wallet',
      'skipped_no_template', 'cancelled', 'failed'
    )),
  payload jsonb not null default '{}'::jsonb,
  idempotency_key text not null,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists wa_oil_followup_jobs_active_uidx
  on public.wa_oil_followup_jobs (tenant_user_id, order_ref)
  where status in ('queued', 'sending');

create index if not exists wa_oil_followup_jobs_due_idx
  on public.wa_oil_followup_jobs (due_at)
  where status = 'queued';

create index if not exists wa_oil_followup_jobs_tenant_idx
  on public.wa_oil_followup_jobs (tenant_user_id, due_at desc);

alter table public.wa_oil_followup_rules enable row level security;
alter table public.wa_oil_followup_jobs enable row level security;

drop policy if exists wa_followup_rules_select_own on public.wa_oil_followup_rules;
create policy wa_followup_rules_select_own on public.wa_oil_followup_rules
  for select to authenticated using (tenant_user_id = auth.uid());

drop policy if exists wa_followup_rules_upsert_own on public.wa_oil_followup_rules;
create policy wa_followup_rules_upsert_own on public.wa_oil_followup_rules
  for all to authenticated using (tenant_user_id = auth.uid())
  with check (tenant_user_id = auth.uid());

drop policy if exists wa_followup_jobs_select_own on public.wa_oil_followup_jobs;
create policy wa_followup_jobs_select_own on public.wa_oil_followup_jobs
  for select to authenticated using (tenant_user_id = auth.uid());

-- ——— حساب الموعد (Asia/Baghdad + صمت ليلي اختياري) ———
create or replace function public.wa_followup_compute_due_at(
  p_saved_at timestamptz,
  p_delay_value integer,
  p_delay_unit text,
  p_quiet_hours boolean
)
returns timestamptz
language plpgsql
immutable
as $$
declare
  v_due timestamptz;
  v_local timestamp;
  v_hour integer;
begin
  v_due := p_saved_at;
  case p_delay_unit
    when 'hour' then v_due := v_due + make_interval(hours => p_delay_value);
    when 'day' then v_due := v_due + make_interval(days => p_delay_value);
    when 'week' then v_due := v_due + make_interval(days => p_delay_value * 7);
    when 'month' then v_due := v_due + make_interval(months => p_delay_value);
    when 'year' then v_due := v_due + make_interval(years => p_delay_value);
    else v_due := v_due + make_interval(months => p_delay_value);
  end case;

  if not coalesce(p_quiet_hours, true) then
    return v_due;
  end if;

  v_local := v_due at time zone 'Asia/Baghdad';
  v_hour := extract(hour from v_local)::integer;
  if v_hour >= 22 or v_hour < 8 then
    if v_hour >= 22 then
      v_local := date_trunc('day', v_local) + interval '1 day' + interval '8 hours';
    else
      v_local := date_trunc('day', v_local) + interval '8 hours';
    end if;
    v_due := v_local at time zone 'Asia/Baghdad';
  end if;
  return v_due;
end;
$$;

-- ——— جدولة بعد حفظ بطاقة غيار ———
create or replace function public.wa_followup_schedule_job(
  p_order_ref text,
  p_phone text,
  p_payload jsonb default '{}'::jsonb,
  p_saved_at timestamptz default now()
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := auth.uid();
  v_rule public.wa_oil_followup_rules%rowtype;
  v_due timestamptz;
  v_id uuid;
  v_idem text;
  v_phone text;
begin
  if v_tenant is null then
    raise exception 'not_authenticated';
  end if;
  v_phone := trim(coalesce(p_phone, ''));
  if length(v_phone) < 8 then
    return null;
  end if;
  if trim(coalesce(p_order_ref, '')) = '' then
    return null;
  end if;

  select * into v_rule from public.wa_oil_followup_rules
  where tenant_user_id = v_tenant;
  if not found or v_rule.enabled is not true then
    return null;
  end if;

  v_due := public.wa_followup_compute_due_at(
    coalesce(p_saved_at, now()),
    v_rule.delay_value,
    v_rule.delay_unit,
    v_rule.quiet_hours
  );
  v_idem := 'followup:' || v_tenant::text || ':' || trim(p_order_ref);

  update public.wa_oil_followup_jobs
  set
    customer_phone = v_phone,
    due_at = v_due,
    payload = coalesce(p_payload, '{}'::jsonb),
    status = 'queued',
    last_error = null,
    updated_at = now()
  where tenant_user_id = v_tenant
    and order_ref = trim(p_order_ref)
    and status in ('queued', 'sending')
  returning id into v_id;

  if v_id is not null then
    return v_id;
  end if;

  insert into public.wa_oil_followup_jobs (
    tenant_user_id, order_ref, customer_phone, due_at, status,
    payload, idempotency_key
  ) values (
    v_tenant, trim(p_order_ref), v_phone, v_due, 'queued',
    coalesce(p_payload, '{}'::jsonb), v_idem
  )
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    select id into v_id from public.wa_oil_followup_jobs
    where tenant_user_id = v_tenant
      and order_ref = trim(p_order_ref)
      and status in ('queued', 'sending')
    limit 1;
    return v_id;
end;
$$;

revoke all on function public.wa_followup_schedule_job(text, text, jsonb, timestamptz) from public;
grant execute on function public.wa_followup_schedule_job(text, text, jsonb, timestamptz) to authenticated;

revoke all on function public.wa_followup_compute_due_at(timestamptz, integer, text, boolean) from public;
grant execute on function public.wa_followup_compute_due_at(timestamptz, integer, text, boolean) to authenticated, service_role;

comment on table public.wa_oil_followup_rules is 'قاعدة تذكير واحدة لكل محل بعد غيار الزيت';
comment on table public.wa_oil_followup_jobs is 'وظائف تذكير مجدولة — تنفَّذ من cron';

create or replace function public.wa_followup_cancel_pending()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := auth.uid();
  v_n integer;
begin
  if v_tenant is null then
    return 0;
  end if;
  update public.wa_oil_followup_jobs
  set status = 'cancelled', updated_at = now()
  where tenant_user_id = v_tenant
    and status in ('queued', 'sending');
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function public.wa_followup_cancel_pending() from public;
grant execute on function public.wa_followup_cancel_pending() to authenticated;
