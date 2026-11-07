/**
 * إرسال ملف بطاقة الغيار داخل نافذة الـ 24 ساعة.
 * يُستدعى من الـ cron بعد الصمت، أو فوراً إذا طلب الزبون الملف.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import {
  cloudSendDocument,
  cloudUploadMedia,
} from '../whatsapp-gateway/cloud_api.ts';
import { debitWalletForSend } from '../whatsapp-gateway/wallet.ts';
import {
  extractStoreBrandingFromTables,
  loadSnapshotTables,
  mapsUrlFromCoords,
} from '../whatsapp-cloud-webhook/tenant_ai_context.ts';
import {
  defaultPdfStoragePath,
  OIL_CARD_PDF_BUCKET,
} from '../whatsapp-cloud-webhook/pdf_jobs.ts';
import {
  buildFallbackOilCardPdf,
  formatInvoiceStamp,
  loadTajawalBold,
  loadTajawalRegular,
} from './build_pdf.ts';

export type OilCardPdfJobRow = {
  id: string;
  tenant_user_id: string;
  order_ref: string;
  to_phone: string;
  phone_number_id: string | null;
  pdf_storage_path: string | null;
  card_payload: Record<string, string> | null;
  created_at?: string | null;
};

const SENDABLE = ['awaiting_inbound', 'pending', 'sending'];

export function asCard(raw: unknown): Record<string, string> | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    const t = String(v ?? '').trim();
    if (t) out[k] = t;
  }
  return Object.keys(out).length ? out : null;
}

function phoneKeys(raw: string): string[] {
  const d = String(raw ?? '').replace(/\D/g, '');
  const keys = new Set<string>();
  if (d) keys.add(d);
  if (d.startsWith('964') && d.length > 3) keys.add(`0${d.slice(3)}`);
  if (d.startsWith('0') && d.length > 1) keys.add(`964${d.slice(1)}`);
  return [...keys];
}

async function downloadPdf(
  db: SupabaseClient,
  job: OilCardPdfJobRow,
): Promise<Uint8Array | null> {
  const candidates = [
    String(job.pdf_storage_path ?? '').trim(),
    defaultPdfStoragePath(job.tenant_user_id, job.order_ref),
  ].filter((p, i, all) => p.length > 0 && all.indexOf(p) === i);

  for (const path of candidates) {
    const { data, error } = await db.storage
      .from(OIL_CARD_PDF_BUCKET)
      .download(path);
    if (error || !data) continue;
    const buf = new Uint8Array(await data.arrayBuffer());
    if (buf.length > 0) return buf;
  }
  return null;
}

function decodeLogo(raw: unknown): Uint8Array | null {
  let b64 = String(raw ?? '').trim();
  const comma = b64.indexOf(',');
  if (b64.startsWith('data:') && comma >= 0) b64 = b64.slice(comma + 1);
  if (!b64) return null;
  try {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out.length > 32 ? out : null;
  } catch {
    return null;
  }
}

function logoFromPayload(raw: unknown): Uint8Array | null {
  let obj: Record<string, unknown> | null = null;
  if (typeof raw === 'string' && raw.trim()) {
    try {
      obj = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      return null;
    }
  } else if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    obj = raw as Record<string, unknown>;
  }
  if (!obj) return null;
  return decodeLogo(obj.storeLogoBase64);
}

function logoFromTables(
  tables: Record<string, Array<Record<string, unknown>>> | null,
  employeeName: string | null,
): Uint8Array | null {
  if (!tables) return null;
  const want = String(employeeName ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
  if (want) {
    for (const row of tables['user_profiles'] ?? []) {
      const display = String(row.displayName ?? '').trim().replace(/\s+/g, ' ').toLowerCase();
      const username = String(row.username ?? row.name ?? '').trim().replace(/\s+/g, ' ')
        .toLowerCase();
      if (display !== want && username !== want) continue;
      const logo = logoFromPayload(row.branchProfileJson);
      if (logo) return logo;
    }
  }
  const printRows = tables['print_settings'] ?? [];
  const row = printRows.find((r) => Number(r.id) === 1) ?? printRows[0];
  return logoFromPayload(row?.payload);
}

function cardFact(card: Record<string, string> | null, key: string): string | null {
  const s = String(card?.[key] ?? '').trim();
  if (!s || s === '-' || s === '—') return null;
  return s;
}

async function professionalPdf(
  db: SupabaseClient,
  job: OilCardPdfJobRow,
): Promise<Uint8Array | null> {
  const card = asCard(job.card_payload);
  try {
    const tables = await loadSnapshotTables(db, job.tenant_user_id, {
      timeoutMs: 8000,
    });
    const branding = tables
      ? extractStoreBrandingFromTables(tables, cardFact(card, 'employee'))
      : {
        storeName: null,
        storePhones: [] as string[],
        storeAddress: null,
        storeLatitude: null,
        storeLongitude: null,
      };
    const phones = branding.storePhones.length > 0
      ? branding.storePhones
      : [cardFact(card, 'store_phone')].filter((p): p is string => !!p);
    const address = branding.storeAddress ?? cardFact(card, 'store_address');
    const maps = mapsUrlFromCoords(branding.storeLatitude, branding.storeLongitude) ??
      cardFact(card, 'store_maps');
    const shopName = branding.storeName ??
      cardFact(card, 'store_name') ??
      cardFact(card, 'shop');
    if (!card && !shopName && !address && phones.length === 0) return null;
    const [fontBytes, boldFontBytes] = await Promise.all([
      loadTajawalRegular(),
      loadTajawalBold(),
    ]);
    return await buildFallbackOilCardPdf({
      fontBytes,
      boldFontBytes,
      logoBytes: logoFromTables(tables, cardFact(card, 'employee')),
      shopName,
      address,
      phones,
      mapsUrl: maps,
      issuedAt: formatInvoiceStamp(job.created_at),
      card,
    });
  } catch (e) {
    console.warn('professional pdf failed', String(e).slice(0, 160));
    return null;
  }
}

async function mark(
  db: SupabaseClient,
  id: string,
  patch: Record<string, unknown>,
): Promise<void> {
  await db.from('whatsapp_oil_card_pdf_jobs').update({
    ...patch,
    updated_at: new Date().toISOString(),
  }).eq('id', id);
}

export async function processOilCardPdfJob(
  db: SupabaseClient,
  job: OilCardPdfJobRow,
): Promise<'sent' | 'failed'> {
  const phoneId = String(job.phone_number_id ?? '').trim();
  const to = String(job.to_phone ?? '').replace(/\D/g, '');
  if (!phoneId || to.length < 10) {
    await mark(db, job.id, { status: 'failed', last_error: 'missing_phone' });
    return 'failed';
  }

  const claimed = await db
    .from('whatsapp_oil_card_pdf_jobs')
    .update({
      status: 'sending',
      updated_at: new Date().toISOString(),
    })
    .eq('id', job.id)
    .in('status', SENDABLE)
    .select('id')
    .maybeSingle();
  if (!claimed.data?.id) {
    const { data: current } = await db
      .from('whatsapp_oil_card_pdf_jobs')
      .select('status')
      .eq('id', job.id)
      .maybeSingle();
    return current?.status === 'sent' ? 'sent' : 'failed';
  }

  let bytes = await professionalPdf(db, job);
  if (!bytes) bytes = await downloadPdf(db, job);
  if (!bytes) {
    await mark(db, job.id, { status: 'failed', last_error: 'missing_pdf' });
    return 'failed';
  }

  const filename = `غيار-${job.order_ref}.pdf`;
  const uploaded = await cloudUploadMedia({
    userId: job.tenant_user_id,
    phoneNumberId: phoneId,
    bytes,
    mimeType: 'application/pdf',
    filename,
  });
  if (!uploaded.ok || !uploaded.mediaId) {
    await mark(db, job.id, {
      status: 'pending',
      last_error: uploaded.detail ?? 'upload_failed',
    });
    return 'failed';
  }

  const wallet = await debitWalletForSend(db, {
    tenantUserId: job.tenant_user_id,
    idempotencyKey: `pdf:${job.tenant_user_id}:${job.order_ref}`,
    provider: 'cloud_api',
    sendKind: 'oil_change_card_pdf',
  });
  if (!wallet.ok) {
    await mark(db, job.id, {
      status: 'failed',
      last_error: wallet.error ?? 'insufficient_balance',
    });
    return 'failed';
  }

  const sent = await cloudSendDocument({
    userId: job.tenant_user_id,
    phoneNumberId: phoneId,
    toE164Digits: to,
    mediaId: uploaded.mediaId,
    filename,
  });
  if (!sent.ok) {
    await mark(db, job.id, {
      status: 'pending',
      last_error: sent.detail ?? 'send_failed',
    });
    return 'failed';
  }

  await mark(db, job.id, {
    status: 'sent',
    sent_at: new Date().toISOString(),
    last_error: null,
  });

  try {
    await db.from('whatsapp_message_logs').insert({
      tenant_user_id: job.tenant_user_id,
      channel: 'whatsapp',
      provider: 'cloud_api',
      template_key: 'oil_change_card_pdf',
      to_phone: to,
      status: 'sent',
      provider_message_id: sent.messageId ?? null,
      order_ref: job.order_ref,
    });
  } catch (e) {
    console.warn('pdf send log failed', String(e).slice(0, 120));
  }

  return 'sent';
}

function rowFrom(raw: Record<string, unknown>): OilCardPdfJobRow {
  return {
    id: String(raw.id),
    tenant_user_id: String(raw.tenant_user_id),
    order_ref: String(raw.order_ref),
    to_phone: String(raw.to_phone ?? ''),
    phone_number_id: raw.phone_number_id ? String(raw.phone_number_id) : null,
    pdf_storage_path: raw.pdf_storage_path ? String(raw.pdf_storage_path) : null,
    card_payload: asCard(raw.card_payload),
    created_at: raw.created_at ? String(raw.created_at) : null,
  };
}

/** إرسال فوري عندما يطلب الزبون الملف. لا ينتظر دقائق الصمت. */
export async function sendOilCardPdfNow(
  db: SupabaseClient,
  args: {
    tenantUserId: string;
    orderRef?: string | null;
    toPhone: string;
    phoneNumberId: string;
  },
): Promise<'sent' | 'already' | 'missing' | 'failed'> {
  const tenant = args.tenantUserId.trim();
  const orderRef = String(args.orderRef ?? '').trim();
  const phones = phoneKeys(args.toPhone);
  if (!tenant || phones.length === 0) return 'missing';

  let query = db
    .from('whatsapp_oil_card_pdf_jobs')
    .select(
      'id, tenant_user_id, order_ref, to_phone, phone_number_id, pdf_storage_path, card_payload, status, created_at',
    )
    .eq('tenant_user_id', tenant)
    .order('updated_at', { ascending: false })
    .limit(1);
  if (orderRef) query = query.eq('order_ref', orderRef);
  else query = query.in('to_phone', phones);

  const { data, error } = await query.maybeSingle();
  if (error || !data) return 'missing';
  if (data.status === 'sent') return 'already';

  const job = rowFrom(data as Record<string, unknown>);
  const phoneId = String(args.phoneNumberId ?? '').trim();
  if (!job.phone_number_id && phoneId) job.phone_number_id = phoneId;
  if (phoneId && job.phone_number_id !== phoneId) {
    job.phone_number_id = phoneId;
  }
  const result = await processOilCardPdfJob(db, job);
  return result === 'sent' ? 'sent' : 'failed';
}
