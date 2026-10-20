#!/usr/bin/env node
/**
 * تشخيص واتساب — أداة دعم محلية (service_role من .env.local).
 *
 * أمثلة:
 *   npm run whatsapp:diagnose -- --email alaqeelioilcenter@gmail.com
 *   npm run whatsapp:diagnose -- --user cb89edb1-a4d2-45fb-9ed3-f30a14126d6b
 *   npm run whatsapp:diagnose -- --phone 07715948175
 *   npm run whatsapp:diagnose -- --instance shop_cb89edb1_a4d2_45fb_9ed3_f30a14126d6b
 *   npm run whatsapp:diagnose -- --email x@y.com --lid-stats
 */
import { createClient } from '@supabase/supabase-js';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');

function loadEnv() {
  const path = resolve(root, '.env.local');
  if (!existsSync(path)) {
    console.error('مفقود: admin-web/.env.local');
    process.exit(1);
  }
  const env = {};
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const m = line.match(/^([A-Za-z0-9_]+)=(.*)$/);
    if (!m) continue;
    env[m[1]] = m[2].trim().replace(/^["']|["']$/g, '');
  }
  return env;
}

function parseArgs(argv) {
  const out = { lidStats: false, limit: 40 };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const next = argv[i + 1];
    if (a === '--email' && next) {
      out.email = next;
      i++;
    } else if (a === '--user' && next) {
      out.userId = next;
      i++;
    } else if (a === '--phone' && next) {
      out.phone = next;
      i++;
    } else if (a === '--instance' && next) {
      out.instance = next;
      i++;
    } else if (a === '--limit' && next) {
      out.limit = Number(next) || 40;
      i++;
    } else if (a === '--lid-stats') {
      out.lidStats = true;
    } else if (a === '--help' || a === '-h') {
      out.help = true;
    }
  }
  return out;
}

function normalizeIraq(raw) {
  let d = String(raw || '').replace(/\D/g, '');
  if (!d) return '';
  if (d.startsWith('964')) return d;
  if (d.startsWith('0')) return `964${d.slice(1)}`;
  if (d.length === 10 && d.startsWith('7')) return `964${d}`;
  return d;
}

function suggest(reason) {
  const r = (reason || '').toLowerCase();
  if (r.includes('same_as_shop')) return 'أدخل رقم زبون ≠ رقم الجلسة المربوطة.';
  if (r.includes('invalid_phone') || r.includes('number_not_on')) {
    return 'تحقق من رقم الزبون ووجوده على واتساب.';
  }
  if (r.includes('removed') || r.includes('instance_not_found')) {
    return 'الجلسة محذوفة — أعد QR مرة واحدة واتركها.';
  }
  if (r.includes('disconnected') || r.includes('515') || r.includes('503')) {
    return 'فصل عفوي — أعد الربط وتجنّب الاستخدام اليدوي المكثّف.';
  }
  if (r.includes('none_timeout') || r.includes('lid')) {
    return 'تسليم معلّق/@lid — اختبر برقم آخر وراقب نسبة lid.';
  }
  if (r.includes('timeout')) return 'أعد المحاولة؛ افحص Evolution إن تكرر.';
  return 'راجع الجدول الزمني أدناه.';
}

