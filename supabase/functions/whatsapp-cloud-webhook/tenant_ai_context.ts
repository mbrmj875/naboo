/**
 * حزمة سياق الرد الذكي لمستأجر واحد فقط.
 * كل قراءة مقيّدة بـ tenant_user_id — لا بيانات مشتركة بين المحلات.
 */

import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';

export type AllowlistedFacts = {
  /** حقول بطاقة الغيار المرتبطة بهذا الزبون. */
  card: Record<string, string> | null;
  storeName: string | null;
  storePhone: string | null;
  /** هاتف إضافي إن وُجد أكثر من رقم. */
  storePhones: string[];
  storeAddress: string | null;
  mapsUrl: string | null;
  employeeName: string | null;
  /** false عندما انتهت مهلة اللقطة أو غابت. لا يعني أن الإعدادات فارغة. */
  snapshotLoaded?: boolean;
};

export type StoreBranding = {
  storeName: string | null;
  storePhones: string[];
  storeAddress: string | null;
  storeLatitude: number | null;
  storeLongitude: number | null;
};

export type SnapshotTables = Record<string, Array<Record<string, unknown>>>;

function trimOrNull(raw: unknown): string | null {
  const s = String(raw ?? '').trim();
  if (!s || s === '-' || s === '—') return null;
  return s;
}

function phonesFromJson(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((e) => String(e ?? '').trim())
    .filter((e) => e.length > 0);
}

function coord(raw: unknown, limit: number): number | null {
  const n = typeof raw === 'number' ? raw : Number(raw);
  if (!Number.isFinite(n) || Math.abs(n) > limit) return null;
  return n;
}

export function mapsUrlFromCoords(
  lat: number | null,
  lng: number | null,
): string | null {
  if (lat == null || lng == null) return null;
  return `https://www.google.com/maps/search/?api=1&query=${lat},${lng}`;
}

/** يقرأ هوية المتجر من حمولة print_settings. */
export function parsePrintSettingsPayload(raw: unknown): StoreBranding {
  let obj: Record<string, unknown> = {};
  if (typeof raw === 'string' && raw.trim()) {
    try {
      obj = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      obj = {};
    }
  } else if (raw && typeof raw === 'object') {
    obj = raw as Record<string, unknown>;
  }
  return {
    storeName: trimOrNull(obj.storeTitleLine),
    storePhones: phonesFromJson(obj.storePhones),
    storeAddress: trimOrNull(obj.storeAddress),
    storeLatitude: coord(obj.storeLatitude, 90),
    storeLongitude: coord(obj.storeLongitude, 180),
  };
}

/** ملف فرع الموظف — يعلو المتجر العام إن وُجدت هوية. */
export function parseBranchProfile(raw: unknown): StoreBranding | null {
  let obj: Record<string, unknown> | null = null;
  if (typeof raw === 'string' && raw.trim()) {
    try {
      obj = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      return null;
    }
  } else if (raw && typeof raw === 'object') {
    obj = raw as Record<string, unknown>;
  }
  if (!obj) return null;
  const branding: StoreBranding = {
    storeName: trimOrNull(obj.storeTitleLine),
    storePhones: phonesFromJson(obj.storePhones),
    storeAddress: trimOrNull(obj.storeAddress),
    storeLatitude: coord(obj.storeLatitude, 90),
    storeLongitude: coord(obj.storeLongitude, 180),
  };
  const hasContact = !!branding.storeAddress ||
    branding.storePhones.length > 0 ||
    (branding.storeLatitude != null && branding.storeLongitude != null);
  if (!branding.storeName && !hasContact) return null;
  return branding;
}

function normalizeName(raw: string): string {
  return raw.trim().replace(/\s+/g, ' ').toLowerCase();
}

/** فرع الموظف يطابق اسم الفني على البطاقة إن وُجد. */
export function pickStaffBranchFromProfiles(
  profiles: Array<Record<string, unknown>>,
  employeeName: string | null,
): StoreBranding | null {
  const want = normalizeName(employeeName ?? '');
  if (!want) return null;
  for (const row of profiles) {
    const display = normalizeName(String(row.displayName ?? ''));
    const username = normalizeName(String(row.username ?? row.name ?? ''));
    if (display !== want && username !== want) continue;
    const branch = parseBranchProfile(row.branchProfileJson);
    if (branch) return branch;
  }
  return null;
}

const LEGACY_BRANCH_KEY_RE =
  /(?:^|:)staff\.branch_profile\.(g:[0-9a-f-]{36}|local:\d+)$/i;

