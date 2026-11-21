/*
  إرجاع الرصيد عند الفشل، دون تكرار الإرسال أو الخصم.

  - خلال 24 ساعة من الفشل: الإعادة مجانية، كما يعمل الكود اليوم.
  - بعد 24 ساعة أو عند الإسقاط: تعود الوحدة عبر wa_wallet_settle_failed.
  - إعادة بعد الاسترداد: خصم جديد بالمفتاح K#n لأن المفتاح القديم مسترد.

  التسوية تعتمد على صافي عائلة المفتاح، فتشغيلها مرتين لا يعيد الوحدة مرتين.
  p_debits_since إلزامي حتى لا تمس الدورية الخصومات القديمة: تسوية الماضي قرار منفصل.
  المتطلب: 20261113_wa_failure_policy.sql (dismissed_at) و20261108_wa_rpc_lockdown.sql.
  الاختبار: 20261114_wa_wallet_settle.test.sql
  الرجوع: 20261114_wa_wallet_settle.rollback.sql
*/

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

CREATE OR REPLACE FUNCTION public.wa_wallet_debit_one(p_tenant uuid, p_idempotency_key text, p_provider text DEFAULT NULL::text, p_send_kind text DEFAULT NULL::text, p_log_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_wallet public.wa_message_wallet%rowtype;
  v_settings public.wa_message_platform_settings%rowtype;
  v_lot public.wa_message_lots%rowtype;
  v_existing uuid;
  v_sends integer;
  v_refunds integer;
  v_key text := p_idempotency_key;
begin
  if p_idempotency_key is null or length(trim(p_idempotency_key)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'missing_idempotency');
  end if;

  perform public.wa_wallet_ensure(p_tenant);

  select * into v_settings from public.wa_message_platform_settings where id = 1;
  select * into v_wallet from public.wa_message_wallet
  where tenant_user_id = p_tenant for update;

  -- عائلة المفتاح: K ثم K#2 للخصم بعد الاسترداد، وK#r1 للاسترداد.
  select
    count(*) filter (where reason = 'send'),
    count(*) filter (where reason = 'refund_failed_send'),
    (array_agg(id order by created_at desc) filter (where reason = 'send'))[1]
  into v_sends, v_refunds, v_existing
  from public.wa_message_ledger
  where tenant_user_id = p_tenant
    and (
      idempotency_key = p_idempotency_key
      or (
        left(idempotency_key, length(p_idempotency_key) + 1) = p_idempotency_key || '#'
        and substr(idempotency_key, length(p_idempotency_key) + 2) ~ '^r?[0-9]+$'
      )
    );

  -- لم يُسترد الخصم بعد: الإعادة مجانية.
  if v_sends > v_refunds then
    return jsonb_build_object('ok', true, 'duplicate', true, 'ledger_id', v_existing);
  end if;

  -- استُرد الخصم: الإعادة خصم جديد بمفتاح جديد.
  if v_sends > 0 then
    v_key := p_idempotency_key || '#' || (v_sends + 1);
  end if;

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
      p_tenant, 0, 'send', p_provider, p_send_kind, p_log_id, v_key,
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
    p_tenant, v_lot.id, -1, 'send', p_provider, p_send_kind, p_log_id, v_key
  );

  return jsonb_build_object('ok', true, 'lot_id', v_lot.id, 'balance_after', v_wallet.balance - 1);
end;
$function$
;

create or replace function public.wa_wallet_settle_failed(
  p_debits_since timestamptz,
  p_dry_run boolean default true,
  p_limit integer default 500
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r record;
  v_refunded integer := 0;
  v_lot uuid;
  v_by_tenant jsonb := '{}'::jsonb;
begin
  -- طلب واحد في كل مرة، حتى لا يتزامن تشغيلان.
  if not pg_try_advisory_xact_lock(hashtext('wa_wallet_settle_failed')) then
    return jsonb_build_object('ok', false, 'error', 'already_running');
  end if;

  for r in
    with families as (
      select
        l.tenant_user_id,
        regexp_replace(l.idempotency_key, '#r?[0-9]+$', '') as base_key,
        count(*) filter (where l.reason = 'send') as sends,
        count(*) filter (where l.reason = 'refund_failed_send') as refunds,
        sum(l.delta) as net,
        max(l.created_at) filter (where l.reason = 'send') as last_debit_at
      from public.wa_message_ledger l
      where l.idempotency_key is not null
        and l.reason in ('send', 'refund_failed_send')
      group by 1, 2
    )
    select f.tenant_user_id, f.base_key, f.refunds
    from families f
    join public.whatsapp_message_logs m
      on m.tenant_user_id = f.tenant_user_id
     and m.idempotency_key = f.base_key
    where f.sends > f.refunds
      and f.net < 0
      and m.status in ('failed', 'rejected')
      and (m.dismissed_at is not null or f.last_debit_at < now() - interval '24 hours')
      and (p_debits_since is null or f.last_debit_at >= p_debits_since)
    order by f.last_debit_at
    limit greatest(coalesce(p_limit, 500), 0)
  loop
    if not p_dry_run then
      begin
        v_lot := public.wa_wallet_credit_lot(
          r.tenant_user_id,
          1,
          'monthly',
          'refund_failed_send',
          'system:settle_failed',
          null,
          null,
          r.base_key || '#r' || (r.refunds + 1)
        );
        if v_lot is null then
          continue;
        end if;
      exception when unique_violation then
        continue;
      end;
    end if;
    v_refunded := v_refunded + 1;
    v_by_tenant := jsonb_set(
      v_by_tenant,
      array[r.tenant_user_id::text],
      to_jsonb(coalesce((v_by_tenant ->> r.tenant_user_id::text)::integer, 0) + 1)
    );
  end loop;

  return jsonb_build_object(
    'ok', true,
    'dry_run', p_dry_run,
    'refunded', v_refunded,
    'by_tenant', v_by_tenant
  );
end;
$function$;

revoke all on function public.wa_wallet_settle_failed(timestamptz, boolean, integer)
  from public, anon, authenticated;
grant execute on function public.wa_wallet_settle_failed(timestamptz, boolean, integer)
  to service_role;

commit;
