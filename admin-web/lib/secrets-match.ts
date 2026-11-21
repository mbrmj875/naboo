import { timingSafeEqual } from "node:crypto";

/** Constant-time compare for shared secrets (utf8). Empty expected → false. */
export function secretsMatch(provided: string, expected: string): boolean {
  if (!expected) return false;
  const a = Buffer.from(provided, "utf8");
  const b = Buffer.from(expected, "utf8");
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}
