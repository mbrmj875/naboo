import { getSupabaseAdmin } from "@/lib/supabase-admin";

type CachedPwdVer = { ver: number; expiresAt: number };

const TTL_MS = 60_000;
const cache = new Map<string, CachedPwdVer>();

export async function getPwdVersionCached(repId: string): Promise<number> {
  const cached = cache.get(repId);
  if (cached && cached.expiresAt > Date.now()) {
    return cached.ver;
  }

  const { data, error } = await getSupabaseAdmin()
    .from("field_reps")
    .select("password_version")
    .eq("id", repId)
    .maybeSingle();

  if (error) throw error;
  const ver =
    typeof data?.password_version === "number" ? data.password_version : 1;
  cache.set(repId, { ver, expiresAt: Date.now() + TTL_MS });
  return ver;
}

export function invalidatePwdVersionCache(repId: string): void {
  cache.delete(repId);
}

export function setPwdVersionCache(repId: string, ver: number): void {
  cache.set(repId, { ver, expiresAt: Date.now() + TTL_MS });
}
