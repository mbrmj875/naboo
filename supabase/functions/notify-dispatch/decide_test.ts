/** Run: deno test supabase/functions/notify-dispatch/decide_test.ts */
import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
  buildSendUnits,
  channelFor,
  DEFAULT_PREFS,
  gate,
  lockScreenText,
  type NotificationRow,
  type PushDevice,
  quietUntil,
  selectRecipients,
} from './decide.ts';

const row = (p: Partial<NotificationRow> = {}): NotificationRow => ({
  id: 1,
  user_id: 'u',
  local_tenant_id: 1,
  category: 'shop_event',
  type: 'shift_closed',
  priority: 'high',
  title_ar: 'أغلق علي الوردية',
  body_ar: 'في الصندوق 450,000 د.ع',
  route: null,
  entity_id: null,
  audience: 'owner_phone',
  source_device_id: null,
  attempts: 0,
  ...p,
});

const dev = (id: string, p: Partial<PushDevice> = {}): PushDevice => ({
  device_id: id,
  fcm_token: `t-${id}`,
  platform: 'android',
  role_key: null,
  permission_keys: [],
  owner_notify: false,
  ...p,
});

// 12:00 UTC = 15:00 بغداد (خارج الهدوء). 21:00 UTC = 00:00 بغداد (داخله).
const DAY = new Date('2026-11-23T12:00:00Z');
const NIGHT = new Date('2026-11-23T21:00:00Z');

Deno.test('hard gate: no owner phone holds everything except account notices', () => {
  assertEquals(gate(row(), false, DEFAULT_PREFS, DAY).kind, 'held_no_owner_phone');
  assertEquals(gate(row({ category: 'orders', priority: 'critical' }), false, DEFAULT_PREFS, DAY).kind, 'held_no_owner_phone');
  assertEquals(gate(row({ category: 'naboo_account' }), false, DEFAULT_PREFS, DAY).kind, 'send');
  assertEquals(gate(row(), true, DEFAULT_PREFS, DAY).kind, 'send');
});

Deno.test('quiet hours 23:00-07:00 Baghdad: defer non-critical until 07:00', () => {
  const g = gate(row(), true, DEFAULT_PREFS, NIGHT);
  assertEquals(g.kind, 'quiet_deferred');
  if (g.kind === 'quiet_deferred') assertEquals(g.until.toISOString(), '2026-11-24T04:00:00.000Z');
  assertEquals(gate(row({ priority: 'critical' }), true, DEFAULT_PREFS, NIGHT).kind, 'send');
  assertEquals(quietUntil(DAY, '23:00', '07:00'), null);
  assertEquals(quietUntil(DAY, '00:00', '00:00'), null);
});

Deno.test('user can disable a type but not account notices', () => {
  const prefs = { ...DEFAULT_PREFS, disabled_types: ['shift_closed', 'subscription_expiry'] };
  assertEquals(gate(row(), true, prefs, DAY).kind, 'disabled_by_user');
  assertEquals(gate(row({ category: 'naboo_account', type: 'subscription_expiry' }), true, prefs, DAY).kind, 'send');
});

Deno.test('financial goes to flagged phones only, never to the source device', () => {
  const devices = [
    dev('phone', { owner_notify: true }),
    dev('phone2', { owner_notify: true }),
    dev('shop', { role_key: 'owner' }),
    dev('cashier', { role_key: 'staff', permission_keys: ['inventory.view'] }),
  ];
  const ids = (r: NotificationRow) => selectRecipients(r, devices).map((d) => d.device_id);
  assertEquals(ids(row()), ['phone', 'phone2']);
  assertEquals(ids(row({ source_device_id: 'phone' })), ['phone2']);
  assertEquals(ids(row({ audience: 'owner', category: 'business' })), ['phone', 'phone2', 'shop']);
  assertEquals(ids(row({ audience: 'perm:inventory.view', category: 'business' })), ['phone', 'phone2', 'shop', 'cashier']);
  assertEquals(ids(row({ audience: 'device:cashier' })), ['cashier']);
  assertEquals(ids(row({ category: 'naboo_account', audience: 'owner_phone' })), ['phone', 'phone2', 'shop']);
});

