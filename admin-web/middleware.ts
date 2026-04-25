import { NextResponse, type NextRequest } from "next/server";
import { cookieName, verifySessionToken } from "@/lib/session";

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  if (pathname.startsWith("/login") || pathname.startsWith("/api/login")) {
    return NextResponse.next();
  }
  if (
    pathname.startsWith("/_next") ||
    pathname.startsWith("/favicon") ||
    (pathname.includes(".") && !pathname.startsWith("/api/"))
  ) {
    return NextResponse.next();
  }

  let ok = false;
  try {
    ok = await verifySessionToken(request.cookies.get(cookieName())?.value);
  } catch {
    ok = false;
  }

  if (pathname.startsWith("/api/")) {
    if (!ok) {
      return NextResponse.json({ error: "غير مصرّح" }, { status: 401 });
    }
    return NextResponse.next();
  }

  if (!ok) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("next", pathname);
    return NextResponse.redirect(url);
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/", "/login", "/api/:path*"],
};
