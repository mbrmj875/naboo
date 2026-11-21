"use client";

import { useCallback, useEffect, useState } from "react";
import type { DeviceRow, LicenseRow, UserRow } from "@/lib/dashboard-data";
import type {
  OpsCrmMeta,
  OpsCrmNote,
  OpsCrmTask,
  OpsTimelineItem,
} from "@/lib/ops-crm";
import { accountWhatsAppHref, buildSystemTimeline } from "@/lib/ops-crm";
import { formatDateTimeLatn } from "@/lib/format-ar";
import { AdminToastBanner } from "@/components/admin-toast";
import { useAdminAction } from "@/lib/use-admin-action";

type Props = {
  user: UserRow;
  license: LicenseRow | null;
  devices: DeviceRow[];
  reload: () => Promise<void>;
};

export function AccountCrmPanel({ user, license, devices, reload }: Props) {
  const { busy, toast, clearToast, showToast, run } = useAdminAction({ reload });
  const [loading, setLoading] = useState(true);
  const [schemaMissing, setSchemaMissing] = useState(false);
  const [meta, setMeta] = useState<OpsCrmMeta | null>(null);
  const [notes, setNotes] = useState<OpsCrmNote[]>([]);
  const [tasks, setTasks] = useState<OpsCrmTask[]>([]);
  const [timeline, setTimeline] = useState<OpsTimelineItem[]>([]);

  const [owner, setOwner] = useState("");
  const [tagsText, setTagsText] = useState("");
  const [noteBody, setNoteBody] = useState("");
  const [taskTitle, setTaskTitle] = useState("");
  const [taskDue, setTaskDue] = useState("");
  const [taskAssignee, setTaskAssignee] = useState("");

  const waHref = accountWhatsAppHref(user);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await fetch("/api/ops/crm/bundle", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          accountUserId: user.id,
          user,
          license,
          devices,
        }),
      });
      const json = (await res.json()) as {
        error?: string;
        schemaMissing?: boolean;
        meta?: OpsCrmMeta | null;
        notes?: OpsCrmNote[];
        tasks?: OpsCrmTask[];
        timeline?: OpsTimelineItem[];
      };
      if (!res.ok) {
        showToast({ kind: "err", text: json.error ?? "فشل تحميل CRM" });
        setTimeline(buildSystemTimeline({ user, license, devices }));
        return;
      }
      setSchemaMissing(Boolean(json.schemaMissing));
      setMeta(json.meta ?? null);
      setNotes(json.notes ?? []);
      setTasks(json.tasks ?? []);
      setTimeline(
        json.timeline?.length
          ? json.timeline
          : buildSystemTimeline({ user, license, devices }),
      );
      setOwner(json.meta?.owner ?? "");
      setTagsText((json.meta?.tags ?? []).join("، "));
    } catch {
      showToast({ kind: "err", text: "خطأ شبكة — تعذر تحميل CRM" });
      setTimeline(buildSystemTimeline({ user, license, devices }));
    } finally {
      setLoading(false);
    }
  }, [user, license, devices, showToast]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    void fetch("/api/ops/contacts/sync", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ user, licenses: license ? [license] : [] }),
    }).catch(() => undefined);
  }, [user, license]);

  const saveMeta = () => {
    const tags = tagsText
      .split(/[،,]/)
      .map((t) => t.trim())
      .filter(Boolean);
    void run({
      url: "/api/ops/crm/meta",
      body: {
        account_user_id: user.id,
        owner: owner.trim() || null,
        tags,
        next_follow_up_at: meta?.next_follow_up_at ?? null,
      },
      successMsg: "تم حفظ متابعة الحساب",
      onSuccess: async () => {
        await load();
      },
    });
  };

  const addNote = () => {
    void run({
      url: "/api/ops/crm/notes",
      body: {
        account_user_id: user.id,
        body: noteBody,
        created_by: owner.trim() || "admin",
      },
      successMsg: "تمت إضافة الملاحظة",
      onSuccess: async () => {
        setNoteBody("");
        await load();
      },
    });
  };

  const addTask = () => {
    void run({
      url: "/api/ops/crm/tasks",
      body: {
        account_user_id: user.id,
        title: taskTitle,
        due_at: taskDue ? new Date(taskDue).toISOString() : null,
        assignee: taskAssignee.trim() || owner.trim() || null,
        kind: "manual",
        created_by: owner.trim() || "admin",
      },
      successMsg: "تمت إضافة المهمة",
      onSuccess: async () => {
        setTaskTitle("");
        setTaskDue("");
        await load();
      },
    });
  };

  const toggleTask = (task: OpsCrmTask) => {
    void (async () => {
      const res = await fetch("/api/ops/crm/tasks", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: task.id, done: !task.done_at }),
      });
      if (!res.ok) {
        const json = (await res.json()) as { error?: string };
        showToast({ kind: "err", text: json.error ?? "فشل تحديث المهمة" });
        return;
      }
      showToast({
        kind: "ok",
        text: task.done_at ? "أُعيد فتح المهمة" : "تمت المهمة",
      });
      await load();
    })();
  };

  return (
    <div className="acct-crm">
      <AdminToastBanner toast={toast} onDismiss={clearToast} />

      {schemaMissing ? (
        <div className="alert" role="status">
          جداول CRM غير مُنشأة بعد. شغّل{" "}
          <code>admin-web/supabase/ops_crm_v1.sql</code> من محرر SQL في Supabase.
          الخط الزمني النظامي يظهر أدناه بدون ملاحظات/مهام محفوظة.
        </div>
      ) : null}

      <div className="acct-crm-actions">
        {waHref ? (
          <a className="btn-sm" href={waHref} target="_blank" rel="noreferrer">
            واتساب
          </a>
        ) : (
          <span className="meta">لا يوجد هاتف لواتساب</span>
        )}
        <button
          type="button"
          className="btn-ghost"
          disabled={loading || busy}
          onClick={() => void load()}
        >
          تحديث CRM
        </button>
      </div>

      <fieldset className="acct-fieldset" disabled={busy || schemaMissing}>
        <legend>متابعة الفريق</legend>
        <label className="acct-crm-label">
          مسؤول المتابعة
          <input
            value={owner}
            onChange={(e) => setOwner(e.target.value)}
            placeholder="مثال: أحمد"
          />
        </label>
        <label className="acct-crm-label">
          وسوم (افصل بفاصلة)
          <input
            value={tagsText}
            onChange={(e) => setTagsText(e.target.value)}
            placeholder="زيت، بغداد، إحالة"
          />
        </label>
        <button type="button" className="btn-sm" disabled={busy} onClick={saveMeta}>
          حفظ المتابعة
        </button>
      </fieldset>

      <section className="acct-crm-section" aria-label="الخط الزمني">
        <h3 className="acct-crm-h">الخط الزمني</h3>
        {loading ? (
          <div className="dash-state muted">جاري التحميل…</div>
        ) : timeline.length === 0 ? (
          <div className="dash-state muted">لا أحداث بعد.</div>
        ) : (
          <ol className="acct-crm-timeline">
            {timeline.slice(0, 40).map((item) => (
              <li key={item.id} className={`acct-crm-tl acct-crm-tl--${item.kind}`}>
                <div className="acct-crm-tl-title">{item.title}</div>
                {item.detail ? (
                  <div className="acct-crm-tl-detail">{item.detail}</div>
                ) : null}
                <div className="meta">{formatDateTimeLatn(item.at)}</div>
              </li>
            ))}
          </ol>
        )}
      </section>

      <section className="acct-crm-section" aria-label="المهام">
        <h3 className="acct-crm-h">المهام</h3>
        <ul className="acct-crm-tasks">
          {tasks.map((t) => (
            <li key={t.id} className={t.done_at ? "done" : undefined}>
              <label>
                <input
                  type="checkbox"
                  checked={Boolean(t.done_at)}
                  onChange={() => toggleTask(t)}
                  disabled={busy || schemaMissing}
                />
                <span>{t.title}</span>
              </label>
              <div className="meta">
                {[t.assignee, t.due_at ? formatDateTimeLatn(t.due_at) : null, t.kind]
                  .filter(Boolean)
                  .join(" · ")}
              </div>
            </li>
          ))}
        </ul>
        <fieldset className="acct-fieldset" disabled={busy || schemaMissing}>
          <legend>مهمة جديدة</legend>
          <input
            value={taskTitle}
            onChange={(e) => setTaskTitle(e.target.value)}
            placeholder="عنوان المهمة"
          />
          <input
            type="datetime-local"
            value={taskDue}
            onChange={(e) => setTaskDue(e.target.value)}
            aria-label="موعد الاستحقاق"
          />
          <input
            value={taskAssignee}
            onChange={(e) => setTaskAssignee(e.target.value)}
            placeholder="المسؤول"
          />
          <button
            type="button"
            className="btn-sm"
            disabled={busy || taskTitle.trim().length < 2}
            onClick={addTask}
          >
            إضافة مهمة
          </button>
        </fieldset>
      </section>

      <section className="acct-crm-section" aria-label="الملاحظات">
        <h3 className="acct-crm-h">الملاحظات</h3>
        <ul className="acct-crm-notes">
          {notes.map((n) => (
            <li key={n.id}>
              <div>{n.body}</div>
              <div className="meta">
                {[n.created_by, formatDateTimeLatn(n.created_at)]
                  .filter(Boolean)
                  .join(" · ")}
              </div>
            </li>
          ))}
        </ul>
        <fieldset className="acct-fieldset" disabled={busy || schemaMissing}>
          <legend>ملاحظة جديدة</legend>
          <textarea
            value={noteBody}
            onChange={(e) => setNoteBody(e.target.value)}
            rows={3}
            placeholder="مثال: اتصلت بهم الجمعة بخصوص التجديد"
          />
          <button
            type="button"
            className="btn-sm"
            disabled={busy || noteBody.trim().length < 2}
            onClick={addNote}
          >
            إضافة ملاحظة
          </button>
        </fieldset>
      </section>
    </div>
  );
}
