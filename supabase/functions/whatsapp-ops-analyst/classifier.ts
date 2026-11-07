/**
 * مصنّف حتمي — يحدّد severity / pattern قبل أي AI.
 * الـ AI ممنوع من تغيير هذه الحقول.
 */
import {
  CODE_463_CHAIN_MIN,
  FALSE_ALARM_MIN,
  FLAP_THRESHOLD,
  PROVISION_STORM_MIN,
  SILENT_FAIL_ACK_RATIO,
  SILENT_FAIL_MIN_ACCEPTED,
  type PlaybookStepId,
  type Severity,
} from './constants.ts';

export type ClassifiedCondition = {
  ruleId: string;
  patternKey: string;
  severity: Severity;
  playbookStepId: PlaybookStepId;
  /** true = افتح فوراً بدون بوابة 5د */
  immediate: boolean;
  titleAr: string;
  summaryAr: string;
};

export type TenantSignals = {
  userId: string;
  sessionName: string;
  repairNeeded: boolean;
  liveStatus: string | null;
  /** عدد انتقالات WORKING↔FAILED|STOPPED خلال 60د */
  flapCount1h: number;
  auth401Count1h: number;
  code463Count1h: number;
  provisionStorm1h: number;
  falseAlarm1h: number;
  sendAccepted1h: number;
  deliveryAck1h: number;
  sendFailed1h: number;
  /** إشارة قيد رقم مؤكدة من الحقائق/التشخيص */
  numberLockSignal: boolean;
  /** سلسلة 463 ثم 401 (نمط باقر) */
  chain463Then401: boolean;
};

export function classifyTenant(signals: TenantSignals): ClassifiedCondition[] {
  const out: ClassifiedCondition[] = [];

  // ── P1 فوري ──
  if (signals.repairNeeded) {
    out.push({
      ruleId: 'rule_repair_needed',
      patternKey: 'repair_needed',
      severity: 'P1',
      playbookStepId: 'pb_relink_qr',
      immediate: true,
      titleAr: 'يلزم إعادة ربط واتساب',
      summaryAr: 'البوابة تشير إلى repair_needed — فصل دائم يتطلب مسح QR.',
    });
  }

  if (signals.auth401Count1h >= 1 && signals.repairNeeded) {
    out.push({
      ruleId: 'rule_auth_401_persistent',
      patternKey: 'auth_401_persistent',
      severity: 'P1',
      playbookStepId: 'pb_relink_qr',
      immediate: true,
      titleAr: 'فشل مصادقة 401 دائم',
      summaryAr: 'ظهرت إشارة 401 مع repair_needed — الجلسة غير صالحة للإرسال.',
    });
  }

  if (signals.numberLockSignal || signals.chain463Then401) {
    out.push({
      ruleId: 'rule_number_lock',
      patternKey: 'number_activity_lock',
      severity: 'P1',
      playbookStepId: 'pb_check_number_lock',
      immediate: true,
      titleAr: 'إشارة قيد نشاط الرقم',
      summaryAr: signals.chain463Then401
        ? 'نمط 463 ثم 401 — غالباً قيد واتساب على الرقم المربوط.'
        : 'إشارة قيد رقم مؤكدة من السجلات.',
    });
  }

  // ── تذبذب → P2 فوري عند العتبة (حادث واحد) ──
  if (signals.flapCount1h >= FLAP_THRESHOLD) {
    out.push({
      ruleId: 'rule_session_flapping',
      patternKey: 'session_flapping',
      severity: 'P2',
      playbookStepId: 'pb_stabilize_session',
      immediate: true,
      titleAr: 'تذبذب جلسة واتساب',
      summaryAr: `≥${FLAP_THRESHOLD} انتقالات حالة خلال 60 دقيقة لنفس الجلسة.`,
    });
  }

  // ── شروط تحتاج استمرار 5د ──
  const silentRatio =
    signals.sendAccepted1h > 0
      ? signals.deliveryAck1h / signals.sendAccepted1h
      : 1;
  if (
    signals.sendAccepted1h >= SILENT_FAIL_MIN_ACCEPTED &&
    silentRatio < SILENT_FAIL_ACK_RATIO
  ) {
    out.push({
      ruleId: 'rule_silent_undelivered',
      patternKey: 'silent_undelivered_spike',
      severity: 'P1',
      playbookStepId: 'pb_delivery_probe',
      immediate: false,
      titleAr: 'فشل تسليم صامت',
      summaryAr:
        `قبول إرسال (${signals.sendAccepted1h}) مع acks قليلة (${signals.deliveryAck1h}) خلال الساعة.`,
    });
  }

  if (signals.code463Count1h >= CODE_463_CHAIN_MIN) {
    out.push({
      ruleId: 'rule_code_463_chain',
      patternKey: 'waha_463_chain',
      severity: 'P2',
      playbookStepId: 'pb_wait_rate_limit',
      immediate: false,
      titleAr: 'سلسلة أخطاء 463',
      summaryAr: `${signals.code463Count1h} أخطاء 463 خلال الساعة — reachout/timelock محتمل.`,
    });
  }

  if (signals.provisionStorm1h >= PROVISION_STORM_MIN) {
    out.push({
      ruleId: 'rule_provision_storm',
      patternKey: 'provision_storm',
      severity: 'P2',
      playbookStepId: 'pb_avoid_hard_reset',
      immediate: false,
      titleAr: 'عاصفة provision / hard_reset',
      summaryAr: `${signals.provisionStorm1h} محاولات تهيئة خلال الساعة.`,
    });
  }

  if (signals.falseAlarm1h >= FALSE_ALARM_MIN && !signals.repairNeeded) {
    out.push({
      ruleId: 'rule_false_alarm_noise',
      patternKey: 'false_alarm_noise',
      severity: 'P3',
      playbookStepId: 'pb_review_false_alarm',
      immediate: false,
      titleAr: 'ضوضاء إنذارات كاذبة',
      summaryAr: `${signals.falseAlarm1h} إشارات false_alarm بلا فصل دائم.`,
    });
  }

  return dedupeByRule(out);
}

