/** ثوابت WhatsApp Ops Analyst — مطابقة للمواصفة. */
export const CRON_INTERVAL_MS = 5 * 60_000;
export const PERSISTENCE_MS = 5 * 60_000;
export const FLAP_WINDOW_MS = 60 * 60_000;
export const FLAP_THRESHOLD = 6;
export const RESOLVE_STABLE_MS = 15 * 60_000;
export const P1_SLA_MS = 15 * 60_000;
export const HEALTHCHECKS_GRACE_MS = 10 * 60_000;
export const DELIVERY_WINDOW_MS = 60 * 60_000;
/** عتبة فشل صامت: accepted بدون ack بنسبة عالية مع حد أدنى للعيّنة. */
export const SILENT_FAIL_MIN_ACCEPTED = 5;
export const SILENT_FAIL_ACK_RATIO = 0.2;
export const PROVISION_STORM_MIN = 8;
export const CODE_463_CHAIN_MIN = 3;
export const FALSE_ALARM_MIN = 5;

export type Severity = 'P1' | 'P2' | 'P3';

export type PlaybookStepId =
  | 'pb_relink_qr'
  | 'pb_wait_rate_limit'
  | 'pb_avoid_hard_reset'
  | 'pb_check_number_lock'
  | 'pb_stabilize_session'
  | 'pb_review_false_alarm'
  | 'pb_delivery_probe';

export const PLAYBOOK: Record<
  PlaybookStepId,
  { title_ar: string; steps_ar: string[] }
> = {
  pb_relink_qr: {
    title_ar: 'إعادة ربط QR',
    steps_ar: [
      'أوقف محاولات hard_reset المتكررة.',
      'امسح QR مرة واحدة من هاتف المحل واترك الجلسة.',
      'تحقق أن الحالة WORKING قبل إرسال تجريبي.',
    ],
  },
  pb_wait_rate_limit: {
    title_ar: 'انتظار قيد/حد واتساب',
    steps_ar: [
      'لا ترسل حملات أو رسائل باردة كثيرة.',
      'انتظر انتهاء قيد النشاط على الهاتف إن ظهر.',
      'أعد المحاولة برقم زبون معروف بعد الاستقرار.',
    ],
  },
  pb_avoid_hard_reset: {
    title_ar: 'تجنّب عاصفة إعادة التهيئة',
    steps_ar: [
      'أغلق شاشة الربط إن كانت تُطلق provision تلقائياً.',
      'لا تضغط «إعادة ضبط» إلا عند repair_needed مؤكد.',
    ],
  },
  pb_check_number_lock: {
    title_ar: 'تحقق قيد الرقم',
    steps_ar: [
      'راجع واجهة واتساب الرسمية على الهاتف لقيود النشاط.',
      'لا تغيّر الرقم المربوط بسرعة بين أرقام متعددة.',
    ],
  },
  pb_stabilize_session: {
    title_ar: 'تثبيت الجلسة',
    steps_ar: [
      'راقب التذبذب WORKING↔FAILED دون تدخل يدوي.',
      'اسمح لـ health-check بمحاولة soft reconnect فقط.',
    ],
  },
  pb_review_false_alarm: {
    title_ar: 'مراجعة إنذارات كاذبة',
    steps_ar: [
      'فرّق بين waha_error/463 وبين فصل حي حقيقي.',
      'حدّث واجهة التطبيق إن ظهرت «غير متصل» خطأً.',
    ],
  },
  pb_delivery_probe: {
    title_ar: 'فحص التسليم',
    steps_ar: [
      'قارن send_accepted مع delivery ack خلال الساعة.',
      'أرسل رسالة اختبار لرقم معروف بعد استقرار الجلسة.',
    ],
  },
};
