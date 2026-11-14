import type { SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1';
import type { SnapshotTables } from './types.ts';

/** يحمّل جداول SQLite من app_snapshots (أو الأجزاء المُجزّأة). */
export async function loadSnapshotTables(
  admin: SupabaseClient,
  userId: string,
): Promise<SnapshotTables | null> {
  const { data: snap, error } = await admin
    .from('app_snapshots')
    .select('payload')
    .eq('user_id', userId)
    .maybeSingle();

  if (error || !snap?.payload) return null;

  let payload = snap.payload as Record<string, unknown>;
  if (payload.chunked === true) {
    const syncId = String(payload.sync_id ?? '');
    if (!syncId) return null;
    payload = await loadChunkedPayload(admin, userId, syncId);
    if (!payload) return null;
  }

  const tables = payload.tables;
  if (!tables || typeof tables !== 'object') return null;
  return tables as SnapshotTables;
}

async function loadChunkedPayload(
  admin: SupabaseClient,
  userId: string,
  syncId: string,
): Promise<Record<string, unknown> | null> {
  const { data: chunks, error } = await admin
    .from('app_snapshot_chunks')
    .select('chunk_index, chunk_data')
    .eq('user_id', userId)
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
