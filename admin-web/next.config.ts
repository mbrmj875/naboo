import path from "node:path";
import { fileURLToPath } from "node:url";

import type { NextConfig } from "next";

/** مجلد تطبيق admin-web نفسه — يقلل لبس جذر المونوريبو عند وجود package-lock في الأعلى. */
const adminWebRoot = path.dirname(fileURLToPath(import.meta.url));

const nextConfig: NextConfig = {
  reactStrictMode: true,
  outputFileTracingRoot: adminWebRoot,
  async headers() {
    if (process.env.NODE_ENV !== "production") {
      return [];
    }
    return [
      {
        source: "/(.*)",
        headers: [
          {
            key: "Strict-Transport-Security",
            value: "max-age=63072000; includeSubDomains; preload",
          },
        ],
      },
    ];
  },
};

export default nextConfig;
