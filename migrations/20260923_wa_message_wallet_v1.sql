-- Naboo WhatsApp message wallet v1
-- تشغيل مرة من Supabase SQL Editor (أو supabase db push).
-- الخصم/الشحن عبر service role أو دوال SECURITY DEFINER أدناه.

create extension if not exists pgcrypto;

-- ——— إعدادات المنصة (صف واحد) ———
create table if not exists public.wa_message_platform_settings (
  id smallint primary key default 1 check (id = 1),
  unit_price_iqd_x100 integer not null default 2500
    check (unit_price_iqd_x100 > 0), -- 2500 = 25.00 د.ع
  annual_discount_pct integer not null default 30
    check (annual_discount_pct >= 0 and annual_discount_pct <= 90),
  annual_free_months integer not null default 2
    check (annual_free_months >= 0 and annual_free_months <= 11),
  min_qty integer not null default 250,
  step_qty integer not null default 250,
  max_qty integer not null default 5000,
  enforce_wallet boolean not null default true,
  updated_at timestamptz not null default now(),
  updated_by text
);

insert into public.wa_message_platform_settings (id)
values (1)
on conflict (id) do nothing;

-- ——— محفظة لكل حساب (auth user = tenant owner) ———
create table if not exists public.wa_message_wallet (
  tenant_user_id uuid primary key references auth.users (id) on delete cascade,
  balance integer not null default 0 check (balance >= 0),
  frozen boolean not null default false,
  send_blocked boolean not null default false,
  wallet_exempt boolean not null default false,
  notes_admin text,
  updated_at timestamptz not null default now()
);

-- ——— اشتراك سنوي ———
create table if not exists public.wa_message_subscriptions (
  id uuid primary key default gen_random_uuid(),
  tenant_user_id uuid not null references auth.users (id) on delete cascade,
  qty integer not null check (qty > 0),
  yearly_pay_iqd integer not null check (yearly_pay_iqd >= 0),
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  months_credited integer not null default 0 check (months_credited >= 0),
  next_credit_at timestamptz,
  status text not null default 'active'
    check (status in ('active', 'cancelled', 'completed')),
  created_at timestamptz not null default now(),
  created_by text
);

create index if not exists wa_message_subscriptions_tenant_idx
  on public.wa_message_subscriptions (tenant_user_id, status);

create index if not exists wa_message_subscriptions_credit_idx
  on public.wa_message_subscriptions (next_credit_at)
  where status = 'active';

-- ——— دفعات رصيد (lots) ———
create table if not exists public.wa_message_lots (
  id uuid primary key default gen_random_uuid(),
  tenant_user_id uuid not null references auth.users (id) on delete cascade,
  subscription_id uuid references public.wa_message_subscriptions (id)
    on delete set null,
  qty integer not null check (qty > 0),
  billing_cycle text not null default 'monthly'
    check (billing_cycle in ('monthly', 'annual')),
  messages_total integer not null check (messages_total > 0),
  messages_remaining integer not null check (messages_remaining >= 0),
  purchased_at timestamptz not null default now(),
  expires_at timestamptz not null,
  status text not null default 'active'
    check (status in ('active', 'exhausted', 'expired')),
  payment_ref text,
  created_by text,
  created_at timestamptz not null default now()
);

create index if not exists wa_message_lots_tenant_active_idx
  on public.wa_message_lots (tenant_user_id, expires_at)
  where status = 'active' and messages_remaining > 0;

-- ——— دفتر القيود ———
create table if not exists public.wa_message_ledger (
  id uuid primary key default gen_random_uuid(),
  tenant_user_id uuid not null references auth.users (id) on delete cascade,
  lot_id uuid references public.wa_message_lots (id) on delete set null,
  delta integer not null,
  reason text not null
    check (reason in (
      'purchase', 'send', 'refund_failed_send', 'expire',
      'admin_adjust', 'subscription_credit', 'hold_release'
    )),
  provider text,
  send_kind text,
  log_id uuid,
  idempotency_key text,
  meta jsonb not null default '{}'::jsonb,
  created_by text,
  created_at timestamptz not null default now()
);

create unique index if not exists wa_message_ledger_idem_uidx
  on public.wa_message_ledger (tenant_user_id, idempotency_key)
  where idempotency_key is not null;

create index if not exists wa_message_ledger_tenant_idx
  on public.wa_message_ledger (tenant_user_id, created_at desc);

-- ——— طلبات الشراء ———
create table if not exists public.wa_message_pack_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_user_id uuid not null references auth.users (id) on delete cascade,
  qty integer not null check (qty > 0),
  billing_cycle text not null check (billing_cycle in ('monthly', 'annual')),
  amount_iqd integer not null check (amount_iqd >= 0),
  status text not null default 'pending_payment'
    check (status in (
      'pending_payment', 'paid', 'credited', 'cancelled'
    )),
  subscription_id uuid references public.wa_message_subscriptions (id)
    on delete set null,
  note text,
  created_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by text
);

