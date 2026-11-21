import { Suspense } from "react";
import FieldLoginPage from "./login-client";

export default function Page() {
  return (
    <Suspense fallback={<div className="field-login-page">جاري التحميل…</div>}>
      <FieldLoginPage />
    </Suspense>
  );
}
