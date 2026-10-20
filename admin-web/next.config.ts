import path from "node:path";
import { fileURLToPath } from "node:url";

import type { NextConfig } from "next";

/** مجلد تطبيق admin-web نفسه — يقلل لبس جذر المونوريبو عند وجود package-lock في الأعلى. */
const adminWebRoot = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  reactStrictMode: true,
  outputFileTracingRoot: adminWebRoot,
  serverExternalPackages: ["bcrypt"],
  async headers() {
    const esHeaders = [
      {
        key: "Cross-Origin-Opener-Policy",
        value: "same-origin-allow-popups",
      },
      {
        key: "Cache-Control",
        value: "no-store",
      },
    ];
    const security = process.env.NODE_ENV === "production"
      ? [
          {
            source: "/(.*)",
            headers: [
              {
                key: "Strict-Transport-Security",
                value: "max-age=63072000; includeSubDomains; preload",
              },
            ],
          },
        ]
      : [];
    return [
      ...security,
      { source: "/whatsapp-meta-es.html", headers: esHeaders },
      { source: "/whatsapp-meta-es", headers: esHeaders },
    ];
  },
};

export default nextConfig;