function dedupeByRule(items: ClassifiedCondition[]): ClassifiedCondition[] {
  const seen = new Set<string>();
  const out: ClassifiedCondition[] = [];
  for (const c of items) {
    if (seen.has(c.ruleId)) continue;
    seen.add(c.ruleId);
    out.push(c);
  }
  return out;
}

/** عدّ انتقالات الحالة الحية من سلسلة حقائق session_working / session_down. */
export function countFlapTransitions(
  events: Array<{ fact_type: string; code: string | null; created_at: string }>,
): number {
  const live = events
    .filter(
      (e) =>
        e.fact_type === 'session_working' ||
        e.fact_type === 'session_down' ||
        e.fact_type === 'session_signal',
    )
    .slice()
    .sort(
      (a, b) =>
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
    );

  let flaps = 0;
  let prev: 'up' | 'down' | null = null;
  for (const e of live) {
    const code = (e.code ?? '').toUpperCase();
    let cur: 'up' | 'down' | null = null;
    if (
      e.fact_type === 'session_working' ||
      code === 'WORKING' ||
      code === 'CONNECTED'
    ) {
      cur = 'up';
    } else if (
      e.fact_type === 'session_down' ||
      code === 'FAILED' ||
      code === 'STOPPED' ||
      code === 'DISCONNECTED'
    ) {
      cur = 'down';
    }
    if (!cur) continue;
    if (prev && prev !== cur) flaps += 1;
    prev = cur;
  }
  return flaps;
}

/** هل ظهرت 463 ثم 401 خلال النافذة (ترتيب زمني)؟ */
export function detect463Then401(
  events: Array<{ fact_type: string; code: string | null; created_at: string }>,
): boolean {
  const sorted = events
    .slice()
    .sort(
      (a, b) =>
        new Date(a.created_at).getTime() - new Date(b.created_at).getTime(),
    );
  let saw463 = false;
  for (const e of sorted) {
    const code = String(e.code ?? '');
    if (code === '463' || e.fact_type === 'send_error' && code.includes('463')) {
      saw463 = true;
    }
    if (saw463 && (code === '401' || e.fact_type === 'auth_401')) {
      return true;
    }
  }
  return false;
}
