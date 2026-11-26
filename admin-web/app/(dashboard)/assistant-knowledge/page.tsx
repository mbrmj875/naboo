"use client";

import { useCallback, useEffect, useState } from "react";
import { AdminToastBanner } from "@/components/admin-toast";
import { useAdminAction } from "@/lib/use-admin-action";

/** معرفة المساعد (ب4): مقالات مكتبة نابو، طلبات الدعم من المساعد، ومراجعة
 *  دليل السيارات. المقال المنشور يظهر أثره في أجوبة المساعد خلال دقيقة. */

type Article = {
  id: number;
  kind: "library" | "naboo";
  title: string;
  body: string;
  keywords: string;
  published: boolean;
  updated_at: string;
};
type Support = {
  id: number;
  tenant_id: string;
  role_key: string | null;
  route_id: string | null;
  summary: string;
  status: "open" | "done";
  created_at: string;
  notified_at: string | null;
};
type Car = {
  id: number;
  make: string;
  model: string;
  year_from: number;
  year_to: number;
  engine: string | null;
  oil_capacity_l: number | null;
  viscosity_primary: string | null;
  oil_spec: string | null;
  sources: { url?: string; title?: string }[];
  confidence: "verified" | "single_source";
  locked: boolean;
  hits: number;
};

type Tab = "articles" | "support" | "cars";
const EMPTY: Omit<Article, "id" | "updated_at"> = { kind: "library", title: "", body: "", keywords: "", published: false };

function hostOf(url?: string): string | null {
  try {
    return url ? new URL(url).hostname.replace(/^www\./, "") : null;
  } catch {
    return null;
  }
}

function when(iso: string) {
  return new Date(iso).toLocaleString("ar-IQ", { dateStyle: "medium", timeStyle: "short" });
}

