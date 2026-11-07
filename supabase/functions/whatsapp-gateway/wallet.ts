import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import { writeClient } from './admin_client.ts';
import {
  classifyExistingSendLog,
  type ExistingSendLogState,
} from './send_log_state.ts';

export { classifyExistingSendLog } from './send_log_state.ts';
export type { ExistingSendLogState } from './send_log_state.ts';

export type WalletDebitResult = {
  ok: boolean;
  duplicate?: boolean;
  exempt?: boolean;
  error?: string;
  message_ar?: string;
};

/**
 * المخطط غائب فعلًا فقط عند هذين الرمزين. لا نقرأ نص الخطأ: رسالة «permission
 * denied for function wa_wallet_debit_one» تحوي اسم الدالة، وقراءتها كانت
 * ستحوّل منع الصلاحية إلى إرسال مجاني بلا خصم.
 */
export function isWalletSchemaMissing(
  error: { code?: string | null } | null | undefined,
): boolean {
  return error?.code === '42883' || error?.code === '42P01';
}

/** يخصم رسالة واحدة قبل الإرسال — idempotent عبر المفتاح. */
export async function debitWalletForSend(
  supabase: SupabaseClient,
  opts: {
    tenantUserId: string;
    idempotencyKey: string;
    provider?: string;
    sendKind?: string;
  },
): Promise<WalletDebitResult> {
  try {
    const db = writeClient(supabase);
    const { data, error } = await db.rpc('wa_wallet_debit_one', {
      p_tenant: opts.tenantUserId,
      p_idempotency_key: opts.idempotencyKey,
      p_provider: opts.provider ?? null,
      p_send_kind: opts.sendKind ?? null,
      p_log_id: null,
    });

    if (error) {
      // السكربت غير مُطبَّق بعد — لا نكسر الإرسال.
      if (isWalletSchemaMissing(error)) {
        console.warn('wa_wallet: schema missing — skip debit');
        return { ok: true, exempt: true };
      }
      console.error('wa_wallet debit error', error);
      return {
        ok: false,
        error: 'wallet_error',
        message_ar: 'تعذّر التحقق من رصيد الرسائل. أعد المحاولة.',
      };
    }

    const row = (data ?? {}) as Record<string, unknown>;
    if (row.ok === true) {
      return {
        ok: true,
        duplicate: row.duplicate === true,
        exempt: row.exempt === true,
      };
    }

    return {
      ok: false,
      error: String(row.error ?? 'insufficient_balance'),
      message_ar: String(
        row.message_ar ??
          'رصيد الرسائل غير كافٍ — اشترك أو جدّد الباقة.',
      ),
    };
  } catch (e) {
    console.error('wa_wallet debit exception', e);
    return {
      ok: false,
      error: 'wallet_exception',
      message_ar: 'تعذّر التحقق من رصيد الرسائل. أعد المحاولة.',
    };
  }
}

const NABOO_SHARED_WELCOME_QTY = 30;

/** مرة واحدة عند الربط برقم نابو الرسمي (dualhook / SHARED_SENDER). */
export async function creditNabooSharedWelcomeLot(
  supabase: SupabaseClient,
  tenantUserId: string,
): Promise<void> {
  try {
    const db = writeClient(supabase);
    const idempotencyKey = `naboo_shared_welcome_30:${tenantUserId}`;
    const { error } = await db.rpc('wa_wallet_credit_lot', {
      p_tenant: tenantUserId,
      p_qty: NABOO_SHARED_WELCOME_QTY,
      p_billing_cycle: 'monthly',
      p_reason: 'admin_adjust',
      p_created_by: 'system:naboo_shared_welcome',
      p_payment_ref: null,
      p_subscription_id: null,
      p_idempotency_key: idempotencyKey,
    });
    if (error) {
      if (isWalletSchemaMissing(error)) {
        console.warn('wa_wallet: schema missing — skip naboo welcome credit');
        return;
      }
      console.error('naboo shared welcome credit failed', error);
    }
  } catch (e) {
    console.error('naboo shared welcome credit exception', e);
  }
}

export function walletRejectResponse(result: WalletDebitResult): Response {
  // 200 دائماً — حتى يقرأ Flutter جسم JSON (مثل بقية مسارات الإرسال).
  return Response.json({
    ok: false,
    reason: result.error ?? 'insufficient_balance',
    detail: result.error ?? 'wallet',
    message_ar: result.message_ar ??
      'رصيد الرسائل غير كافٍ — اشترك أو جدّد الباقة من محفظة WhatsApp.',
  });
}

