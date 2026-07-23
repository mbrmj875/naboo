#!/usr/bin/env node
/**
 * ضبط webhook التشخيص على كل instances الحالية في Evolution (مرة واحدة).
 * يقرأ EVOLUTION_* و WHATSAPP_EVENTS_* من admin-web/.env.local أو البيئة.
 *
 *   npm run whatsapp:webhook-backfill
 */
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = resolve(__dirname, '..');

function loadEnv() {
  const path = resolve(root, '.env.local');
  const env = { ...process.env };
  if (!existsSync(path)) return env;
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    const m = line.match(/^([A-Za-z0-9_]+)=(.*)$/);
    if (!m) continue;
    env[m[1]] = m[2].trim().replace(/^["']|["']$/g, '');
  }
  return env;
}

async function main() {
  const env = loadEnv();
  const evoBase = (env.EVOLUTION_BASE_URL || 'https://evo-nrwn.srv1769126.hstgr.cloud').replace(/\/$/, '');
  const evoKey = env.EVOLUTION_API_KEY;
  const supabaseUrl = (env.NEXT_PUBLIC_SUPABASE_URL || env.SUPABASE_URL || '').replace(/\/$/, '');
  const secret = env.WHATSAPP_EVENTS_WEBHOOK_SECRET || '';
  const webhookUrl =
    env.WHATSAPP_EVENTS_WEBHOOK_URL ||
    (supabaseUrl ? `${supabaseUrl}/functions/v1/whatsapp-events` : '');

  if (!evoKey) {
    console.error('EVOLUTION_API_KEY مفقود في .env.local');
    process.exit(1);
  }
  if (!webhookUrl) {
    console.error('WHATSAPP_EVENTS_WEBHOOK_URL أو SUPABASE URL مفقود');
    process.exit(1);
  }
  if (!secret) {
    console.warn('تحذير: WHATSAPP_EVENTS_WEBHOOK_SECRET فارغ — الـ events سترفض الطلبات.');
  }

  console.log('Webhook URL:', webhookUrl);
  const listRes = await fetch(`${evoBase}/instance/fetchInstances`, {
    headers: { apikey: evoKey },
  });
  if (!listRes.ok) {
    console.error('fetchInstances failed', listRes.status, await listRes.text());
    process.exit(1);
  }
  const list = await listRes.json();
  const instances = (Array.isArray(list) ? list : [list]).map((i) =>
    i?.name || i?.instanceName || i?.instance?.instanceName || i?.instance?.name,
  ).filter(Boolean);

  console.log(`instances: ${instances.length}`);
  const payload = {
    webhook: {
      enabled: true,
      url: webhookUrl,
      webhookByEvents: false,
      webhookBase64: false,
      events: ['CONNECTION_UPDATE', 'MESSAGES_UPDATE', 'SEND_MESSAGE'],
      headers: secret ? { 'x-webhook-secret': secret } : undefined,
    },
  };

  for (const name of instances) {
    const res = await fetch(`${evoBase}/webhook/set/${name}`, {
      method: 'POST',
      headers: { apikey: evoKey, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const body = await res.text();
    console.log(`${name}: HTTP ${res.status} ${body.slice(0, 160)}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
