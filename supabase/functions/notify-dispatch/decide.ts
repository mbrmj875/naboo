/**
 * منطق القرار في notify-dispatch، بلا اتصال بالشبكة أو بقاعدة البيانات (قابل للاختبار).
 * docs/specs/notifications_master_plan_ar.md (خامسا، البنود 3 و4 و8).
 */

export type Category =
  | 'business'
  | 'shop_event'
  | 'naboo_ads'
  | 'naboo_account'
  | 'summary'
  | 'orders';

export type Priority = 'critical' | 'high' | 'normal' | 'low';

export type NotificationRow = {
  id: number;
  user_id: string;
  local_tenant_id: number;
  category: Category;
  type: string;
  priority: Priority;
  title_ar: string;
  body_ar: string;
  route: string | null;
  entity_id: string | null;
  audience: string;
  source_device_id: string | null;
  attempts: number;
};

export type PushDevice = {
  device_id: string;
  fcm_token: string;
  platform: string;
  role_key: string | null;
  permission_keys: string[] | null;
  owner_notify: boolean;
};

export type Prefs = {
  disabled_types: string[];
  quiet_start: string; // 'HH:MM[:SS]'
  quiet_end: string;
  hide_lock_details: boolean;
};

export const DEFAULT_PREFS: Prefs = {
  disabled_types: [],
  quiet_start: '23:00',
  quiet_end: '07:00',
  hide_lock_details: false,
};

/** العراق UTC+3 طوال السنة. */
const BAGHDAD_OFFSET_MIN = 180;

function minutesOf(hhmm: string): number {
  const [h, m] = hhmm.split(':').map((x) => parseInt(x, 10));
  return (h || 0) * 60 + (m || 0);
}

/**
 * إن كان الوقت داخل ساعات الهدوء: يعيد لحظة نهايتها (UTC). وإلا null.
 * الفترة قد تعبر منتصف الليل (23:00 إلى 07:00).
 */
export function quietUntil(now: Date, start: string, end: string): Date | null {
  const s = minutesOf(start);
  const e = minutesOf(end);
  if (s === e) return null;
  const localMin =
    (now.getUTCHours() * 60 + now.getUTCMinutes() + BAGHDAD_OFFSET_MIN) % 1440;
  const inside = s < e ? localMin >= s && localMin < e : localMin >= s || localMin < e;
  if (!inside) return null;
  let wait = e - localMin;
  if (wait <= 0) wait += 1440;
  const until = new Date(now.getTime() + wait * 60_000);
  until.setUTCSeconds(0, 0);
  return until;
}

/** «حسابك واشتراكك» لا يُحجب قبل تحديد هاتف المالك ولا يُطفأ من الإعدادات (قرارك). */
export function isAccountEssential(row: Pick<NotificationRow, 'category'>): boolean {
  return row.category === 'naboo_account';
}

export type Gate =
  | { kind: 'send' }
  | { kind: 'held_no_owner_phone' }
  | { kind: 'disabled_by_user' }
  | { kind: 'quiet_deferred'; until: Date };

export function gate(
  row: NotificationRow,
  hasOwnerPhone: boolean,
  prefs: Prefs,
  now: Date,
): Gate {
  const essential = isAccountEssential(row);
  if (!hasOwnerPhone && !essential) return { kind: 'held_no_owner_phone' };
  // «إعلانات وعروض من نابو» تُطفأ كلها بمفتاح واحد (naboo_ads)، وأي نوع آخر باسمه.
  if (
    !essential &&
    (prefs.disabled_types.includes(row.type) ||
      (row.category === 'naboo_ads' && prefs.disabled_types.includes('naboo_ads')))
  ) {
    return { kind: 'disabled_by_user' };
  }
  // الملخص اليومي يصل في وقته الذي اختاره المالك، فالهدوء لا ينطبق عليه (رابعا، البند 4).
  if (row.priority !== 'critical' && row.category !== 'summary') {
    const until = quietUntil(now, prefs.quiet_start, prefs.quiet_end);
    if (until) return { kind: 'quiet_deferred', until };
  }
  return { kind: 'send' };
}

