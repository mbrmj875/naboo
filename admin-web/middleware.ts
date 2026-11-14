import { NextResponse, type NextRequest } from "next/server";
import { cookieName, verifySessionToken } from "@/lib/session";
import {
  fieldCookieName,
  verifyFieldSessionToken,
} from "@/lib/field-session";
import { withSecurityHeaders } from "@/lib/security-headers";

function isPublicMenuPath(pathname: string): boolean {
  return (
    pathname === "/m" ||
    pathname.startsWith("/m/") ||
    pathname.startsWith("/fonts/")
  );
}

function isFieldLoginPath(pathname: string): boolean {
  return (
    pathname === "/field/login" ||
    pathname.startsWith("/field/login/") ||
    pathname === "/api/field/login" ||
    pathname.startsWith("/api/field/login/")
  );
}

function isFieldApiPath(pathname: string): boolean {
  return pathname === "/api/field" || pathname.startsWith("/api/field/");
}

function isFieldAdminApiPath(pathname: string): boolean {
  return (
    pathname === "/api/field/admin" ||
    pathname.startsWith("/api/field/admin/")
  );
}

function isFieldAppPath(pathname: string): boolean {
  return pathname === "/field" || pathname.startsWith("/field/");
}

function applyFieldMapCsp(res: NextResponse): NextResponse {
  withSecurityHeaders(res);
  // المندوب يحتاج GPS + مايك للملاحظات الصوتية
  res.headers.set(
    "Permissions-Policy",
    "camera=(), microphone=(self), geolocation=(self)",
  );
  res.headers.set(
    "Content-Security-Policy",
    [
      "default-src 'self'",
      "script-src 'self' 'unsafe-inline'",
      "style-src 'self' 'unsafe-inline'",
      "img-src 'self' data: blob: https://*.tile.openstreetmap.org https://tile.openstreetmap.org",
      "connect-src 'self' https://*.tile.openstreetmap.org https://tile.openstreetmap.org https://nominatim.openstreetmap.org",
      "media-src 'self' blob:",
      "font-src 'self'",
      "worker-src 'self' blob:",
      "frame-ancestors 'none'",
      "base-uri 'self'",
      "form-action 'self'",
    ].join("; "),
  );
  return res;
}

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (isPublicMenuPath(pathname)) {
    const res = NextResponse.next();
    withSecurityHeaders(res);
    res.headers.set("Cross-Origin-Resource-Policy", "cross-origin");
    res.headers.set(
      "Strict-Transport-Security",
      "max-age=63072000; includeSubDomains; preload",
    );
    res.headers.set(
      "Content-Security-Policy",
      [
        "default-src 'self'",
        "img-src 'self' data: blob: https://*.supabase.co https://naboo.fun",
        "font-src 'self'",
        "style-src 'self' 'unsafe-inline'",
        "script-src 'self' 'unsafe-inline'",
        "connect-src 'self' https://*.supabase.co wss://*.supabase.co",
        "frame-ancestors 'none'",
        "base-uri 'self'",
        "form-action 'self'",
      ].join("; "),
    );
    return res;
  }

  if (pathname.startsWith("/login") || pathname.startsWith("/api/login")) {
    return withSecurityHeaders(NextResponse.next());
  }

  if (isFieldLoginPath(pathname) || pathname === "/api/field/logout") {
    return applyFieldMapCsp(NextResponse.next());
  }

  if (
    pathname === "/api/ops/whatsapp-webhook" ||
    pathname.startsWith("/api/ops/whatsapp-webhook/") ||
    pathname === "/api/ops/channels/ingress" ||
    pathname.startsWith("/api/ops/channels/ingress/")
  ) {
    return withSecurityHeaders(NextResponse.next());
  }

  const isKnownStaticAsset =
    pathname.startsWith("/_next") ||
    pathname.startsWith("/favicon") ||
    pathname.startsWith("/fonts/") ||
    /\.(?:ico|png|jpe?g|gif|svg|webp|css|js|map|woff2?|ttf|txt|html)$/i.test(
      pathname,
    );

  if (isKnownStaticAsset && !pathname.startsWith("/api/")) {
    return withSecurityHeaders(NextResponse.next());
  }

  // Field APIs (غير admin): المصادقة داخل الـ route بجلسة المندوب
  if (isFieldApiPath(pathname) && !isFieldAdminApiPath(pathname)) {
    return applyFieldMapCsp(NextResponse.next());
  }

  // صفحات المندوب: جلسة field مطلوبة
  if (isFieldAppPath(pathname)) {
    let fieldOk = false;
    try {
      const payload = await verifyFieldSessionToken(
        request.cookies.get(fieldCookieName())?.value,
      );
      fieldOk = payload != null;
    } catch {
      fieldOk = false;
    }
    if (!fieldOk) {
      const url = request.nextUrl.clone();
      url.pathname = "/field/login";
      url.searchParams.set("next", pathname);
      return applyFieldMapCsp(NextResponse.redirect(url));
    }
    return applyFieldMapCsp(NextResponse.next());
  }

  let ok = false;
  try {
    ok = await verifySessionToken(request.cookies.get(cookieName())?.value);
  } catch {
    ok = false;
  }

  if (pathname.startsWith("/api/")) {
    if (!ok) {
      return withSecurityHeaders(
        NextResponse.json({ error: "غير مصرّح" }, { status: 401 }),
      );
    }
    return withSecurityHeaders(NextResponse.next());
  }

  if (!ok) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return withSecurityHeaders(NextResponse.redirect(url));
  }

  return withSecurityHeaders(NextResponse.next());
}

export const config = {
  matcher: [
    "/",
    "/login",
    "/login/:path*",
    "/accounts",
    "/accounts/:path*",
    "/licenses",
    "/licenses/:path*",
    "/settings",
    "/settings/:path*",
    "/support",
    "/support/:path*",
    "/inbox",
    "/inbox/:path*",
    "/channels",
    "/channels/:path*",
    "/market/:path*",
    "/reps",
    "/reps/:path*",
    "/field",
    "/field/:path*",
    "/api/:path*",
    "/m",
    "/m/:path*",
    "/fonts/:path*",
  ],
};
