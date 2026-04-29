import { NextResponse } from "next/server";

/**
 * رؤوس أمان أساسية (OWASP)، من دون CSP صارمة لتجنّب كسر Next.js/HMR محلياً.
 */
export function withSecurityHeaders<T extends NextResponse>(res: T): T {
  res.headers.set("X-Frame-Options", "DENY");
  res.headers.set("X-Content-Type-Options", "nosniff");
  res.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  res.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  res.headers.set("Cross-Origin-Opener-Policy", "same-origin");
  res.headers.set(
    "Cross-Origin-Resource-Policy",
    process.env.NODE_ENV === "production" ? "same-site" : "cross-origin",
  );
  return res;
}
