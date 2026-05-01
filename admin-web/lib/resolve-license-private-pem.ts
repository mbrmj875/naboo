import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";

/** يوسّع ~ ويحوّل المسارات النسبية إلى مطلقة من cwd (مجلد تشغيل next). */
export function expandLicensePrivateKeyPath(raw: string): string {
  const t = raw.trim();
  if (t.startsWith("~/")) {
    return path.join(homedir(), t.slice(2));
  }
  if (t === "~") {
    return homedir();
  }
  if (!path.isAbsolute(t)) {
    return path.resolve(process.cwd(), t);
  }
  return t;
}

/**
 * يقرأ PEM الخاص للتوقيع: يفضّل الملف (PATH) ثم المتغير (PEM).
 * يطبّع `\n` الهاربة من .env ويدعم لصق PEM في سطر واحد بدون فواصل أسطر.
 */
export function resolveLicenseJwtPrivateKeyPem(): string | null {
  const pathRaw = process.env.LICENSE_JWT_PRIVATE_KEY_PATH?.trim();
  if (pathRaw) {
    try {
      const abs = expandLicensePrivateKeyPath(pathRaw);
      const fromFile = normalizePem(readFileSync(abs, "utf8"));
      if (fromFile.length > 0) return fromFile;
    } catch {
      /* ننتقل إلى PEM */
    }
  }

  const raw = process.env.LICENSE_JWT_PRIVATE_KEY_PEM;
  if (raw != null && String(raw).trim() !== "") {
    const normalized = normalizePem(String(raw).trim().replace(/\\n/g, "\n"));
    return normalized.length > 0 ? normalized : null;
  }

  return null;
}

/**
 * يحوّل PEM إلى أسطر نظيفة؛ وإن وُجدت BEGIN/END ملصوقة بالـ Base64 في سطر واحد يفكها.
 */
export function normalizePem(s: string): string {
  const unwrapped = unwrapSingleLinePemIfNeeded(s.replace(/\r\n/g, "\n").trim());
  return unwrapped
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .join("\n");
}

/** إن كان الملف سطراً واحداً: -----BEGIN …-----BASE64…-----END …----- */
function unwrapSingleLinePemIfNeeded(s: string): string {
  if (s.includes("\n")) return s;

  const m = s.match(/^-----BEGIN ([^-]+)-----(.*)-----END \1-----$/s);
  if (!m) return s;

  const label = m[1].trim();
  const body = m[2].replace(/\s+/g, "");
  if (!body) return s;

  const chunks = body.match(/.{1,64}/g) ?? [body];
  return `-----BEGIN ${label}-----\n${chunks.join("\n")}\n-----END ${label}-----`;
}
