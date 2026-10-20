"use client";

import Link from "next/link";
import { formatNumberLatn } from "@/lib/format-ar";
import { useDashboardData } from "@/lib/use-dashboard-data";

export default function SupportPage() {
  const { data, loadErr, loading, reload } = useDashboardData();

  const snapCount = data?.snapshots?.length ?? 0;
  const chunkCount = data?.snapshotChunks?.length ?? 0;

  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>أدوات الدعم</h1>
          <div className="meta">للعمليات التقنية وحل أعطال المزامنة</div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void reload()}>
          تحديث
        </button>
      </header>

      {loading ? (
        <div className="dash-state" role="status">
          جاري التحميل…
        </div>
      ) : null}

      {!loading && loadErr ? (
        <div className="alert" role="alert">
          <div>{loadErr}</div>
          <button type="button" className="btn-ghost" onClick={() => void reload()}>
            إعادة المحاولة
          </button>
        </div>
      ) : null}

      {!loading && !loadErr ? (
        <div className="support-stack">
          <section className="acct-fieldset">
            <h2 className="ops-attention-title">ملخص المزامنة العامة</h2>
            <p className="meta">
              أعداد تقريبية من آخر جلب — للتفاصيل أو المسح أو المعاينة افتح ملف
              الحساب المعني.
            </p>
            <dl className="acct-dl compact">
              <div>
                <dt>لقطات مزامنة</dt>
                <dd>{formatNumberLatn(snapCount)}</dd>
              </div>
              <div>
                <dt>أجزاء لقطات</dt>
                <dd>{formatNumberLatn(chunkCount)}</dd>
              </div>
            </dl>
            {(snapCount === 0 && chunkCount === 0) ? (
              <div className="dash-state muted" style={{ marginBlockStart: "0.75rem" }}>
                لا بيانات مزامنة ظاهرة حالياً.
              </div>
            ) : null}
          </section>

          <section className="acct-fieldset">
            <h2 className="ops-attention-title">أدوات حساب معيّن</h2>
            <p>
              تبديل نظام الترخيص، معاينة اللقطات، مسح السحابة، وحذف الحساب موجودة داخل{" "}
              <strong>ملف الحساب</strong> ← قسم «أدوات دعم» (مطوي) والمنطقة الحمراء.
            </p>
            <Link className="btn-primary" href="/accounts">
              فتح الحسابات
            </Link>
          </section>
        </div>
      ) : null}
    </div>
  );
}
