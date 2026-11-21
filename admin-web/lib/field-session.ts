import { SignJWT, jwtVerify, type JWTPayload } from "jose";

const COOKIE = "naboo_field_session";

export type FieldSessionPayload = {
  role: "field_rep";
  repId: string;
  pwdVer: number;
};

export function fieldCookieName(): string {
  return COOKIE;
}

function getSecret(): Uint8Array {
  const s = process.env.NABOO_SESSION_SECRET;
  if (!s || s.length < 16) {
    throw new Error("NABOO_SESSION_SECRET must be set (min 16 chars)");
  }
  return new TextEncoder().encode(s);
}

export async function createFieldSessionToken(
  repId: string,
  pwdVer: number,
): Promise<string> {
  return new SignJWT({
    role: "field_rep",
    repId,
    pwdVer,
  } satisfies FieldSessionPayload)
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("8h")
    .sign(getSecret());
}

export async function verifyFieldSessionToken(
  token: string | undefined,
): Promise<FieldSessionPayload | null> {
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, getSecret());
    if (payload.role !== "field_rep") return null;
    const repId = typeof payload.repId === "string" ? payload.repId : null;
    const pwdVer =
      typeof payload.pwdVer === "number" ? payload.pwdVer : null;
    if (!repId || pwdVer === null) return null;
    return { role: "field_rep", repId, pwdVer };
  } catch {
    return null;
  }
}

export function isFieldSessionPayload(
  payload: JWTPayload,
): payload is JWTPayload & FieldSessionPayload {
  return (
    payload.role === "field_rep" &&
    typeof payload.repId === "string" &&
    typeof payload.pwdVer === "number"
  );
}
