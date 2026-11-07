/*
  تراجع عن 20261114_wa_wallet_settle.sql — يعيد wa_wallet_debit_one كما كانت في
  الإنتاج بتاريخ 2026-11-07، ويحذف التسوية وجدولتها.

  ما أُعيد من وحدات يبقى في الدفتر، ولا يُسحب.
*/

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $$
begin
  if to_regclass('cron.job') is not null then
    perform cron.unschedule(jobid) from cron.job
    where jobname = 'wa-wallet-settle-failed';
  end if;
end;
$$;

drop function if exists public.wa_wallet_settle_failed(timestamptz, boolean, integer);

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
$function$
;

commit;