/**
 * من يستلم (خامسا، البند 8):
 * - owner_phone: الأجهزة المعلَّمة فقط (الإشعارات المالية).
 * - owner: المعلَّمة + أي جهاز الداخل عليه مالك.
 * - perm:<key>: ما سبق + جهاز الموظف الذي يملك المفتاح (المرحلة 5).
 * - device:<id>: ذلك الجهاز.
 * الجهاز الذي صدر منه الحدث لا يستلم إشعاره.
 * «حسابك واشتراكك»: أي جهاز الداخل عليه مالك، حتى بلا علامة.
 */
export function selectRecipients(row: NotificationRow, devices: PushDevice[]): PushDevice[] {
  const isOwnerSession = (d: PushDevice) => d.role_key === 'owner' || d.role_key === 'admin';
  let picked: PushDevice[];
  const aud = row.audience;
  if (isAccountEssential(row)) {
    picked = devices.filter((d) => d.owner_notify || isOwnerSession(d));
  } else if (aud === 'owner_phone') {
    picked = devices.filter((d) => d.owner_notify);
  } else if (aud === 'owner') {
    picked = devices.filter((d) => d.owner_notify || isOwnerSession(d));
  } else if (aud.startsWith('perm:')) {
    const key = aud.slice(5);
    picked = devices.filter(
      (d) => d.owner_notify || isOwnerSession(d) || (d.permission_keys ?? []).includes(key),
    );
  } else if (aud.startsWith('device:')) {
    const id = aud.slice(7);
    picked = devices.filter((d) => d.device_id === id);
  } else {
    picked = [];
  }
  const seen = new Set<string>();
  return picked.filter((d) => {
    if (row.source_device_id && d.device_id === row.source_device_id) return false;
    if (seen.has(d.fcm_token)) return false;
    seen.add(d.fcm_token);
    return true;
  });
}

/** قنوات أندرويد (خامسا، البند 4). */
export function channelFor(category: Category, priority: Priority): string {
  if (category === 'orders') return 'naboo_orders';
  if (priority === 'critical') return 'naboo_urgent';
  switch (category) {
    case 'shop_event':
      return 'naboo_shop';
    case 'summary':
      return 'naboo_summary';
    case 'naboo_ads':
      return 'naboo_ads';
    case 'naboo_account':
      return 'naboo_account';
    default:
      return 'naboo_business';
  }
}

/** نص شاشة القفل. «إخفاء التفاصيل» يجعله عاما، والنص الكامل يبقى داخل التطبيق. */
export function lockScreenText(
  row: Pick<NotificationRow, 'category' | 'title_ar' | 'body_ar'>,
  prefs: Prefs,
  hasOwnerPhone = true,
): { title: string; body: string } {
  if (prefs.hide_lock_details && !isAccountEssential(row)) {
    return { title: 'نابو', body: 'حركة جديدة في المحل' };
  }
  // «حسابك واشتراكك» يصل قبل تحديد هاتف المالك، ومعه تذكير بالتحديد (خامسا، البند 8).
  if (isAccountEssential(row) && !hasOwnerPhone) {
    return { title: row.title_ar, body: `${row.body_ar}\nحدّد هاتف المالك لتصلك إشعارات المحل.` };
  }
  return { title: row.title_ar, body: row.body_ar };
}

const PRIORITY_RANK: Record<Priority, number> = { low: 0, normal: 1, high: 2, critical: 3 };

/** جمع الإشعار المدمج: «3 مرتجعات». */
const MERGED_LABEL: Record<string, string> = {
  sale_return: 'مرتجعات',
  debt_sale: 'بيوع بالدين',
  installment_sale: 'بيوع بالتقسيط',
  negative_stock_sale: 'بيوع أدت إلى رصيد سالب',
  shift_open: 'ورديات فُتحت',
  shift_close: 'ورديات أُغلقت',
  cash_difference: 'فروق في الصندوق',
  market_order: 'طلبات جديدة من السوق',
  restaurant_order: 'طلبات جديدة من الطاولات',
};

