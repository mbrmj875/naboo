import type { FieldSyncOp, VisitHashPayload } from "@/lib/field-hash";
import { buildCanonicalObject } from "@/lib/field-hash";

/** Browser-safe sha256 matching server computeOperationHash */
export async function computeOperationHashClient(
  op: FieldSyncOp,
  payload: VisitHashPayload,
  visitId?: string | null,
): Promise<string> {
  const canonical = buildCanonicalObject(op, payload, visitId);
  const keys = Object.keys(canonical).sort();
  const ordered: Record<string, unknown> = {};
  for (const k of keys) ordered[k] = canonical[k];
  const json = JSON.stringify(ordered);
  const data = new TextEncoder().encode(json);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
