/**
 * اختيار WhatsAppProvider حسب معرف النقل — بدون معرفة منطق الأعمال.
 * ملاحظة: `dualhook` = رقم نابو الرسمي عبر Meta (SHARED_SENDER)، ليس API Dualhook.
 */

import type { TransportProviderId, WhatsAppProvider } from './types.ts';
import { dualhookTransport } from './dualhook_transport.ts';
import { ycloudTransport } from './ycloud_transport.ts';
import { metaCloudTransport } from './meta_cloud_transport.ts';

export function getWhatsAppProvider(
  id: TransportProviderId,
): WhatsAppProvider | null {
  if (id === 'dualhook') return dualhookTransport;
  if (id === 'ycloud') return ycloudTransport;
  if (id === 'cloud_api') return metaCloudTransport;
  // waha / evolution / whats360 تبقى على المسارات الحالية في index.ts
  // حتى تُغلَّف بالكامل كـ transports.
  return null;
}

export function parseTransportId(raw: unknown): TransportProviderId {
  const v = String(raw ?? '').trim().toLowerCase();
  if (
    v === 'evolution' ||
    v === 'cloud_api' ||
    v === 'waha' ||
    v === 'whats360' ||
    v === 'ycloud' ||
    v === 'dualhook'
  ) {
    return v;
  }
  return 'waha';
}

/** مزودات Cloud الرسمية (قوالب Meta). */
export function isOfficialTemplateTransport(id: string): boolean {
  return id === 'dualhook' || id === 'ycloud' || id === 'cloud_api';
}