function pickPrimaryIssue(events, gate, liveOk) {
  if (liveOk === false && gate?.status === 'connected') {
    return {
      code: 'stale_connected',
      text: 'السحابة تقول متصل بينما Evolution لا يؤكد — حالة وهمية.',
      action: 'حدّث الحالة أو أعد QR؛ حالة REMOVED يجب أن تظهر منفصلة.',
    };
  }
  if (gate?.status === 'disconnected' || liveOk === false) {
    return {
      code: 'disconnected',
      text: 'الجلسة منفصلة أو غير موجودة.',
      action: suggest('disconnected'),
    };
  }
  const recent = events.slice(0, 15);
  const same = recent.find((e) => e.reason_code === 'same_as_shop_phone');
  if (same) {
    return {
      code: 'same_as_shop_phone',
      text: 'محاولة إرسال لرقم المحل نفسه.',
      action: suggest('same_as_shop_phone'),
    };
  }
  const none = recent.find((e) => e.outcome === 'none_timeout');
  if (none) {
    return {
      code: none.reason_code || 'none_timeout',
      text: `رسالة بلا تسليم بعد 15د (jid=${none.recipient_jid_type || '?'}).`,
      action: suggest(none.reason_code || 'none_timeout'),
    };
  }
  const err = recent.find((e) => e.severity === 'error' || e.outcome === 'error');
  if (err) {
    return {
      code: err.reason_code || 'error',
      text: err.technical_detail || err.event_type,
      action: err.suggested_action || suggest(err.reason_code),
    };
  }
  return {
    code: 'ok',
    text: 'لا مشكلة ظاهرة في آخر الأحداث.',
    action: '—',
  };
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || (!args.email && !args.userId && !args.phone && !args.instance && !args.lidStats)) {
    console.log(`استخدام:
  npm run whatsapp:diagnose -- --email USER@gmail.com
  npm run whatsapp:diagnose -- --user <uuid>
  npm run whatsapp:diagnose -- --phone 07xxxxxxxx
  npm run whatsapp:diagnose -- --instance shop_...
  npm run whatsapp:diagnose -- --lid-stats`);
    process.exit(args.help ? 0 : 1);
  }

  const env = loadEnv();
  const url = env.NEXT_PUBLIC_SUPABASE_URL || env.SUPABASE_URL;
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error('تحتاج SUPABASE_SERVICE_ROLE_KEY و URL في .env.local');
    process.exit(1);
  }
  const sb = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  if (args.lidStats) {
    const { data, error } = await sb.rpc('whatsapp_lid_failure_stats', { p_days: 7 });
    console.log('\n=== نسبة فشل الإرسال حسب نوع JID (7 أيام) ===');
    if (error) console.error(error.message);
    else console.table(data ?? []);
    if (!args.email && !args.userId && !args.phone && !args.instance) return;
  }

  let userId = args.userId || null;
  let email = args.email || null;
  let instance = args.instance || null;

  if (args.phone && !userId) {
    const digits = normalizeIraq(args.phone);
    const { data: rows } = await sb
      .from('whatsapp_diagnostic_events')
      .select('user_id, shop_phone, recipient_phone, created_at')
      .or(`shop_phone.eq.${digits},recipient_phone.eq.${digits}`)
      .order('created_at', { ascending: false })
      .limit(1);
    if (rows?.[0]?.user_id) userId = rows[0].user_id;
    else {
      const { data: g } = await sb
        .from('tenant_whatsapp_gateways')
        .select('user_id, whatsapp_phone')
        .eq('whatsapp_phone', digits)
        .maybeSingle();
      if (g?.user_id) userId = g.user_id;
    }
  }

  if (instance && !userId) {
    const { data: g } = await sb
      .from('tenant_whatsapp_gateways')
      .select('user_id')
      .eq('evolution_instance_name', instance)
      .maybeSingle();
    if (g?.user_id) userId = g.user_id;
  }

  if (email && !userId) {
    const { data: list, error } = await sb.auth.admin.listUsers({ perPage: 1000 });
    if (error) {
      // fallback profiles
      const { data: prof } = await sb
        .from('profiles')
        .select('id, email')
        .eq('email', email)
        .maybeSingle();
      if (prof?.id) userId = prof.id;
      else {
        console.error('تعذّر إيجاد المستخدم بالبريد:', error.message);
        process.exit(1);
      }
    } else {
      const u = (list?.users ?? []).find(
        (x) => (x.email || '').toLowerCase() === email.toLowerCase(),
      );
      if (!u) {
        const { data: prof } = await sb
          .from('profiles')
          .select('id, email')
          .ilike('email', email)
          .maybeSingle();
        if (prof?.id) userId = prof.id;
        else {
          console.error('لا مستخدم بهذا البريد:', email);
          process.exit(1);
        }
      } else {
        userId = u.id;
        email = u.email;
      }
    }
  }

  if (!userId) {
    console.error('لم يُعثر على الحساب.');
    process.exit(1);
  }

  const { data: gate } = await sb
    .from('tenant_whatsapp_gateways')
    .select('*')
    .eq('user_id', userId)
    .maybeSingle();

  instance = gate?.evolution_instance_name || instance ||
    `shop_${userId.replace(/-/g, '_')}`;

  if (!email) {
    const { data: prof } = await sb
      .from('profiles')
      .select('email')
      .eq('id', userId)
      .maybeSingle();
    email = prof?.email || '—';
  }

  // حالة حية عبر REST Evolution إن توفّر المفتاح في env (اختياري)
  let liveNote = 'غير مفحوصة (لا EVO من هذه الأداة افتراضياً)';
  const evoBase = env.EVOLUTION_BASE_URL || 'https://evo-nrwn.srv1769126.hstgr.cloud';
  const evoKey = env.EVOLUTION_API_KEY;
  let liveOk = null;
  if (evoKey) {
    try {
      const res = await fetch(
        `${evoBase}/instance/connectionState/${instance}`,
        { headers: { apikey: evoKey } },
      );
      if (res.status === 404) {
        liveOk = false;
        liveNote = 'REMOVED / غير موجودة (HTTP 404)';
      } else if (res.ok) {
        const j = await res.json();
        const st = String(j?.instance?.state ?? j?.state ?? '').toLowerCase();
        liveOk = st === 'open';
        liveNote = `state=${st || '?'}`;
      } else {
        liveOk = false;
        liveNote = `HTTP ${res.status}`;
      }
    } catch (e) {
      liveNote = `خطأ: ${e.message}`;
    }
  }

  const { data: events } = await sb
    .from('whatsapp_diagnostic_events')
    .select('*')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(args.limit);

  const { data: audit } = await sb
    .from('whatsapp_gateway_audit')
    .select('created_at, action, detail, meta')
    .eq('user_id', userId)
    .order('created_at', { ascending: false })
    .limit(15);

  const issue = pickPrimaryIssue(events ?? [], gate, liveOk);

  console.log('\n========== تشخيص واتساب ==========');
  console.log(`الحساب: ${email}`);
  console.log(`user_id: ${userId}`);
  console.log(`instance: ${instance}`);
  console.log(`السحابة: status=${gate?.status ?? '—'} phone=${gate?.whatsapp_phone ?? '—'} updated=${gate?.updated_at ?? '—'}`);
  console.log(`الحيّة: ${liveNote}`);
  console.log(`آخر ربط: ${gate?.last_connected_at ?? '—'} | آخر فصل: ${gate?.last_disconnected_at ?? '—'}`);
  console.log('------------------------------------');
  console.log(`الخلاصة: [${issue.code}] ${issue.text}`);
  console.log(`الحل السريع: ${issue.action}`);
  console.log('------------------------------------');
  console.log('آخر أحداث التشخيص (الأحدث أولاً):');
  for (const e of events ?? []) {
    const ts = String(e.created_at || '').replace('T', ' ').slice(0, 19);
    console.log(
      `  ${ts} | ${e.event_type.padEnd(16)} | ${String(e.outcome || '-').padEnd(14)} | jid=${e.recipient_jid_type || '-'} | to=${e.recipient_phone || '-'} | shop=${e.shop_phone || '-'} | ${e.reason_code || ''} ${e.technical_detail || ''}`.slice(0, 200),
    );
  }
  if (!(events ?? []).length) {
    console.log('  (لا أحداث بعد — تأكد من تطبيق الـ migration ونشر الدوال)');
  }
  console.log('------------------------------------');
  console.log('آخر audit قديم (مرجع):');
  for (const a of audit ?? []) {
    const ts = String(a.created_at || '').replace('T', ' ').slice(0, 19);
    const meta = a.meta || {};
    console.log(
      `  ${ts} | ${a.action} | ${a.detail || ''} | to=${meta.sent_to || ''} shop=${meta.shop_digits || ''}`.slice(0, 160),
    );
  }
  console.log('====================================\n');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