export type ProviderSendGate =
  | { action: 'send' }
  | {
    action: 'idempotent_hit';
    providerMessageId?: string | null;
  }
  | {
    action: 'in_flight';
    providerMessageId?: string | null;
  };

function gateFromLogState(
  state: ExistingSendLogState,
  providerMessageId?: string | null,
): ProviderSendGate {
  if (state === 'done') {
    return { action: 'idempotent_hit', providerMessageId: providerMessageId ?? null };
  }
  if (state === 'retry') return { action: 'send' };
  return { action: 'in_flight', providerMessageId: providerMessageId ?? null };
}

/**
 * بعد خصم المحفظة: إن كان المفتاح مكرراً لا تُرسل للمزود إلا عند فشل مؤكد.
 * يمنع إرسالاً مزدوجاً بين أجهزة / طلبات HTTP متزامنة.
 */
export async function gateProviderSendAfterWallet(
  supabase: SupabaseClient,
  opts: {
    tenantUserId: string;
    idempotencyKey: string;
    wallet: WalletDebitResult;
  },
): Promise<ProviderSendGate> {
  if (!opts.wallet.ok) return { action: 'in_flight' };
  if (!opts.wallet.duplicate) return { action: 'send' };

  try {
    const db = writeClient(supabase);
    const { data } = await db
      .from('whatsapp_message_logs')
      .select('status, provider_message_id')
      .eq('tenant_user_id', opts.tenantUserId)
      .eq('idempotency_key', opts.idempotencyKey)
      .maybeSingle();
    return gateFromLogState(
      classifyExistingSendLog(
        data?.status as string | null,
        data?.provider_message_id as string | null,
      ),
      (data?.provider_message_id as string | null) ?? null,
    );
  } catch (e) {
    console.warn('wallet duplicate gate lookup failed', e);
    // عند الشك: لا ترسل للمزود.
    return { action: 'in_flight' };
  }
}

/** محاولة Claim ذرية قبل الإرسال — يمنع سباق SELECT ثم إرسال مزدوج. */
export async function claimSendLogRow(
  supabase: SupabaseClient,
  opts: {
    tenantUserId: string;
    idempotencyKey: string;
    toPhone: string;
    provider: string;
    templateKey?: string;
    orderRef?: string | null;
    employeeName?: string | null;
    body?: string | null;
  },
): Promise<ProviderSendGate> {
  const db = writeClient(supabase);
  try {
    const { data: existing } = await db
      .from('whatsapp_message_logs')
      .select('id, status, provider_message_id')
      .eq('tenant_user_id', opts.tenantUserId)
      .eq('idempotency_key', opts.idempotencyKey)
      .maybeSingle();

    if (existing) {
      const state = classifyExistingSendLog(
        existing.status,
        existing.provider_message_id,
      );
      if (state === 'done' || state === 'in_flight') {
        return gateFromLogState(state, existing.provider_message_id);
      }
      // failed / rejected / أُرسل بلا wamid — أعد الصف للإرسال.
      await db
        .from('whatsapp_message_logs')
        .update({
          status: 'queued',
          error: null,
          to_phone: opts.toPhone,
          provider: opts.provider,
        })
        .eq('id', existing.id)
        .eq('tenant_user_id', opts.tenantUserId);
      return { action: 'send' };
    }

    const { error: insErr } = await db.from('whatsapp_message_logs').insert({
      tenant_user_id: opts.tenantUserId,
      channel: 'whatsapp',
      provider: opts.provider,
      template_key: opts.templateKey ?? null,
      to_phone: opts.toPhone,
      // queued ضمن whatsapp_message_logs_status_check — لا تستخدم sending.
      status: 'queued',
      provider_message_id: null,
      error: null,
      order_ref: opts.orderRef ?? null,
      employee_name: opts.employeeName ?? null,
      body: opts.body ?? null,
      idempotency_key: opts.idempotencyKey,
    });

    if (insErr) {
      // سباق: طلب آخر أدخل الصف — أعد القراءة ولا ترسل إن كان غير failed.
      const { data: raced } = await db
        .from('whatsapp_message_logs')
        .select('status, provider_message_id')
        .eq('tenant_user_id', opts.tenantUserId)
        .eq('idempotency_key', opts.idempotencyKey)
        .maybeSingle();
      return gateFromLogState(
        classifyExistingSendLog(
          raced?.status,
          raced?.provider_message_id,
        ),
        raced?.provider_message_id ?? null,
      );
    }
    return { action: 'send' };
  } catch (e) {
    console.warn('claimSendLogRow failed', e);
    return { action: 'in_flight' };
  }
}