Deno.test('same token on two device rows is sent once', () => {
  const devices = [dev('a', { owner_notify: true }), { ...dev('b', { owner_notify: true }), fcm_token: 't-a' }];
  assertEquals(selectRecipients(row(), devices).length, 1);
});

Deno.test('channels and lock-screen privacy', () => {
  assertEquals(channelFor('orders', 'critical'), 'naboo_orders');
  assertEquals(channelFor('shop_event', 'critical'), 'naboo_urgent');
  assertEquals(channelFor('shop_event', 'high'), 'naboo_shop');
  assertEquals(channelFor('business', 'normal'), 'naboo_business');
  const hidden = { ...DEFAULT_PREFS, hide_lock_details: true };
  assertEquals(lockScreenText(row(), hidden), { title: 'نابو', body: 'حركة جديدة في المحل' });
  assertEquals(lockScreenText(row(), DEFAULT_PREFS).title, 'أغلق علي الوردية');
});

Deno.test('summary ignores quiet hours; account notice reminds to set the owner phone', () => {
  assertEquals(gate(row({ category: 'summary', priority: 'low' }), true, DEFAULT_PREFS, NIGHT).kind, 'send');
  const t = lockScreenText(row({ category: 'naboo_account', body_ar: 'جدّد' }), DEFAULT_PREFS, false);
  assertEquals(t.body, 'جدّد\nحدّد هاتف المالك لتصلك إشعارات المحل.');
  assertEquals(lockScreenText(row({ category: 'naboo_account', body_ar: 'جدّد' }), DEFAULT_PREFS, true).body, 'جدّد');
});

Deno.test('merge: same type in one batch becomes one push', () => {
  const units = buildSendUnits([
    row({ id: 1, type: 'sale_return', title_ar: 'مرتجع بمبلغ 5,000 د.ع', source_device_id: 'shop' }),
    row({ id: 2, type: 'sale_return', title_ar: 'مرتجع بمبلغ 9,000 د.ع', source_device_id: 'shop' }),
    row({ id: 3, type: 'shift_close' }),
  ]);
  assertEquals(units.length, 2);
  const merged = units.find((u) => u.rows.length === 2)!;
  assertEquals(merged.title, '2 مرتجعات');
  assertEquals(merged.body, 'آخرها: مرتجع بمبلغ 9,000 د.ع');
  assertEquals(merged.sourceDeviceId, 'shop');
  assertEquals(merged.entityId, null);
});

Deno.test('digest: many owner groups at once (morning after quiet) become one push', () => {
  const types = ['sale_return', 'debt_sale', 'shift_open', 'shift_close', 'cash_difference'];
  const units = buildSendUnits([
    ...types.map((t, i) => row({ id: i + 1, type: t, priority: t === 'cash_difference' ? 'critical' : 'high' })),
    row({ id: 9, type: 'market_order', category: 'orders', audience: 'perm:sales.pos', priority: 'critical' }),
  ]);
  assertEquals(units.length, 2);
  assertEquals(units[0].title, 'لديك 5 إشعارات جديدة');
  assertEquals(units[0].priority, 'critical');
  assertEquals(units[0].route, 'notifications');
  assertEquals(units[1].lead.type, 'market_order');
});

Deno.test('owner can mute all Naboo ads with one switch', () => {
  const prefs = { ...DEFAULT_PREFS, disabled_types: ['naboo_ads'] };
  assertEquals(gate(row({ category: 'naboo_ads', type: 'announcement', priority: 'low' }), true, prefs, DAY).kind, 'disabled_by_user');
  assertEquals(gate(row({ category: 'naboo_account', type: 'app_update' }), true, prefs, DAY).kind, 'send');
});
