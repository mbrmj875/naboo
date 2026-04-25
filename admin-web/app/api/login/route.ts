import { timingSafeEqual } from "crypto";
import { NextResponse } from "next/server";
import { createSessionToken, cookieName } from "@/lib/session";

function passwordsMatch(a: string, b: string): boolean {
  try {
    const ba = Buffer.from(a, "utf8");
    const bb = Buffer.from(b, "utf8");
    if (ba.length !== bb.length) return false;
    return timingSafeEqual(ba, bb);
  } catch {
    return false;
  }
}

export async function POST(req: Request) {
  try {
    const body = (await req.json()) as { password?: string };
    const password = body.password ?? "";
    const expected = process.env.NABOO_ADMIN_PASSWORD ?? "";
    if (!expected || !passwordsMatch(password, expected)) {
      return NextResponse.json({ error: "كلمة المرور غير صحيحة" }, { status: 401 });
    }
    const token = await createSessionToken();
    const res = NextResponse.json({ ok: true });
    res.cookies.set(cookieName(), token, {
      httpOnly: true,
      secure: process.env.NODE_ENV === "production",
      sameSite: "lax",
      path: "/",
      maxAge: 60 * 60 * 8,
    });
    return res;
  } catch (e) {
    const msg = e instanceof Error ? e.message : "خطأ";
    return NextResponse.json({ error: msg }, { status: 500 });
  }
}