/** ملفات فرع قديمة ما زالت في app_settings قبل اكتمال الترحيل إلى user_profiles. */
export function extractLegacyBranchProfilesFromAppSettings(
  rows: Array<Record<string, unknown>>,
): Array<{ storageKey: string; branding: StoreBranding }> {
  const out: Array<{ storageKey: string; branding: StoreBranding }> = [];
  for (const row of rows) {
    const key = String(row.key ?? '').trim();
    const m = key.match(LEGACY_BRANCH_KEY_RE);
    if (!m) continue;
    const branding = parseBranchProfile(row.value);
    if (!branding) continue;
    out.push({ storageKey: m[1].toLowerCase(), branding });
  }
  return out;
}

function profileMatchesEmployee(
  row: Record<string, unknown>,
  employeeName: string | null,
): boolean {
  const want = normalizeName(employeeName ?? '');
  if (!want) return false;
  const display = normalizeName(String(row.displayName ?? ''));
  const username = normalizeName(String(row.username ?? row.name ?? ''));
  return display === want || username === want;
}

/** يربط مفتاح app_settings بصف الموظف عبر global_id أو id المحلي. */
export function pickStaffBranchFromLegacyAppSettings(
  appSettings: Array<Record<string, unknown>>,
  profiles: Array<Record<string, unknown>>,
  employeeName: string | null,
): StoreBranding | null {
  const legacy = extractLegacyBranchProfilesFromAppSettings(appSettings);
  if (!legacy.length) return null;

  const want = normalizeName(employeeName ?? '');
  if (want) {
    for (const entry of legacy) {
      const matched = profiles.find((row) => {
        if (!profileMatchesEmployee(row, employeeName)) return false;
        const gid = String(row.global_id ?? row.globalId ?? '').trim()
          .toLowerCase();
        const localId = String(row.id ?? '').trim();
        if (entry.storageKey.startsWith('g:') && gid) {
          return entry.storageKey === `g:${gid}`;
        }
        if (entry.storageKey.startsWith('local:') && localId) {
          return entry.storageKey === `local:${localId}`;
        }
        return false;
      });
      if (matched) return entry.branding;
    }
  }

  // لا تخمّن بين فروع متعددة — فقط إن وُجد ملف واحد مملوء.
  if (legacy.length === 1) return legacy[0].branding;
  return null;
}

function mergeStoreBranding(
  base: StoreBranding,
  overlay: StoreBranding | null,
): StoreBranding {
  if (!overlay) return base;
  return {
    storeName: overlay.storeName ?? base.storeName,
    storePhones: overlay.storePhones.length > 0
      ? overlay.storePhones
      : base.storePhones,
    storeAddress: overlay.storeAddress ?? base.storeAddress,
    storeLatitude: overlay.storeLatitude ?? base.storeLatitude,
    storeLongitude: overlay.storeLongitude ?? base.storeLongitude,
  };
}

export function extractStoreBrandingFromTables(
  tables: SnapshotTables,
  employeeName: string | null,
): StoreBranding {
  const printRows = tables['print_settings'] ?? [];
  const printRow =
    printRows.find((r) => Number(r.id) === 1) ?? printRows[0] ?? null;
  const workspace = parsePrintSettingsPayload(printRow?.payload);

  const profiles = tables['user_profiles'] ?? [];
  const appSettings = tables['app_settings'] ?? [];
  const branch = pickStaffBranchFromProfiles(profiles, employeeName) ??
    pickStaffBranchFromLegacyAppSettings(appSettings, profiles, employeeName);

  return mergeStoreBranding(workspace, branch);
}

export function buildAllowlistedFacts(args: {
  card: Record<string, string> | null;
  branding: StoreBranding;
  employeeName: string | null;
}): AllowlistedFacts {
  const card = args.card;
  const shopFromCard = trimOrNull(card?.shop);
  const phones = args.branding.storePhones.filter((p) => p.trim().length > 0);
  return {
    card,
    storeName: args.branding.storeName ?? shopFromCard,
    storePhone: phones[0] ?? null,
    storePhones: phones,
    storeAddress: args.branding.storeAddress,
    mapsUrl: mapsUrlFromCoords(
      args.branding.storeLatitude,
      args.branding.storeLongitude,
    ),
    employeeName: trimOrNull(args.employeeName),
  };
}

/** أسطر تُمرَّر للنموذج — متجر فقط؛ البطاقة تُبنى في ai_reply. */
export function buildStoreFactLines(facts: AllowlistedFacts): string[] {
  const out: string[] = [];
  if (facts.storeName) out.push(`اسم المحل: ${facts.storeName}`);
  if (facts.storePhones.length > 0) {
    out.push(`هاتف المحل للتواصل: ${facts.storePhones.join(' / ')}`);
  }
  if (facts.storeAddress) out.push(`عنوان المحل: ${facts.storeAddress}`);
  if (facts.mapsUrl) out.push(`رابط موقع المحل على الخريطة: ${facts.mapsUrl}`);
  if (out.length > 0) {
    out.push(
      'قاعدة التواصل: إذا سأل الزبون عن الرقم أو العنوان أو الموقع، ' +
        'جاوبه فقط من الأسطر أعلاه ولا تخترع شيئاً غيرها.',
    );
  }
  return out;
}

