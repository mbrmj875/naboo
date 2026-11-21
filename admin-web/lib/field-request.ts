import { cookies } from "next/headers";
import { NextResponse } from "next/server";
import {
  fieldCookieName,
  verifyFieldSessionToken,
  type FieldSessionPayload,
} from "@/lib/field-session";
import { cookieName, verifySessionToken } from "@/lib/session";
import {
  getPwdVersionCached,
} from "@/lib/field-pwdver-cache";
import { FIELD_MESSAGES } from "@/lib/field-messages";

export async function readFieldSessionFromCookies(): Promise<FieldSessionPayload | null> {
  const jar = await cookies();
  return verifyFieldSessionToken(jar.get(fieldCookieName())?.value);
}

export async function requireFieldSession(): Promise<
  | { ok: true; session: FieldSessionPayload }
  | { ok: false; response: NextResponse }
> {
  const session = await readFieldSessionFromCookies();
  if (!session) {
    return {
      ok: false,
      response: NextResponse.json(
        { error: FIELD_MESSAGES.UNAUTHORIZED, code: "UNAUTHORIZED" },
        { status: 401 },
      ),
    };
  }

  const pwdVer = await getPwdVersionCached(session.repId);
  if (session.pwdVer !== pwdVer) {
    return {
      ok: false,
      response: NextResponse.json(
        {
          error: FIELD_MESSAGES.SESSION_INVALIDATED,
          code: "SESSION_INVALIDATED",
        },
        { status: 401 },
      ),
    };
  }

  return { ok: true, session };
}

export async function requireAdminSession(): Promise<
  | { ok: true }
  | { ok: false; response: NextResponse }
> {
  const jar = await cookies();
  const ok = await verifySessionToken(jar.get(cookieName())?.value);
  if (!ok) {
    return {
      ok: false,
      response: NextResponse.json(
        { error: FIELD_MESSAGES.UNAUTHORIZED, code: "UNAUTHORIZED" },
        { status: 401 },
      ),
    };
  }
  return { ok: true };
}

/** health: مندوب أو أدمن */
export async function requireFieldOrAdminSession(): Promise<
  | { ok: true; kind: "field" | "admin" }
  | { ok: false; response: NextResponse }
> {
  const jar = await cookies();
  const adminOk = await verifySessionToken(jar.get(cookieName())?.value);
  if (adminOk) return { ok: true, kind: "admin" };

  const field = await verifyFieldSessionToken(jar.get(fieldCookieName())?.value);
  if (field) {
    const pwdVer = await getPwdVersionCached(field.repId);
    if (field.pwdVer !== pwdVer) {
      return {
        ok: false,
        response: NextResponse.json(
          {
            error: FIELD_MESSAGES.SESSION_INVALIDATED,
            code: "SESSION_INVALIDATED",
          },
          { status: 401 },
        ),
      };
    }
    return { ok: true, kind: "field" };
  }

  return {
    ok: false,
    response: NextResponse.json(
      { error: FIELD_MESSAGES.UNAUTHORIZED, code: "UNAUTHORIZED" },
      { status: 401 },
    ),
  };
}
