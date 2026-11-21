/** Safe relative path for post-login navigation (no open redirect). */
export function safeAdminNextPath(raw: string | null | undefined): string {
  const next = (raw ?? "").trim() || "/";
  if (!next.startsWith("/") || next.startsWith("//")) return "/";
  if (next.includes("\\") || next.includes("://")) return "/";
  if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(next)) return "/";
  return next;
}