create index if not exists wa_message_pack_orders_pending_idx
  on public.wa_message_pack_orders (created_at desc)
  where status = 'pending_payment';

create index if not exists wa_message_pack_orders_tenant_idx
  on public.wa_message_pack_orders (tenant_user_id, created_at desc);

-- ——— ضمان وجود صف محفظة ———
create or replace function public.wa_wallet_ensure(p_tenant uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.wa_message_wallet (tenant_user_id)
  values (p_tenant)
  on conflict (tenant_user_id) do nothing;
end;
$$;

-- ——— شحن lot + تحديث الرصيد ———
create or replace function public.wa_wallet_credit_lot(
  p_tenant uuid,
  p_qty integer,
  p_billing_cycle text,
  p_reason text,
  p_created_by text default null,
  p_subscription_id uuid default null,
  p_payment_ref text default null,
  p_idempotency_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_lot_id uuid;
  v_existing uuid;
begin
  if p_qty is null or p_qty <= 0 then
    raise exception 'invalid_qty';
  end if;

  if p_idempotency_key is not null then
    select id into v_existing
    from public.wa_message_ledger
    where tenant_user_id = p_tenant
      and idempotency_key = p_idempotency_key
    limit 1;
    if v_existing is not null then
      return null;
    end if;
  end if;

  perform public.wa_wallet_ensure(p_tenant);

  insert into public.wa_message_lots (
    tenant_user_id, subscription_id, qty, billing_cycle,
    messages_total, messages_remaining, expires_at, payment_ref, created_by
  ) values (
    p_tenant, p_subscription_id, p_qty, coalesce(p_billing_cycle, 'monthly'),
    p_qty, p_qty, now() + interval '30 days', p_payment_ref, p_created_by
  )
  returning id into v_lot_id;

  update public.wa_message_wallet
  set balance = balance + p_qty,
      updated_at = now()
  where tenant_user_id = p_tenant;

  insert into public.wa_message_ledger (
    tenant_user_id, lot_id, delta, reason, created_by, idempotency_key
  ) values (
    p_tenant, v_lot_id, p_qty, p_reason, p_created_by, p_idempotency_key
  );

  return v_lot_id;
end;
$$;

-- ——— خصم رسالة واحدة (FIFO على lots) ———
create or replace function public.wa_wallet_debit_one(
  p_tenant uuid,
  p_idempotency_key text,
  p_provider text default null,
  p_send_kind text default null,
  p_log_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_wallet public.wa_message_wallet%rowtype;
  v_settings public.wa_message_platform_settings%rowtype;
  v_lot public.wa_message_lots%rowtype;
  v_existing uuid;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'missing_idempotency');
  end if;

  select id into v_existing
  from public.wa_message_ledger
  where tenant_user_id = p_tenant
    and idempotency_key = p_idempotency_key
  limit 1;
  if v_existing is not null then
    return jsonb_build_object('ok', true, 'duplicate', true, 'ledger_id', v_existing);
  end if;

  perform public.wa_wallet_ensure(p_tenant);

  select * into v_settings from public.wa_message_platform_settings where id = 1;
  select * into v_wallet from public.wa_message_wallet
  where tenant_user_id = p_tenant for update;

  if v_wallet.send_blocked then
    return jsonb_build_object('ok', false, 'error', 'send_blocked',
      'message_ar', 'تم إيقاف إرسال واتساب لهذا الحساب من المنصة.');
  end if;

  if v_wallet.frozen then
    return jsonb_build_object('ok', false, 'error', 'wallet_frozen',
      'message_ar', 'محفظة الرسائل مجمّدة — تواصل مع الدعم.');
  end if;

  if v_wallet.wallet_exempt or not coalesce(v_settings.enforce_wallet, true) then
    insert into public.wa_message_ledger (
      tenant_user_id, delta, reason, provider, send_kind, log_id, idempotency_key, meta
    ) values (
      p_tenant, 0, 'send', p_provider, p_send_kind, p_log_id, p_idempotency_key,
      jsonb_build_object('exempt', true)
    );
    return jsonb_build_object('ok', true, 'exempt', true);
  end if;

  if v_wallet.balance < 1 then
    return jsonb_build_object('ok', false, 'error', 'insufficient_balance',
      'message_ar', 'رصيد الرسائل غير كافٍ — اشترك أو جدّد الباقة.');
  end if;

  select * into v_lot
  from public.wa_message_lots
  where tenant_user_id = p_tenant
    and status = 'active'
    and messages_remaining > 0
    and expires_at > now()
  order by expires_at asc
  for update
  limit 1;

  if v_lot.id is null then
    update public.wa_message_wallet
    set balance = 0, updated_at = now()
    where tenant_user_id = p_tenant;
    return jsonb_build_object('ok', false, 'error', 'insufficient_balance',
      'message_ar', 'رصيد الرسائل غير كافٍ — اشترك أو جدّد الباقة.');
  end if;

  update public.wa_message_lots
  set messages_remaining = messages_remaining - 1,
      status = case when messages_remaining - 1 <= 0 then 'exhausted' else status end
  where id = v_lot.id;

  update public.wa_message_wallet
  set balance = greatest(balance - 1, 0),
      updated_at = now()
  where tenant_user_id = p_tenant;

  insert into public.wa_message_ledger (
    tenant_user_id, lot_id, delta, reason, provider, send_kind, log_id, idempotency_key
  ) values (
    p_tenant, v_lot.id, -1, 'send', p_provider, p_send_kind, p_log_id, p_idempotency_key
  );

  return jsonb_build_object('ok', true, 'lot_id', v_lot.id, 'balance_after', v_wallet.balance - 1);
end;
$$;

-- ——— انتهاء lots ———
create or replace function public.wa_wallet_expire_lots()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select id, tenant_user_id, messages_remaining
    from public.wa_message_lots
    where status = 'active'
      and messages_remaining > 0
      and expires_at <= now()
    for update
  loop
    update public.wa_message_lots
    set status = 'expired', messages_remaining = 0
    where id = r.id;

    update public.wa_message_wallet
    set balance = greatest(balance - r.messages_remaining, 0),
        updated_at = now()
    where tenant_user_id = r.tenant_user_id;

    insert into public.wa_message_ledger (
      tenant_user_id, lot_id, delta, reason, meta
    ) values (
      r.tenant_user_id, r.id, -r.messages_remaining, 'expire',
      jsonb_build_object('expired_remaining', r.messages_remaining)
    );
    n := n + 1;
  end loop;
  return n;
end;
$$;

revoke all on function public.wa_wallet_ensure(uuid) from public;
revoke all on function public.wa_wallet_credit_lot(uuid, integer, text, text, text, uuid, text, text) from public;
revoke all on function public.wa_wallet_debit_one(uuid, text, text, text, uuid) from public;
revoke all on function public.wa_wallet_expire_lots() from public;

grant execute on function public.wa_wallet_ensure(uuid) to service_role;
grant execute on function public.wa_wallet_credit_lot(uuid, integer, text, text, text, uuid, text, text) to service_role;
grant execute on function public.wa_wallet_debit_one(uuid, text, text, text, uuid) to service_role;
grant execute on function public.wa_wallet_expire_lots() to service_role;

-- المستأجر يقرأ فقط
alter table public.wa_message_platform_settings enable row level security;
alter table public.wa_message_wallet enable row level security;
alter table public.wa_message_lots enable row level security;
alter table public.wa_message_ledger enable row level security;
alter table public.wa_message_pack_orders enable row level security;
alter table public.wa_message_subscriptions enable row level security;

drop policy if exists wa_settings_select on public.wa_message_platform_settings;
create policy wa_settings_select on public.wa_message_platform_settings
  for select to authenticated using (true);

drop policy if exists wa_wallet_select_own on public.wa_message_wallet;
create policy wa_wallet_select_own on public.wa_message_wallet
  for select to authenticated using (tenant_user_id = auth.uid());

drop policy if exists wa_lots_select_own on public.wa_message_lots;
create policy wa_lots_select_own on public.wa_message_lots
  for select to authenticated using (tenant_user_id = auth.uid());

drop policy if exists wa_ledger_select_own on public.wa_message_ledger;
create policy wa_ledger_select_own on public.wa_message_ledger
  for select to authenticated using (tenant_user_id = auth.uid());

drop policy if exists wa_orders_select_own on public.wa_message_pack_orders;
create policy wa_orders_select_own on public.wa_message_pack_orders
  for select to authenticated using (tenant_user_id = auth.uid());

drop policy if exists wa_orders_insert_own on public.wa_message_pack_orders;
create policy wa_orders_insert_own on public.wa_message_pack_orders
  for insert to authenticated
  with check (
    tenant_user_id = auth.uid()
    and status = 'pending_payment'
  );

drop policy if exists wa_subs_select_own on public.wa_message_subscriptions;
create policy wa_subs_select_own on public.wa_message_subscriptions
  for select to authenticated using (tenant_user_id = auth.uid());

comment on table public.wa_message_wallet is 'رصيد رسائل واتساب لكل حساب نابو';
comment on table public.wa_message_pack_orders is 'طلبات اشتراك رسائل بانتظار تأكيد المنصة';
