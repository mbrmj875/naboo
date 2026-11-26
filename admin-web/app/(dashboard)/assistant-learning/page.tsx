"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AdminToastBanner } from "@/components/admin-toast";
import { useAdminAction } from "@/lib/use-admin-action";

/** تعلّم المساعد (ب6، م5-8). كل ليلة يحكم الحَكَم على أسئلة اليوم، ويقترح دروساً
 *  من الإخفاقات المتكررة، ثم يختبر كل درس على 60 حالة ثابتة قبل نشره. هنا ترى
 *  ما نُشر ولماذا، وتتراجع عن أي درس بضغطة. */

type Status = "candidate" | "active" | "retired" | "rejected";
type Lesson = {
  id: number;
  audience: string;
  tenant_id: string | null;
  kind: "rule" | "qa" | "screen_note";
  topic: string;
  trigger_text: string;
  body: string;
  status: Status;
  version: number;
  eval_before: number | null;
  eval_after: number | null;
  origin: string;
  created_at: string;
  activated_at: string | null;
  retired_at: string | null;
  retired_reason: string | null;
  merged_from: number[] | null;
  eval_requested_at: string | null;
};
type Run = {
  id: number;
  target: string;
  lesson_id: number | null;
  model: string;
  passed: number;
  total: number;
  note: string | null;
  created_at: string;
};
type Usage = { id: number; uses: number; judged: number; fails: number; overall_judged: number; overall_fails: number };
type Topic = { topic: string; total: number; fails: number };

const STATUS_LABEL: Record<Status, string> = {
  active: "منشور",
  candidate: "مرشّح",
  retired: "متقاعد",
  rejected: "مرفوض",
};
const KIND_LABEL: Record<Lesson["kind"], string> = { rule: "قاعدة", qa: "سؤال وجواب", screen_note: "ملاحظة شاشة" };
const ORIGIN_LABEL: Record<string, string> = { learn: "تعلّم ليلي", legacy_example: "مثال قديم", manual: "يدوي" };

function when(iso: string | null) {
  return iso ? new Date(iso).toLocaleString("ar-IQ", { dateStyle: "medium", timeStyle: "short" }) : "-";
}

