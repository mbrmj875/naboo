import { NextResponse } from "next/server";
import { getClientIpFromRequest } from "@/lib/client-ip";
import { verifyPassword } from "@/lib/field-auth";
import { findRepByUsername } from "@/lib/field-db";
import {
  clearFieldLoginFailures,
  recordFieldLoginFailure,
} from "@/lib/field-login-rate-limit";
import { FIELD_MESSAGES } from "@/lib/field-messages";
import { setPwdVersionCache } from "@/lib/field-pwdver-cache";
import { FieldLoginSchema } from "@/lib/field-schemas";
import {
  createFieldSessionToken,
  fieldCookieName,
} from "@/lib/field-session";

export async function POST(req: Request) {
  try {
    const ip = getClientIpFromRequest(req);
    const body = await req.json();
    const parsed = FieldLoginSchema.safeParse(body);
    if (!parsed.success) {
      return NextResponse.json(
        {
          error: FIELD_MESSAGES.VALIDATION_ERROR,
          code: "VALIDATION_ERROR",
          errors: parsed.error.flatten().fieldErrors,
        },
        { status: 400 },
      );
    }

    const username = parsed.data.username.trim().toLowerCase();

    const rep = await findRepByUsername(username);
    if (!rep || !rep.is_active) {
      const rl = recordFieldLoginFailure(ip, username);
      if (!rl.ok) {
        return NextResponse.json(
          { error: FIELD_MESSAGES.RATE_LIMITED, code: "RATE_LIMITED" },
          {
            status: 429,
            headers: { "Retry-After": String(rl.retryAfterSec) },
          },
        );
      }
      return NextResponse.json(
        { error: FIELD_MESSAGES.LOGIN_FAILED, code: "LOGIN_FAILED" },
        { status: 401 },
      );
    }

    const valid = await verifyPassword(parsed.data.password, rep.password_hash);
    if (!valid) {
      const rl = recordFieldLoginFailure(ip, username);
      if (!rl.ok) {
        return NextResponse.json(
          { error: FIELD_MESSAGES.RATE_LIMITED, code: "RATE_LIMITED" },
          {
            status: 429,
            headers: { "Retry-After": String(rl.retryAfterSec) },
          },
        );
      }
      return NextResponse.json(
        { error: FIELD_MESSAGES.LOGIN_FAILED, code: "LOGIN_FAILED" },
        { status: 401 },
      );
    }

    clearFieldLoginFailures(ip, username);
    setPwdVersionCache(rep.id, rep.password_version);
    const token = await createFieldSessionToken(rep.id, rep.password_version);
    const res = NextResponse.json({
      ok: true,
      rep: {
        id: rep.id,
        username: rep.username,
        display_name: rep.display_name,
      },
    });
    res.cookies.set(fieldCookieName(), token, {
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