export default function AssistantKnowledgePage() {
  const [tab, setTab] = useState<Tab>("support");
  const [articles, setArticles] = useState<Article[]>([]);
  const [support, setSupport] = useState<Support[]>([]);
  const [cars, setCars] = useState<Car[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState<string | null>(null);
  const [draft, setDraft] = useState<(typeof EMPTY & { id?: number }) | null>(null);
  const [onlySingle, setOnlySingle] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    setLoadErr(null);
    try {
      const res = await fetch("/api/assistant-knowledge", { cache: "no-store" });
      const json = (await res.json()) as { articles?: Article[]; support?: Support[]; cars?: Car[]; error?: string };
      if (!res.ok) throw new Error(json.error ?? "تعذّر التحميل");
      setArticles(json.articles ?? []);
      setSupport(json.support ?? []);
      setCars(json.cars ?? []);
    } catch (e) {
      setLoadErr(e instanceof Error ? e.message : "تعذّر التحميل");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const { busy, toast, clearToast, run } = useAdminAction({ reload: load });
  const act = (body: object, successMsg: string) => void run({ url: "/api/assistant-knowledge", body, successMsg });

  const openCount = support.filter((s) => s.status === "open").length;
  const singleCount = cars.filter((c) => c.confidence === "single_source" && !c.locked).length;
  const shownCars = onlySingle ? cars.filter((c) => c.confidence === "single_source" && !c.locked) : cars;

  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>معرفة المساعد</h1>
          <div className="meta">
            {openCount} طلب دعم مفتوح · {articles.filter((a) => a.published).length} مقال منشور · {singleCount} سيارة
            تحتاج مراجعة
          </div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void load()}>
          تحديث
        </button>
      </header>

      <AdminToastBanner toast={toast} onDismiss={clearToast} />

      <nav role="tablist" style={{ display: "flex", gap: 8, margin: "12px 0" }}>
        {(
          [
            ["support", `طلبات الدعم (${openCount})`],
            ["articles", "مكتبة نابو"],
            ["cars", `دليل السيارات (${singleCount})`],
          ] as [Tab, string][]
        ).map(([k, label]) => (
          <button
            key={k}
            type="button"
            role="tab"
            aria-selected={tab === k}
            className={tab === k ? "btn-primary" : "btn-ghost"}
            onClick={() => setTab(k)}
          >
            {label}
          </button>
        ))}
      </nav>

      {loading ? (
        <div className="dash-state" role="status">
          جاري التحميل…
        </div>
      ) : null}
      {!loading && loadErr ? (
        <div className="alert" role="alert">
          {loadErr}
        </div>
      ) : null}

      {!loading && !loadErr && tab === "support" ? (
        <section>
          <p className="meta">
            يرسلها المساعد بموافقة المستخدم. الملخص منظّف: لا مبالغ ولا هواتف ولا أسماء زبائن.
          </p>
          {support.length === 0 ? <div className="dash-state">لا طلبات بعد.</div> : null}
          {support.map((s) => (
            <article key={s.id} className="acct-fieldset" style={{ opacity: s.status === "done" ? 0.6 : 1 }}>
              <div className="meta">
                {when(s.created_at)} · محل {s.tenant_id.slice(0, 8)} · {s.role_key === "owner" ? "المالك" : "موظف"}
                {s.route_id ? ` · ${s.route_id}` : ""}
                {s.notified_at ? " · وصل التنبيه بالبريد" : " · لم يُرسل تنبيه"}
              </div>
              <p style={{ whiteSpace: "pre-wrap" }}>{s.summary}</p>
              {s.status === "open" ? (
                <button type="button" className="btn-ghost" disabled={busy} onClick={() => act({ action: "support_done", id: s.id }, "عُلّم كمنجز")}>
                  تم الحل
                </button>
              ) : (
                <span className="meta">منجز</span>
              )}
            </article>
          ))}
        </section>
      ) : null}

      {!loading && !loadErr && tab === "articles" ? (
        <section>
          <p className="meta">
            «مكتبة» لخبرة الزيوت والسيارات، و«نابو» لأسئلة التطبيق والاشتراك. يختار المساعد أقرب مقالين للسؤال
            بكلمات الاستدعاء ثم العنوان. النص 800 حرف كحد أقصى.
          </p>
          {draft ? (
            <form
              className="rc-form settings-form"
              onSubmit={(e) => {
                e.preventDefault();
                void run({
                  url: "/api/assistant-knowledge",
                  body: { action: "save_article", ...draft },
                  successMsg: "حُفظ المقال",
                  onSuccess: () => setDraft(null),
                });
              }}
            >
              <fieldset className="acct-fieldset" disabled={busy}>
                <legend>{draft.id ? "تعديل مقال" : "مقال جديد"}</legend>
                <label className="acct-label">
                  النوع
                  <select value={draft.kind} onChange={(e) => setDraft({ ...draft, kind: e.target.value as Article["kind"] })}>
                    <option value="library">مكتبة (زيوت وسيارات)</option>
                    <option value="naboo">نابو (التطبيق والاشتراك)</option>
                  </select>
                </label>
                <label className="acct-label">
                  العنوان
                  <input maxLength={120} value={draft.title} onChange={(e) => setDraft({ ...draft, title: e.target.value })} />
                </label>
                <label className="acct-label">
                  النص ({draft.body.length}/800)
                  <textarea rows={7} maxLength={800} value={draft.body} onChange={(e) => setDraft({ ...draft, body: e.target.value })} />
                </label>
                <label className="acct-label">
                  كلمات الاستدعاء (مفصولة بفاصلة، بالعامية أيضاً)
                  <input maxLength={400} value={draft.keywords} onChange={(e) => setDraft({ ...draft, keywords: e.target.value })} />
                </label>
                <label className="acct-label" style={{ flexDirection: "row", gap: 8, alignItems: "center" }}>
                  <input type="checkbox" checked={draft.published} onChange={(e) => setDraft({ ...draft, published: e.target.checked })} />
                  منشور (يستعمله المساعد)
                </label>
              </fieldset>
              <div style={{ display: "flex", gap: 8 }}>
                <button type="submit" className="btn-primary" disabled={busy}>
                  {busy ? "جاري الحفظ…" : "حفظ"}
                </button>
                <button type="button" className="btn-ghost" onClick={() => setDraft(null)}>
                  إلغاء
                </button>
              </div>
            </form>
          ) : (
            <button type="button" className="btn-primary" onClick={() => setDraft({ ...EMPTY })}>
              مقال جديد
            </button>
          )}
          {articles.map((a) => (
            <article key={a.id} className="acct-fieldset">
              <div className="meta">
                {a.kind === "naboo" ? "نابو" : "مكتبة"} · {a.published ? "منشور" : "مسودة"} · {when(a.updated_at)}
              </div>
              <h3>{a.title}</h3>
              <p style={{ whiteSpace: "pre-wrap" }}>{a.body}</p>
              {a.keywords ? <div className="meta">كلمات: {a.keywords}</div> : null}
              <div style={{ display: "flex", gap: 8 }}>
                <button type="button" className="btn-ghost" onClick={() => setDraft({ ...a })}>
                  تعديل
                </button>
                <button
                  type="button"
                  className="btn-ghost"
                  disabled={busy}
                  onClick={() => act({ action: "save_article", ...a, published: !a.published }, a.published ? "أُلغي النشر" : "نُشر")}
                >
                  {a.published ? "إلغاء النشر" : "انشر"}
                </button>
                <button
                  type="button"
                  className="btn-ghost"
                  disabled={busy}
                  onClick={() => {
                    if (confirm(`حذف «${a.title}» نهائياً؟`)) act({ action: "delete_article", id: a.id }, "حُذف المقال");
                  }}
                >
                  حذف
                </button>
              </div>
            </article>
          ))}
        </section>
      ) : null}

      {!loading && !loadErr && tab === "cars" ? (
        <section>
          <p className="meta">
            «مصدر واحد» يظهر للمحلات مع تنبيه. راجع الرقم بنفسك ثم «اعتمد» فيصبح موثقاً ولا يُعاد البحث عنه، أو احذفه
            فيُبحث من جديد عند أول سؤال.
          </p>
          <label className="acct-label" style={{ flexDirection: "row", gap: 8, alignItems: "center" }}>
            <input type="checkbox" checked={onlySingle} onChange={(e) => setOnlySingle(e.target.checked)} />
            ما يحتاج مراجعة فقط
          </label>
          <div className="acct-table-wrap">
            <table className="acct-table">
              <thead>
                <tr>
                  <th>السيارة</th>
                  <th>السعة</th>
                  <th>اللزوجة</th>
                  <th>الثقة</th>
                  <th>الأسئلة</th>
                  <th>المصادر</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {shownCars.map((c) => (
                  <tr key={c.id}>
                    <td dir="ltr">
                      {c.make} {c.model} {c.year_from}–{c.year_to} {c.engine ?? ""}
                    </td>
                    <td>{c.oil_capacity_l ?? "-"} لتر</td>
                    <td dir="ltr">{c.viscosity_primary ?? "-"}</td>
                    <td>{c.locked ? "معتمد" : c.confidence === "verified" ? "موثق" : "مصدر واحد"}</td>
                    <td>{c.hits}</td>
                    <td>
                      {(c.sources ?? []).slice(0, 3).map((s, i) => (
                        <div key={i}>
                          <a href={s.url} target="_blank" rel="noreferrer noopener" dir="ltr">
                            {hostOf(s.url) ?? s.title}
                          </a>
                        </div>
                      ))}
                    </td>
                    <td style={{ whiteSpace: "nowrap" }}>
                      {!c.locked ? (
                        <button type="button" className="btn-ghost" disabled={busy} onClick={() => act({ action: "car_lock", id: c.id }, "اعتُمد")}>
                          اعتمد
                        </button>
                      ) : null}
                      <button
                        type="button"
                        className="btn-ghost"
                        disabled={busy}
                        onClick={() => {
                          if (confirm(`حذف ${c.make} ${c.model}؟ سيُبحث عنها من جديد.`)) act({ action: "car_delete", id: c.id }, "حُذف");
                        }}
                      >
                        حذف
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {shownCars.length === 0 ? <div className="dash-state">لا شيء هنا.</div> : null}
        </section>
      ) : null}
    </div>
  );
}