export default function AssistantLearningPage() {
  const [tab, setTab] = useState<Status | "runs" | "topics">("active");
  const [channel, setChannel] = useState<"app" | "whatsapp">("app");
  const [lessons, setLessons] = useState<Lesson[]>([]);
  const [runs, setRuns] = useState<Run[]>([]);
  const [usage, setUsage] = useState<Usage[]>([]);
  const [topics, setTopics] = useState<Topic[]>([]);
  const [judgedTotal, setJudgedTotal] = useState(0);
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setLoadErr(null);
    try {
      const res = await fetch(`/api/assistant-learning?channel=${channel}`, { cache: "no-store" });
      const json = (await res.json()) as {
        lessons?: Lesson[];
        runs?: Run[];
        usage?: Usage[];
        topics?: Topic[];
        judgedTotal?: number;
        supportEmail?: string;
        error?: string;
      };
      if (!res.ok) throw new Error(json.error ?? "تعذّر التحميل");
      setLessons(json.lessons ?? []);
      setRuns(json.runs ?? []);
      setUsage(json.usage ?? []);
      setTopics(json.topics ?? []);
      setJudgedTotal(json.judgedTotal ?? 0);
      setEmail(json.supportEmail ?? "");
    } catch (e) {
      setLoadErr(e instanceof Error ? e.message : "تعذّر التحميل");
    } finally {
      setLoading(false);
    }
  }, [channel]);

  useEffect(() => {
    void load();
  }, [load]);

  const { busy, toast, clearToast, run } = useAdminAction({ reload: load });
  const act = (body: object, successMsg: string) => void run({ url: "/api/assistant-learning", body, successMsg });

  const usageById = useMemo(() => new Map(usage.map((u) => [u.id, u])), [usage]);
  const count = (s: Status) => lessons.filter((l) => l.status === s).length;
  const rules = lessons.filter((l) => l.status === "active" && l.kind === "rule").length;
  const overall = usage[0] && usage[0].overall_judged > 0 ? usage[0].overall_fails / usage[0].overall_judged : null;
  const shown = tab === "runs" || tab === "topics" ? [] : lessons.filter((l) => l.status === tab);

  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>{channel === "whatsapp" ? "تعلّم مجيب واتساب" : "تعلّم المساعد"}</h1>
          <div className="meta">
            {count("active")} درس منشور ({rules}/25 قاعدة) · {count("candidate")} مرشّح · {judgedTotal}{" "}
            {channel === "whatsapp" ? "رد محكوم" : "سؤال محكوم"} في 14
            يوماً{overall != null ? ` · نسبة الفشل العامة ${Math.round(overall * 100)}%` : ""}
          </div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void load()}>
          تحديث
        </button>
      </header>

      <AdminToastBanner toast={toast} onDismiss={clearToast} />

      <nav aria-label="القناة" style={{ display: "flex", gap: 8, marginTop: 12, flexWrap: "wrap" }}>
        {(
          [
            ["app", "المساعد داخل التطبيق"],
            ["whatsapp", "مجيب واتساب"],
          ] as const
        ).map(([k, label]) => (
          <button
            key={k}
            type="button"
            aria-pressed={channel === k}
            className={channel === k ? "btn-primary" : "btn-ghost"}
            onClick={() => setChannel(k)}
          >
            {label}
          </button>
        ))}
      </nav>

      <nav role="tablist" style={{ display: "flex", gap: 8, margin: "12px 0", flexWrap: "wrap" }}>
        {(
          [
            ["active", `منشور (${count("active")})`],
            ["candidate", `مرشّح (${count("candidate")})`],
            ["retired", `متقاعد (${count("retired")})`],
            ["rejected", `مرفوض (${count("rejected")})`],
            ["runs", "تشغيلات الاختبار"],
            ["topics", "أكثر المواضيع فشلاً"],
          ] as [typeof tab, string][]
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

      {!loading && !loadErr && shown.length === 0 && tab !== "runs" && tab !== "topics" ? (
        <div className="dash-state">لا دروس هنا.</div>
      ) : null}

      {!loading && !loadErr
        ? shown.map((l) => {
            const u = usageById.get(l.id);
            return (
              <article key={l.id} className="acct-fieldset" style={{ opacity: l.status === "rejected" ? 0.7 : 1 }}>
                <div className="meta">
                  #{l.id} · {KIND_LABEL[l.kind]} · {l.topic} · {ORIGIN_LABEL[l.origin] ?? l.origin} · {when(l.created_at)}
                  {l.tenant_id ? ` · محل ${l.tenant_id.slice(0, 8)}` : ""}
                </div>
                <p className="meta">
                  <strong>متى:</strong> {l.trigger_text}
                </p>
                <p style={{ whiteSpace: "pre-wrap" }}>{l.body}</p>
                <div className="meta">
                  الاختبار: {l.eval_before ?? "-"} ← {l.eval_after ?? "-"} من 60
                  {l.activated_at ? ` · نُشر ${when(l.activated_at)}` : ""}
                  {u ? ` · استُعمل ${u.uses} مرة، حُكم ${u.judged}، فشل ${u.fails}` : ""}
                  {l.merged_from?.length ? ` · دُمج من ${l.merged_from.map((x) => `#${x}`).join("، ")}` : ""}
                </div>
                {l.retired_reason ? <div className="meta">السبب: {l.retired_reason}</div> : null}
                {l.eval_requested_at ? (
                  <div className="meta">طُلب اختباره {when(l.eval_requested_at)}، يُختبر خلال 10 دقائق.</div>
                ) : null}
                <div style={{ display: "flex", gap: 8 }}>
                  {l.status === "active" ? (
                    <button
                      type="button"
                      className="btn-ghost"
                      disabled={busy}
                      onClick={() => {
                        if (confirm(`التراجع عن الدرس #${l.id}؟ يخرج من المساعد خلال 10 دقائق.`)) {
                          act({ action: "rollback", id: l.id }, "تم التراجع عن الدرس");
                        }
                      }}
                    >
                      تراجع
                    </button>
                  ) : null}
                  {l.status === "candidate" && !l.eval_requested_at ? (
                    <button
                      type="button"
                      className="btn-primary"
                      disabled={busy}
                      onClick={() => act({ action: "request_eval", id: l.id }, "سيُختبر خلال 10 دقائق")}
                    >
                      اختبره
                    </button>
                  ) : null}
                  {l.status === "candidate" ? (
                    <button
                      type="button"
                      className="btn-ghost"
                      disabled={busy}
                      onClick={() => act({ action: "reject", id: l.id }, "رُفض الدرس")}
                    >
                      ارفض
                    </button>
                  ) : null}
                </div>
              </article>
            );
          })
        : null}

      {!loading && !loadErr && tab === "runs" ? (
        <section>
          <p className="meta">
            «baseline» = المساعد بالدروس الحالية بلا الدرس الجديد، يُحسب مرة في اليوم. الدرس يُنشر فقط إذا لم تنزل
            النتيجة ولم تفشل حالة كانت ناجحة (بعد إعادة الحالات المتذبذبة).
          </p>
          <div className="acct-table-wrap">
            <table className="acct-table">
              <thead>
                <tr>
                  <th>#</th>
                  <th>الوقت</th>
                  <th>الدرس</th>
                  <th>النتيجة</th>
                  <th>النموذج</th>
                  <th>ملاحظة</th>
                </tr>
              </thead>
              <tbody>
                {runs.map((r) => (
                  <tr key={r.id}>
                    <td>{r.id}</td>
                    <td>{when(r.created_at)}</td>
                    <td>{r.lesson_id ? `#${r.lesson_id}` : "-"}</td>
                    <td>
                      {r.passed}/{r.total}
                    </td>
                    <td dir="ltr">{r.model}</td>
                    <td dir="auto" style={{ maxWidth: 360 }}>
                      {r.note ?? ""}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </section>
      ) : null}

      {!loading && !loadErr && tab === "topics" ? (
        <section>
          <p className="meta">
            حكم الحَكَم على أسئلة آخر 14 يوماً. الموضوع يصير درساً مقترحاً إذا فشل 3 مرات من محلَّين على الأقل.
          </p>
          <div className="acct-table-wrap">
            <table className="acct-table">
              <thead>
                <tr>
                  <th>الموضوع</th>
                  <th>فشل</th>
                  <th>محكوم</th>
                  <th>النسبة</th>
                </tr>
              </thead>
              <tbody>
                {topics.map((t) => (
                  <tr key={t.topic}>
                    <td dir="ltr">{t.topic}</td>
                    <td>{t.fails}</td>
                    <td>{t.total}</td>
                    <td>{t.total ? Math.round((t.fails / t.total) * 100) : 0}%</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {topics.length === 0 ? <div className="dash-state">لا أحكام بعد.</div> : null}
        </section>
      ) : null}

      {!loading && !loadErr ? (
        <form
          className="rc-form settings-form"
          style={{ marginTop: 24 }}
          onSubmit={(e) => {
            e.preventDefault();
            act({ action: "support_email", email }, "حُفظ البريد");
          }}
        >
          <fieldset className="acct-fieldset" disabled={busy}>
            <legend>بريد تنبيه الدعم</legend>
            <p className="meta">كل طلب دعم يرسله المساعد يصل هنا فوراً، ويظهر في «معرفة المساعد».</p>
            <label className="acct-label">
              البريد
              <input type="email" dir="ltr" value={email} onChange={(e) => setEmail(e.target.value)} />
            </label>
          </fieldset>
          <button type="submit" className="btn-primary" disabled={busy}>
            حفظ
          </button>
        </form>
      ) : null}
    </div>
  );
}
