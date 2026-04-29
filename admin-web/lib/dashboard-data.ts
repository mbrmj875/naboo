import type { User } from "@supabase/supabase-js";
import { getSupabaseAdmin } from "./supabase-admin";

const TRIAL_DAYS = 15;

export type ProfileRow = {
  id: string;
  email: string | null;
  trial_started_at: string | null;
  custom_message_title_ar?: string | null;
  custom_message_body_ar?: string | null;
  custom_message_active?: boolean | null;
  custom_message_updated_at?: string | null;
  updated_at: string | null;
};

export type DeviceRow = {
  id: number;
  user_id: string;
  device_id: string;
  device_name: string;
  platform: string | null;
  last_seen_at: string;
  created_at: string;
  access_status?: string | null;
};

export type LicenseRow = {
  /** مفتاح أساسي في PostgreSQL إن وُجد */
  db_id: number | null;
  license_key: string;
  status: string | null;
  business_name: string | null;
  plan: string | null;
  max_devices: number | null;
  expires_at: string | null;
  trial_started_at?: string | null;
  registered_devices?: Record<string, unknown> | null;
  /** حقل اختياري من DB: ربط إداري بالحساب في Auth */
  assigned_user_id: string | null;
  assigned_user_email: string | null;
  /** فرق بالأيام التقريبية حتى expires_at؛ سالب إن انتهى؛ null إن لا يوجد تاريخ */
  expires_days_left: number | null;
};

/** لقطة مزامنة واحدة لكل مستخدم عادةً — بدون حمولة في القائمة لتفادي البطء */
export type SnapshotRow = {
  id: number;
  user_id: string;
  device_label: string | null;
  schema_version: number | null;
  updated_at: string;
};

/** أجزاء لقطة مجزّأة (ملفات كبيرة) — بدون نص الجزء في القائمة */
export type ChunkRow = {
  id: number;
  user_id: string;
  sync_id: string;
  chunk_index: number;
  updated_at: string;
};

/** يطابق مفاتيح JSON في عمود app_remote_config.config */
export type AppRemoteConfigPayload = {
  maintenance_mode: boolean;
  maintenance_message_ar: string;
  sync_paused_globally: boolean;
  sync_paused_message_ar: string;
  min_supported_version: string;
  latest_version: string;
  update_message_ar: string;
  force_update: boolean;
  update_download_url: string;
  /** إعلان لأي مناسبة — يظهر في التطبيق عند تغيير العنوان/النص/الرابط */
  announcement_title_ar: string;
  announcement_body_ar: string;
  announcement_url: string;
};

export function defaultAppRemoteConfig(): AppRemoteConfigPayload {
  return {
    maintenance_mode: false,
    maintenance_message_ar: "",
    sync_paused_globally: false,
    sync_paused_message_ar: "المزامنة موقوفة مؤقتاً من الخادم.",
    min_supported_version: "1.0.0",
    latest_version: "2.0.1",
    update_message_ar: "",
    force_update: false,
    update_download_url: "",
    announcement_title_ar: "",
    announcement_body_ar: "",
    announcement_url: "",
  };
}

function parseRemoteConfig(raw: unknown): AppRemoteConfigPayload {
  const d = defaultAppRemoteConfig();
  if (!raw || typeof raw !== "object") return d;
  const o = raw as Record<string, unknown>;
  const b = (k: string) => o[k] === true;
  const s = (k: string) => (o[k] != null ? String(o[k]).trim() : "");
  return {
    maintenance_mode: b("maintenance_mode"),
    maintenance_message_ar: s("maintenance_message_ar"),
    sync_paused_globally: b("sync_paused_globally"),
    sync_paused_message_ar: s("sync_paused_message_ar") || d.sync_paused_message_ar,
    min_supported_version: s("min_supported_version") || d.min_supported_version,
    latest_version: s("latest_version") || d.latest_version,
    update_message_ar: s("update_message_ar"),
    force_update: b("force_update"),
    update_download_url: s("update_download_url"),
    announcement_title_ar: s("announcement_title_ar"),
    announcement_body_ar: s("announcement_body_ar"),
    announcement_url: s("announcement_url"),
  };
}