/**
 * شعار المتجر داخل اللقطة يكبّر الملف. 1.8 ثانية كانت تُرجع فراغاً
 * فيُقال للزبون إن العنوان غير محفوظ وهو موجود في الإعدادات.
 */
const SNAPSHOT_LOAD_TIMEOUT_MS = 6500;

export async function loadSnapshotTables(
  db: SupabaseClient,
  tenantUserId: string,
  opts?: { timeoutMs?: number },
): Promise<SnapshotTables | null> {
  const timeoutMs = Math.max(
    400,
    Math.floor(opts?.timeoutMs ?? SNAPSHOT_LOAD_TIMEOUT_MS),
  );
  try {
    return await Promise.race([
      loadSnapshotTablesInner(db, tenantUserId),
      new Promise<null>((resolve) =>
        setTimeout(() => resolve(null), timeoutMs)
      ),
    ]);
  } catch (e) {
    console.warn('snapshot load failed', String(e).slice(0, 120));
    return null;
  }
}

async function loadSnapshotTablesInner(
  db: SupabaseClient,
  tenantUserId: string,
): Promise<SnapshotTables | null> {
  const { data: snap, error } = await db
    .from('app_snapshots')
    .select('payload')
    .eq('user_id', tenantUserId)
    .maybeSingle();

  if (error || !snap?.payload) return null;

  let payload = snap.payload as Record<string, unknown>;
  if (payload.chunked === true) {
    const syncId = String(payload.sync_id ?? '');
    if (!syncId) return null;
    const chunked = await loadChunkedPayload(db, tenantUserId, syncId);
    if (!chunked) return null;
    payload = chunked;
  }

  const tables = payload.tables;
  if (!tables || typeof tables !== 'object') return null;
  return tables as SnapshotTables;
}

async function loadChunkedPayload(
  db: SupabaseClient,
  tenantUserId: string,
  syncId: string,
): Promise<Record<string, unknown> | null> {
  const { data: chunks, error } = await db
    .from('app_snapshot_chunks')
    .select('chunk_index, chunk_data')
    .eq('user_id', tenantUserId)
    .eq('sync_id', syncId)
    .order('chunk_index', { ascending: true });

  if (error || !chunks?.length) return null;

  const b64 = chunks.map((c) => String(c.chunk_data ?? '')).join('');
  try {
    const jsonText = await decodeGzipBase64(b64);
    return JSON.parse(jsonText) as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function decodeGzipBase64(b64: string): Promise<string> {
  const raw = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  const stream = new Blob([raw]).stream().pipeThrough(
    new DecompressionStream('gzip'),
  );
  const buf = await new Response(stream).arrayBuffer();
  return new TextDecoder().decode(buf);
}

/**
 * يبني الحقائق المسموحة لهذا المستأجر والزبون.
 * البطاقة تأتي من إسناد الرسالة؛ المتجر من لقطة الحساب فقط.
 */
export async function buildTenantAiContext(
  db: SupabaseClient,
  args: {
    tenantUserId: string;
    card: Record<string, string> | null;
    employeeName: string | null;
    timeoutMs?: number;
  },
): Promise<AllowlistedFacts> {
  const tenantUserId = String(args.tenantUserId ?? '').trim();
  if (!tenantUserId) {
    return {
      ...buildAllowlistedFacts({
        card: args.card,
        branding: {
          storeName: null,
          storePhones: [],
          storeAddress: null,
          storeLatitude: null,
          storeLongitude: null,
        },
        employeeName: args.employeeName,
      }),
      snapshotLoaded: false,
    };
  }

  let branding: StoreBranding = {
    storeName: null,
    storePhones: [],
    storeAddress: null,
    storeLatitude: null,
    storeLongitude: null,
  };
  let snapshotLoaded = false;

  try {
    const tables = await loadSnapshotTables(db, tenantUserId, {
      timeoutMs: args.timeoutMs,
    });
    snapshotLoaded = tables != null;
    if (tables) {
      branding = extractStoreBrandingFromTables(tables, args.employeeName);
    }
  } catch (e) {
    console.warn('tenant ai context snapshot failed', String(e).slice(0, 160));
  }

  return {
    ...buildAllowlistedFacts({
      card: args.card,
      branding,
      employeeName: args.employeeName,
    }),
    snapshotLoaded,
  };
}
