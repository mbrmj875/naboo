"use client";

import { useCallback, useState } from "react";

export type AdminToast = {
  kind: "ok" | "err";
  text: string;
} | null;

type RunOptions = {
  url: string;
  body: object;
  successMsg: string;
  /** إذا رجع true بعد النجاح (مثلاً حذف حساب) */
  onSuccess?: (json: Record<string, unknown>) => void | Promise<void>;
};

type UseAdminActionArgs = {
  reload: () => Promise<void>;
};

export type UseAdminActionResult = {
  busy: boolean;
  toast: AdminToast;
  clearToast: () => void;
  showToast: (toast: NonNullable<AdminToast>) => void;
  run: (opts: RunOptions) => Promise<boolean>;
};

/**
 * تنفيذ موحّد لإجراءات الإدارة:
 * تعطيل الزر أثناء الطلب · toast · إعادة جلب البيانات.
 */
export function useAdminAction({
  reload,
}: UseAdminActionArgs): UseAdminActionResult {
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<AdminToast>(null);

  const clearToast = useCallback(() => setToast(null), []);
  const showToast = useCallback((t: NonNullable<AdminToast>) => {
    setToast(t);
  }, []);

  const run = useCallback(
    async ({ url, body, successMsg, onSuccess }: RunOptions): Promise<boolean> => {
      setToast(null);
      setBusy(true);
      try {
        const res = await fetch(url, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
        const json = (await res.json()) as Record<string, unknown> & {
          error?: string;
        };
        if (!res.ok) {
          setToast({
            kind: "err",
            text: json.error ?? "فشل تنفيذ الإجراء",
          });
          return false;
        }
        setToast({ kind: "ok", text: successMsg });
        await reload();
        if (onSuccess) await onSuccess(json);
        return true;
      } catch {
        setToast({ kind: "err", text: "خطأ شبكة — تعذر الاتصال بالخادم" });
        return false;
      } finally {
        setBusy(false);
      }
    },
    [reload],
  );

  return { busy, toast, clearToast, showToast, run };
}