export type UserRow = {
  id: string;
  email: string | null;
  phone: string | null;
  created_at: string;
  last_sign_in_at: string | null;
  providers: string;
  display_name: string | null;
  trial_started_at: string | null;
  profile_updated_at: string | null;
  trial_ends_at: string | null;
  trial_days_left: number | null;
  /** إن وُجد: المستخدم ممنوع حتى هذا التاريخ (UTC) */
  banned_until: string | null;
  /** عدد سجلات الجهاز في جدول account_devices لهذا الحساب */
  linked_devices_count: number;
  custom_message_title_ar: string | null;
  custom_message_body_ar: string | null;
  custom_message_active: boolean;
  custom_message_updated_at: string | null;
};

/** ملخص للوحة الاشتراكات (من صفوف خام قبل إخفاء المفتاح). */
export type LicenseSummaryRow = {
  total: number;
  byStatus: Record<string, number>;
  byPlan: Record<string, number>;
  activePaid: number;
  expiringWithinWeek: number;
};

function buildLicenseSummary(rawRows: Record<string, unknown>[]): LicenseSummaryRow {
  const byStatus: Record<string, number> = {};
  const byPlan: Record<string, number> = {};
  let activePaid = 0;
  let expiringWithinWeek = 0;
  const now = Date.now();
  const weekMs = 7 * 86400000;

  for (const r of rawRows) {
    const st = String(r.status ?? "—");
    const pl = String(r.plan ?? "—");
    byStatus[st] = (byStatus[st] ?? 0) + 1;
    byPlan[pl] = (byPlan[pl] ?? 0) + 1;
    if (st === "active") {
      activePaid += 1;
      const expStr = r.expires_at as string | null | undefined;
      if (expStr) {
        try {
          const exp = new Date(expStr).getTime();
          if (exp >= now && exp - now <= weekMs) expiringWithinWeek += 1;
        } catch {
          /* ignore */
        }
      }
    }
  }

  return {
    total: rawRows.length,
    byStatus,
    byPlan,
    activePaid,
    expiringWithinWeek,
  };
}

function maskLicenseKey(key: string): string {
  const k = key.trim();
  if (k.length <= 8) return "****";
  return `${k.slice(0, 4)}…${k.slice(-4)}`;
}

/** فرق بالأيام حتى تاريخ ISO؛ سالب بعد المرور. */
function expiresDaysLeft(iso: string | null | undefined): number | null {
  if (iso == null || iso === "") return null;
  try {
    const end = new Date(iso).getTime();
    if (Number.isNaN(end)) return null;
    return Math.ceil((end - Date.now()) / 86400000);
  } catch {
    return null;
  }
}

function userProviders(u: User): string {
  const ids = u.identities?.map((i) => i.provider).filter(Boolean) ?? [];
  return [...new Set(ids)].join(", ") || "—";
}

function displayNameFromUser(u: User): string | null {
  const m = u.user_metadata as Record<string, unknown> | undefined;
  if (!m) return null;
  const full = m["full_name"];
  const name = m["name"];
  if (typeof full === "string" && full.trim()) return full.trim();
  if (typeof name === "string" && name.trim()) return name.trim();
  return null;
}

