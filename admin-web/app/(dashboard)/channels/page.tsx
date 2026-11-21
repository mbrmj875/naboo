"use client";

import Link from "next/link";
import { OPS_CHANNELS } from "@/lib/ops-channels";

/**
 * مرحلة F — سجل قنوات عمل نابو.
 * واتساب مفعّل؛ الباقي نفس نموذج الهوية ويُفعَّل لاحقاً عبر webhook/مزوّد.
 */
export default function ChannelsPage() {
  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>قنوات تواصل عمل نابو</h1>
          <div className="meta">
            هوية واحدة لكل تاجر — واتساب الآن، وباقي القنوات بنفس الجداول لاحقاً
          </div>
        </div>
        <Link className="btn-sm" href="/inbox">
          فتح الصندوق
        </Link>
      </header>

      <div className="alert" role="status">
        لاستقبال واتساب: اضبط <code>NABOO_OPS_WEBHOOK_SECRET</code> ووجّه الموصل إلى{" "}
        <code>/api/ops/whatsapp-webhook</code>. للإرسال الاختياري:{" "}
        <code>NABOO_OPS_WA_SEND_URL</code>.
      </div>

      <ul className="channels-grid">
        {OPS_CHANNELS.filter((c) => c.id !== "system").map((ch) => (
          <li
            key={ch.id}
            className={
              ch.enabled ? "channels-card channels-card--on" : "channels-card"
            }
          >
            <div className="channels-card-title">{ch.labelAr}</div>
            <div className="meta">ترتيب التفعيل: {ch.rolloutOrder}</div>
            <div className="channels-card-status">
              {ch.enabled ? "مفعّل للاستقبال عبر webhook" : "جاهز للنموذج — غير موصول بعد"}
            </div>
            {ch.id === "whatsapp" ? (
              <Link className="btn-sm" href="/inbox">
                الصندوق
              </Link>
            ) : (
              <p className="meta">
                عند التفعيل: نفس <code>ops_contacts</code> +{" "}
                <code>ops_messages.channel = {ch.id}</code>
              </p>
            )}
          </li>
        ))}
      </ul>
    </div>
  );
}
