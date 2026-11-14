"use client";

import type { AdminToast } from "@/lib/use-admin-action";

export function AdminToastBanner({
  toast,
  onDismiss,
}: {
  toast: AdminToast;
  onDismiss: () => void;
}) {
  if (!toast) return null;
  return (
    <div
      className={toast.kind === "ok" ? "feedback acct-toast" : "feedback err acct-toast"}
      role="status"
    >
      <span>{toast.text}</span>
      <button type="button" className="btn-ghost" onClick={onDismiss}>
        إغلاق
      </button>
    </div>
  );
}