export async function loadDashboardData(): Promise<{
  users: UserRow[];
  devices: DeviceRow[];
  licenses: LicenseRow[];
  licenseSummary: LicenseSummaryRow;
  snapshots: SnapshotRow[];
  snapshotChunks: ChunkRow[];
  remoteConfig: AppRemoteConfigPayload;
  remoteConfigUpdatedAt: string | null;
  errors: string[];
  fetchedAt: string;
}> {
  const supabase = getSupabaseAdmin();
  const errors: string[] = [];
  const fetchedAt = new Date().toISOString();

  const users: User[] = [];
  let page = 1;
  const perPage = 200;
  for (;;) {
    const { data, error } = await supabase.auth.admin.listUsers({
      page,
      perPage,
    });
    if (error) {
      errors.push(`قائمة المستخدمين: ${error.message}`);
      break;
    }
    const batch = data.users;
    users.push(...batch);
    if (batch.length < perPage) break;
    page += 1;
    if (page > 50) break;
  }

  const authEmailByUserId = new Map<string, string>();
  for (const u of users) {
    const em = u.email?.trim();
    if (em) authEmailByUserId.set(u.id, em);
  }

  let profiles: Record<string, unknown>[] | null = null;
  let pErr: { message: string } | null = null;
  {
    const q1 = await supabase
      .from("profiles")
      .select(
        "id,email,trial_started_at,custom_message_title_ar,custom_message_body_ar,custom_message_active,custom_message_updated_at,updated_at",
      );
    profiles = q1.data as Record<string, unknown>[] | null;
    pErr = q1.error;
    if (
      pErr?.message?.includes("column") &&
      pErr.message.includes("custom_message_title_ar")
    ) {
      const qFallback = await supabase
        .from("profiles")
        .select("id,email,trial_started_at,updated_at");
      profiles = qFallback.data as Record<string, unknown>[] | null;
      pErr = qFallback.error;
      errors.push(
        "لا توجد أعمدة الرسالة المخصصة — نفّذ admin-web/supabase/profiles_custom_message.sql.",
      );
    }
  }

  if (pErr) errors.push(`profiles: ${pErr.message}`);

  const profileById = new Map<string, ProfileRow>();
  for (const row of profiles ?? []) {
    profileById.set(row.id as string, row as ProfileRow);
  }

  const userRows: UserRow[] = users.map((u) => {
    const p = profileById.get(u.id);
    let trialEnds: string | null = null;
    let daysLeft: number | null = null;
    const ts = p?.trial_started_at;
    if (ts) {
      const start = new Date(ts);
      const end = new Date(start);
      end.setUTCDate(end.getUTCDate() + TRIAL_DAYS);
      trialEnds = end.toISOString();
      const now = Date.now();
      const ms = end.getTime() - now;
      daysLeft = ms <= 0 ? 0 : Math.ceil(ms / 86400000);
    }
    return {
      id: u.id,
      email: u.email ?? p?.email ?? null,
      phone: u.phone ?? null,
      created_at: u.created_at,
      last_sign_in_at: u.last_sign_in_at ?? null,
      providers: userProviders(u),
      display_name: displayNameFromUser(u),
      trial_started_at: p?.trial_started_at ?? null,
      profile_updated_at: p?.updated_at ?? null,
      trial_ends_at: trialEnds,
      trial_days_left: daysLeft,
      banned_until: u.banned_until ?? null,
      linked_devices_count: 0,
      custom_message_title_ar: p?.custom_message_title_ar ?? null,
      custom_message_body_ar: p?.custom_message_body_ar ?? null,
      custom_message_active: p?.custom_message_active == true,
      custom_message_updated_at: p?.custom_message_updated_at ?? null,
    };
  });

  userRows.sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime(),
  );

  /** عدد الأجهزة لكل حساب (من عمود user_id)، للدقة خارج حد قائمة الجدول. */
  let linkedDeviceCountByUser = new Map<string, number>();
  {
    const { data: idsOnly, error: dcErr } = await supabase
      .from("account_devices")
      .select("user_id");
    if (dcErr) errors.push(`account_devices (عدّ الأجهزة): ${dcErr.message}`);
    for (const r of idsOnly ?? []) {
      const uid = String((r as { user_id: string }).user_id ?? "");
      if (!uid) continue;
      linkedDeviceCountByUser.set(uid, (linkedDeviceCountByUser.get(uid) ?? 0) + 1);
    }
  }

  const userRowsWithDevices: UserRow[] = userRows.map((row) => ({
    ...row,
    linked_devices_count: linkedDeviceCountByUser.get(row.id) ?? 0,
  }));

  const { data: devices, error: dErr } = await supabase
    .from("account_devices")
    .select(
      "id,user_id,device_id,device_name,platform,last_seen_at,created_at,access_status",
    )
    .order("last_seen_at", { ascending: false })
    .limit(500);

  if (dErr) errors.push(`account_devices: ${dErr.message}`);

  let licenseRows: Record<string, unknown>[] | null = null;
  let lErr: { message: string } | null = null;
  {
    const qFull = await supabase
      .from("licenses")
      .select(
        "id,license_key,status,business_name,plan,max_devices,expires_at,trial_started_at,registered_devices,assigned_user_id",
      )
      .order("license_key", { ascending: true })
      .limit(500);
    licenseRows = qFull.data as Record<string, unknown>[] | null;
    lErr = qFull.error;

    const msgNoCol = (e: typeof lErr, col: string) =>
      !!(e?.message?.includes("column") && e.message.includes(col));

    if (lErr && msgNoCol(lErr, "assigned_user_id")) {
      const qFallback = await supabase
        .from("licenses")
        .select(
          "id,license_key,status,business_name,plan,max_devices,expires_at,trial_started_at,registered_devices",
        )
        .order("license_key", { ascending: true })
        .limit(500);
      licenseRows = qFallback.data as Record<string, unknown>[] | null;
      lErr = qFallback.error;
      errors.push(
        "لم يُعثر على عمود assigned_user_id — نفّذ admin-web/supabase/licenses_assigned_user_id.sql من لوحة Supabase.",
      );
    }

    if (lErr?.message?.includes("column") && lErr.message.includes("id")) {
      const q2 = await supabase
        .from("licenses")
        .select(
          "license_key,status,business_name,plan,max_devices,expires_at,trial_started_at,registered_devices",
        )
        .order("license_key", { ascending: true })
        .limit(500);
      licenseRows = q2.data as Record<string, unknown>[] | null;
      lErr = q2.error;
    }
  }

  if (lErr) errors.push(`licenses: ${lErr.message}`);

  const { data: snapRows, error: sErr } = await supabase
    .from("app_snapshots")
    .select("id,user_id,device_label,schema_version,updated_at")
    .order("updated_at", { ascending: false })
    .limit(500);

  if (sErr) errors.push(`app_snapshots: ${sErr.message}`);

  const { data: chunkRows, error: cErr } = await supabase
    .from("app_snapshot_chunks")
    .select("id,user_id,sync_id,chunk_index,updated_at")
    .order("updated_at", { ascending: false })
    .limit(800);

  if (cErr) errors.push(`app_snapshot_chunks: ${cErr.message}`);

  let remoteConfig = defaultAppRemoteConfig();
  let remoteConfigUpdatedAt: string | null = null;
  const rcRes = await supabase
    .from("app_remote_config")
    .select("config,updated_at")
    .eq("id", 1)
    .maybeSingle();
  if (rcRes.error) {
    errors.push(`app_remote_config: ${rcRes.error.message}`);
  } else if (rcRes.data) {
    remoteConfig = parseRemoteConfig(rcRes.data.config);
    remoteConfigUpdatedAt =
      rcRes.data.updated_at != null ? String(rcRes.data.updated_at) : null;
  }

  const licenseSummary = buildLicenseSummary(licenseRows ?? []);

  const licenses: LicenseRow[] = (licenseRows ?? []).map((r) => {
    const rawId = r["id"];
    const dbId =
      typeof rawId === "number"
        ? rawId
        : typeof rawId === "string" && /^\d+$/.test(rawId)
          ? parseInt(rawId, 10)
          : null;
    const expIso = (r.expires_at as string) ?? null;
    const assignedRaw = r["assigned_user_id"];
    const assignedId =
      assignedRaw != null && String(assignedRaw).trim() !== ""
        ? String(assignedRaw)
        : null;
    return {
      db_id: dbId,
      license_key: maskLicenseKey(String(r.license_key ?? "")),
      status: (r.status as string) ?? null,
      business_name: (r.business_name as string) ?? null,
      plan: (r.plan as string) ?? null,
      max_devices:
        r.max_devices === null || r.max_devices === undefined
          ? null
          : Number(r.max_devices),
      expires_at: expIso,
      trial_started_at: (r.trial_started_at as string) ?? null,
      registered_devices:
        r.registered_devices && typeof r.registered_devices === "object"
          ? (r.registered_devices as Record<string, unknown>)
          : null,
      assigned_user_id: assignedId,
      assigned_user_email: assignedId
        ? authEmailByUserId.get(assignedId) ?? null
        : null,
      expires_days_left: expiresDaysLeft(expIso),
    };
  });

  return {
    users: userRowsWithDevices,
    devices: (devices ?? []) as DeviceRow[],
    licenses,
    licenseSummary,
    snapshots: (snapRows ?? []) as SnapshotRow[],
    snapshotChunks: (chunkRows ?? []) as ChunkRow[],
    remoteConfig,
    remoteConfigUpdatedAt,
    errors,
    fetchedAt,
  };
}
