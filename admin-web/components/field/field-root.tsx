"use client";

import { useEffect, useState } from "react";
import {
  detectFieldPlatform,
  fieldPlatformClass,
  type FieldPlatform,
} from "@/lib/field-platform";

/** يطبّق صنف المنصة على الجذر ليتجانس الشكل مع iOS / Android */
export function FieldRoot({ children }: { children: React.ReactNode }) {
  const [platform, setPlatform] = useState<FieldPlatform>("other");

  useEffect(() => {
    const p = detectFieldPlatform();
    setPlatform(p);
    document.documentElement.dataset.fieldPlatform = p;
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) {
      meta.setAttribute("content", p === "ios" ? "#f2f2f7" : "#f0f3f7");
    }
  }, []);

  return (
    <div className={`field-root ${fieldPlatformClass(platform)}`}>
      {children}
    </div>
  );
}
