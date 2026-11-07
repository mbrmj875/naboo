/**
 * cron: إرسال PDF بطاقة الغيار المستحق بعد 5 دقائق صمت — Cloud API بلا نص.
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  asCard,
  processOilCardPdfJob,
  type OilCardPdfJobRow,
} from './send_job.ts';

const SESSION_WINDOW_MS = 24 * 60 * 60 * 1000;
const IDLE_MS = 5 * 60 * 1000;

function cronAuthorized(req: Request): boolean {
  const presented = (
    req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '') ??
      req.headers.get('x-cron-secret') ??
      ''
  ).trim();
  if (!presented) return false;
  const accepted = [
    Deno.env.get('CRON_SECRET')?.trim() ?? '',
    Deno.env.get('WHATSAPP_OPS_ANALYST_SECRET')?.trim() ?? '',
  ].filter((s) => s.length > 0);
  return accepted.includes(presented);
}

/** آخر رسالة زبون ≈ idle_after − 5 دقائق. النافذة المجانية 24 ساعة من تلك الرسالة. */
function sessionWindowFloor(now = Date.now()): string {
  return new Date(now - SESSION_WINDOW_MS + IDLE_MS).toISOString();
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405 });
  }
  if (!cronAuthorized(req)) {
    return new Response('Unauthorized', { status: 401 });
  }

  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const dueIso = new Date().toISOString();
  const windowFloor = sessionWindowFloor();
  await db
    .from('whatsapp_oil_card_pdf_jobs')
    .update({
      status: 'failed',
      last_error: 'session_window_closed',
      updated_at: dueIso,
    })
    .eq('status', 'pending')
    .lt('idle_after', windowFloor);

  const { data: rows, error } = await db
    .from('whatsapp_oil_card_pdf_jobs')
    .select(
      'id, tenant_user_id, order_ref, to_phone, phone_number_id, pdf_storage_path, card_payload, created_at',
    )
    .eq('status', 'pending')
    .lte('idle_after', dueIso)
    .gte('idle_after', windowFloor)
    .order('idle_after', { ascending: true })
    .limit(20);

  if (error) {
    return Response.json({ ok: false, error: error.message }, { status: 500 });
  }

  let sent = 0;
  let failed = 0;
  for (const raw of rows ?? []) {
    const job: OilCardPdfJobRow = {
      id: String(raw.id),
      tenant_user_id: String(raw.tenant_user_id),
      order_ref: String(raw.order_ref),
      to_phone: String(raw.to_phone ?? ''),
      phone_number_id: raw.phone_number_id
        ? String(raw.phone_number_id)
        : null,
      pdf_storage_path: raw.pdf_storage_path
        ? String(raw.pdf_storage_path)
        : null,
      card_payload: asCard(raw.card_payload),
      created_at: raw.created_at ? String(raw.created_at) : null,
    };
    try {
      const r = await processOilCardPdfJob(db, job);
      if (r === 'sent') sent += 1;
      else failed += 1;
    } catch (e) {
      failed += 1;
      console.warn('pdf job crashed', job.id, String(e).slice(0, 160));
    }
  }

  return Response.json({ ok: true, scanned: rows?.length ?? 0, sent, failed });
});