/** وحدة إرسال: إشعار واحد على الهاتف يمثّل صفا أو أكثر من السجل. */
export type SendUnit = {
  rows: NotificationRow[];
  lead: NotificationRow;
  title: string;
  body: string;
  route: string | null;
  entityId: string | null;
  priority: Priority;
  /** الجهاز المستثنى: مصدر كل الصفوف إن كان واحدا. */
  sourceDeviceId: string | null;
};

/** أكثر من هذا العدد من المجموعات لحساب واحد في الدفعة نفسها يصير إشعارا واحدا. */
export const DIGEST_AFTER = 3;

/**
 * الدمج (سادسا): صفوف الحساب الجاهزة للإرسال في الدفعة نفسها تُجمع حسب
 * (النوع، الجمهور، الفرع). وإن زادت مجموعات «هاتف المالك» عن 3 (مثل المؤجل
 * ليلا) تصير إشعارا واحدا «لديك N إشعارات جديدة».
 */
export function buildSendUnits(rows: NotificationRow[]): SendUnit[] {
  const groups = new Map<string, NotificationRow[]>();
  for (const r of rows) {
    const k = `${r.type}|${r.audience}|${r.local_tenant_id}`;
    groups.set(k, [...(groups.get(k) ?? []), r]);
  }
  const units: SendUnit[] = [];
  for (const g of groups.values()) units.push(unitOf(g));

  const ownerUnits = units.filter((u) => u.lead.audience === 'owner_phone' && !isAccountEssential(u.lead));
  if (ownerUnits.length <= DIGEST_AFTER) return units;

  const rest = units.filter((u) => !ownerUnits.includes(u));
  const all = ownerUnits.flatMap((u) => u.rows);
  const top = maxPriority(all);
  const digest: SendUnit = {
    rows: all,
    lead: all[0],
    title: `لديك ${all.length} إشعارات جديدة`,
    body: ownerUnits.slice(0, 2).map((u) => u.title).join('، ') + '، وغيرها.',
    route: 'notifications',
    entityId: null,
    priority: top,
    sourceDeviceId: sameSource(all),
  };
  return [digest, ...rest];
}

function unitOf(g: NotificationRow[]): SendUnit {
  const sorted = [...g].sort((a, b) => a.id - b.id);
  const lead = sorted[sorted.length - 1];
  if (sorted.length === 1) {
    return {
      rows: sorted,
      lead,
      title: lead.title_ar,
      body: lead.body_ar,
      route: lead.route,
      entityId: lead.entity_id,
      priority: lead.priority,
      sourceDeviceId: lead.source_device_id,
    };
  }
  const label = MERGED_LABEL[lead.type] ?? 'إشعارات جديدة';
  return {
    rows: sorted,
    lead,
    title: `${sorted.length} ${label}`,
    body: `آخرها: ${lead.title_ar}`,
    route: lead.route,
    entityId: null,
    priority: maxPriority(sorted),
    sourceDeviceId: sameSource(sorted),
  };
}

function maxPriority(rows: NotificationRow[]): Priority {
  return rows.reduce<Priority>(
    (p, r) => (PRIORITY_RANK[r.priority] > PRIORITY_RANK[p] ? r.priority : p),
    'low',
  );
}

function sameSource(rows: NotificationRow[]): string | null {
  const first = rows[0]?.source_device_id ?? null;
  return rows.every((r) => r.source_device_id === first) ? first : null;
}

/** إعادة المحاولة: 5 محاولات بفواصل متزايدة، ثم يبقى «فاشلا» في السجل. */
export const MAX_ATTEMPTS = 5;
export function retryAt(now: Date, attempts: number): Date {
  const minutes = [1, 5, 15, 60, 180][Math.min(attempts, 4)];
  return new Date(now.getTime() + minutes * 60_000);
}

/** حد أمان: 20 إشعارا في الساعة للحساب (رقم مقترح في الخطة). */
export const HOURLY_LIMIT = 20;
