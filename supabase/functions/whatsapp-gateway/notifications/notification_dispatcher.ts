/**
 * NotificationDispatcher — توجيه القنوات + retry + logs.
 * لا يعرف WABA ولا ينشئ قوالب.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import type {
  NotificationDispatchResult,
  NotificationRequest,
} from './notification_request.ts';
import { dispatchWhatsappChannel } from './channels/whatsapp.ts';
import { writeClient } from '../admin_client.ts';
import { classifyExistingSendLog } from '../send_log_state.ts';
import { codeFromGatewayDetail, formatWaLogError } from '../wa_log_error.ts';
import { classifyFailure } from '../failure_policy.ts';
import { applySendBlock } from '../send_block.ts';

const MAX_ATTEMPTS = 3;
const BACKOFF_MS = [0, 800, 2000];

export async function dispatchNotification(
  supabase: SupabaseClient,
  request: NotificationRequest,
): Promise<NotificationDispatchResult> {
  const db = writeClient(supabase);

  let existingLogId: string | undefined;
  if (request.idempotencyKey) {
    const { data: existing } = await db
      .from('whatsapp_message_logs')
      .select('id, status, provider_message_id')
      .eq('tenant_user_id', request.tenantUserId)
      .eq('idempotency_key', request.idempotencyKey)
      .maybeSingle();
    if (existing) {
      const state = classifyExistingSendLog(
        existing.status,
        existing.provider_message_id,
      );
      if (state === 'done') {
        return {
          ok: true,
          channel: request.channel,
          providerMessageId: existing.provider_message_id
            ? String(existing.provider_message_id)
            : undefined,
          logId: String(existing.id),
          detail: 'idempotent_hit',
        };
      }
      // rejected / failed / أُرسل بلا wamid / claim سابق — نفس الصف.
      existingLogId = String(existing.id);
    }
  }

  if (request.channel === 'whatsapp') {
    return await withRetry(db, request, () =>
      dispatchWhatsappChannel(db, request)
    , existingLogId);
  }

  return {
    ok: false,
    channel: request.channel,
    detail: `channel_not_implemented:${request.channel}`,
  };
}

async function withRetry(
  supabase: SupabaseClient,
  request: NotificationRequest,
  fn: () => Promise<NotificationDispatchResult & { retryable?: boolean }>,
  existingLogId?: string,
): Promise<NotificationDispatchResult> {
  let last: NotificationDispatchResult = {
    ok: false,
    channel: request.channel,
    detail: 'no_attempt',
  };

  for (let i = 0; i < MAX_ATTEMPTS; i++) {
    if (BACKOFF_MS[i]) {
      await new Promise((r) => setTimeout(r, BACKOFF_MS[i]));
    }
    const result = await fn();
    last = result;
    if (result.ok) {
      await writeLog(supabase, request, 'sent', result, existingLogId);
      return result;
    }
    if (!result.retryable) {
      await writeLog(supabase, request, 'failed', result, existingLogId);
      return result;
    }
    // فشل غامض بعد بدء الإرسال للمزود: لا تُرسل مرة ثانية في نفس الطلب
    // (قد تكون Meta قبلت الرسالة قبل انقطاع الرد).
    if (isAmbiguousProviderFailure(result)) {
      await writeLog(supabase, request, 'failed', result, existingLogId);
      return result;
    }
  }

  await writeLog(supabase, request, 'failed', last, existingLogId);
  return last;
}

function isAmbiguousProviderFailure(
  result: NotificationDispatchResult & { retryable?: boolean },
): boolean {
  const d = `${result.detail ?? ''}`.toLowerCase();
  if (result.providerMessageId) return true;
  return (
    d.includes('timeout') ||
    d.includes('timed out') ||
    d.includes('abort') ||
    d.includes('fetch failed') ||
    d.includes('network') ||
    d.includes('econnreset') ||
    d.includes('socket')
  );
}

async function writeLog(
  supabase: SupabaseClient,
  request: NotificationRequest,
  status: 'sent' | 'failed',
  result: NotificationDispatchResult,
  existingLogId?: string,
): Promise<void> {
  try {
    const { data: gate } = await supabase
      .from('tenant_whatsapp_gateways')
      .select('whatsapp_provider')
      .eq('user_id', request.tenantUserId)
      .maybeSingle();
    const provider = String(gate?.whatsapp_provider ?? 'dualhook');
    const decision = result.ok ? null : classifyFailure({
      errorCode: result.errorCode,
      detail: result.detail,
      httpStatus: result.httpStatus,
      isSharedSender: provider === 'dualhook',
    });
    if (decision) {
      await applySendBlock(supabase, request.tenantUserId, decision, {
        provider,
        templateKey: request.templateKey,
      });
    }
    const errorJson = result.ok
      ? null
      : formatWaLogError({
        source: 'gateway',
        code: result.errorCode != null
          ? String(result.errorCode)
          : codeFromGatewayDetail(result.detail),
        title: '',
        message: result.detail ?? '',
        reasonCode: decision?.reasonCode,
      });
    const row = {
      tenant_user_id: request.tenantUserId,
      channel: request.channel,
      provider,
      template_key: request.templateKey,
      to_phone: request.recipient.phone ?? null,
      status,
      provider_message_id: result.providerMessageId ?? null,
      error: errorJson,
      idempotency_key: request.idempotencyKey ?? null,
      order_ref: request.orderRef ?? null,
      employee_name: request.employeeName ?? null,
      card_payload: request.variables,
      body: request.variables['details'] ?? null,
    };
    if (existingLogId) {
      await supabase
        .from('whatsapp_message_logs')
        .update({
          status: row.status,
          provider_message_id: row.provider_message_id,
          error: row.error,
          body: row.body,
          card_payload: row.card_payload,
          employee_name: row.employee_name,
        })
        .eq('id', existingLogId)
        .eq('tenant_user_id', request.tenantUserId);
    } else {
      await supabase.from('whatsapp_message_logs').insert(row);
    }
  } catch (e) {
    console.warn('whatsapp_message_logs insert failed', e);
  }
}
