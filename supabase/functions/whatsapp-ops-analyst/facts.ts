/**
 * كاتب حقائق واتساب — يُستدعى من whatsapp-events / gateway / analyst.
 */
import { phoneFingerprint } from './fingerprint.ts';

export type OpsFactInput = {
  userId: string;
  sessionName: string;
  factType: string;
  code?: string | null;
  phone?: string | null;
  rawRef?: string | null;
  meta?: Record<string, unknown> | null;
};

export async function writeOpsFact(
  // deno-lint-ignore no-explicit-any
  sb: any,
  input: OpsFactInput,
): Promise<void> {
  try {
    const { error } = await sb.from('whatsapp_ops_facts').insert({
      user_id: input.userId,
      session_name: input.sessionName,
      fact_type: input.factType,
      code: input.code ?? null,
      phone_fingerprint: phoneFingerprint(input.phone),
      raw_ref: (input.rawRef ?? '').slice(0, 200) || null,
      meta: input.meta ?? {},
    });
    if (error) console.warn('ops fact insert failed', error.message);
  } catch (e) {
    console.warn('ops fact insert failed', e);
  }
}

/** يحوّل أحداث التشخيص الشائعة إلى fact_type موحّد. */
export function mapDiagnosticToFactType(args: {
  eventType: string;
  outcome?: string | null;
  reasonCode?: string | null;
  technicalDetail?: string | null;
}): { factType: string; code: string | null } | null {
  const et = (args.eventType ?? '').toLowerCase();
  const outcome = (args.outcome ?? '').toLowerCase();
  const reason = (args.reasonCode ?? '').toLowerCase();
  const detail = (args.technicalDetail ?? '').toLowerCase();
  const blob = `${outcome} ${reason} ${detail}`;

  if (et === 'send_accepted' || outcome === 'send_accepted' || outcome === 'accepted') {
    return { factType: 'send_accepted', code: null };
  }
  if (et === 'delivery_update' || outcome.includes('ack') || outcome === 'delivered') {
    return { factType: 'delivery_ack', code: null };
  }
  if (blob.includes('463') || reason.includes('463')) {
    return { factType: 'send_error', code: '463' };
  }
  if (blob.includes('401') || reason.includes('401')) {
    return { factType: 'auth_401', code: '401' };
  }
  if (reason.includes('repair_needed') || outcome.includes('disconnect_permanent')) {
    return { factType: 'repair_needed', code: reason || 'repair_needed' };
  }
  if (et === 'soft_reconnect' || reason.includes('soft_reconnect')) {
    return {
      factType: 'soft_reconnect',
      code: outcome.includes('fail') ? 'soft_fail' : 'soft_ok',
    };
  }
  if (
    et.includes('provision') ||
    reason.includes('provision') ||
    reason.includes('hard_reset') ||
    blob.includes('hard_reset')
  ) {
    return {
      factType: 'provision_storm',
      code: reason.includes('hard_reset') ? 'hard_reset' : 'provision',
    };
  }
  if (outcome === 'connected' || (et === 'connection' && outcome === 'connected')) {
    return { factType: 'session_working', code: 'WORKING' };
  }
  if (
    outcome.includes('disconnect') ||
    outcome === 'failed' ||
    blob.includes('stopped')
  ) {
    const code = blob.includes('failed')
      ? 'FAILED'
      : blob.includes('stopped')
      ? 'STOPPED'
      : 'disconnected';
    return { factType: 'session_down', code };
  }
  if (reason.includes('false') || blob.includes('waha_error')) {
    return { factType: 'false_alarm', code: reason || 'waha_error' };
  }
  if (et === 'connection' || et === 'provider_event') {
    return { factType: 'session_signal', code: reason || outcome || null };
  }
  return null;
}
