import { createPrivateKey } from "node:crypto";
import { SignJWT, importPKCS8 } from "jose";

/**
 * يقرأ PEM لـ RSA (PKCS#1 أو PKCS#8) من متغير البيئة ويُحوّله لمفتاح يوقّع به jose.
 */
export async function importRsaPrivateKeyFromPem(pemRaw: string): Promise<CryptoKey> {
  const pem = pemRaw.replace(/\\n/g, "\n").trim();
  if (!pem.includes("BEGIN") || !pem.includes("PRIVATE KEY")) {
    throw new Error("LICENSE_JWT_PRIVATE_KEY_PEM: PEM غير صالح");
  }
  const nodeKey = createPrivateKey({ key: pem, format: "pem" });
  const pkcs8 = nodeKey.export({ type: "pkcs8", format: "pem" });
  if (typeof pkcs8 !== "string") {
    throw new Error("LICENSE_JWT_PRIVATE_KEY_PEM: تعذر تصدير PKCS#8");
  }
  return importPKCS8(pkcs8, "RS256");
}

export type LicenseJwtClaimsInput = {
  tenantId: string;
  plan: string;
  maxDevices: number;
  startsAt: Date;
  endsAt: Date;
  licenseId: string;
  isTrial: boolean;
  issuedAt: Date;
};

/** يطابق مطالبات `LicenseToken.fromJwt` في تطبيق Flutter. */
export async function signLicenseJwt(params: {
  privateKey: CryptoKey;
  kid: string;
  claims: LicenseJwtClaimsInput;
}): Promise<string> {
  const c = params.claims;
  const payload = {
    tenant_id: c.tenantId,
    plan: c.plan,
    max_devices: c.maxDevices,
    starts_at: c.startsAt.toISOString(),
    ends_at: c.endsAt.toISOString(),
    license_id: c.licenseId,
    is_trial: c.isTrial,
    issued_at: c.issuedAt.toISOString(),
  };
  return new SignJWT(payload)
    .setProtectedHeader({ alg: "RS256", typ: "JWT", kid: params.kid })
    .sign(params.privateKey);
}
