import { SignJWT, jwtVerify } from "jose";

const COOKIE = "naboo_admin_session";

export function cookieName(): string {
  return COOKIE;
}

function getSecret(): Uint8Array {
  const s = process.env.NABOO_SESSION_SECRET;
  if (!s || s.length < 16) {
    throw new Error("NABOO_SESSION_SECRET must be set (min 16 chars)");
  }
  return new TextEncoder().encode(s);
}

export async function createSessionToken(): Promise<string> {
  return new SignJWT({ role: "admin" })
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("8h")
    .sign(getSecret());
}

export async function verifySessionToken(token: string | undefined): Promise<boolean> {
  if (!token) return false;
  try {
    await jwtVerify(token, getSecret());
    return true;
  } catch {
    return false;
  }
}
