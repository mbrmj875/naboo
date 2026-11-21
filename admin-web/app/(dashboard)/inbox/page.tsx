"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { formatDateTimeLatn } from "@/lib/format-ar";
import { opsChannelLabelAr } from "@/lib/ops-channels";
import { AdminToastBanner } from "@/components/admin-toast";

type Conversation = {
  id: string;
  phone_e164: string;
  display_name: string | null;
  auth_user_id: string | null;
  lifecycle: string;
  last_message: {
    body: string;
    created_at: string;
    channel: string;
    sender: string;
  } | null;
};

type Message = {
  id: string;
  body: string;
  sender: string;
  channel: string;
  direction: string;
  created_at: string;
};

type Suggestion = {
  id: string;
  response_text: string;
  confidence: number | null;
  status: string;
};

export default function InboxPage() {
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [contact, setContact] = useState<Conversation | null>(null);
  const [draft, setDraft] = useState("");
  const [busy, setBusy] = useState(false);
  const [toast, setToast] = useState<{ kind: "ok" | "err"; text: string } | null>(
    null,
  );
  const [schemaHint, setSchemaHint] = useState(false);

  const loadList = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/ops/inbox");
      const json = (await res.json()) as {
        error?: string;
        conversations?: Conversation[];
      };
      if (!res.ok) {
        if (json.error?.includes("does not exist") || json.error?.includes("ops_")) {
          setSchemaHint(true);
        }
        setError(json.error ?? "فشل التحميل");
        setConversations([]);
        return;
      }
      setConversations(json.conversations ?? []);
    } catch {
      setError("خطأ شبكة");
    } finally {
      setLoading(false);
    }
  }, []);

  const loadThread = useCallback(async (contactId: string) => {
    setBusy(true);
    try {
      const res = await fetch(
        `/api/ops/inbox?contact_id=${encodeURIComponent(contactId)}`,
      );
      const json = (await res.json()) as {
        error?: string;
        contact?: Conversation;
        messages?: Message[];
        pending_suggestions?: Suggestion[];
      };
      if (!res.ok) {
        setToast({ kind: "err", text: json.error ?? "فشل فتح المحادثة" });
        return;
      }
      setContact(json.contact ?? null);
      setMessages(json.messages ?? []);
      setSuggestions(json.pending_suggestions ?? []);
    } finally {
      setBusy(false);
    }
  }, []);

  useEffect(() => {
    void loadList();
  }, [loadList]);

  useEffect(() => {
    if (selectedId) void loadThread(selectedId);
  }, [selectedId, loadThread]);

  const send = async () => {
    if (!selectedId || draft.trim().length < 1) return;
    setBusy(true);
    try {
      const res = await fetch("/api/ops/inbox", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ contact_id: selectedId, text: draft.trim() }),
      });
      const json = (await res.json()) as { error?: string };
      if (!res.ok) {
        setToast({ kind: "err", text: json.error ?? "فشل الإرسال" });
        return;
      }
      setDraft("");
      setToast({ kind: "ok", text: "تم تسجيل الرسالة الصادرة" });
      await loadThread(selectedId);
      await loadList();
    } finally {
      setBusy(false);
    }
  };

  const suggestAi = async () => {
    if (!selectedId) return;
    setBusy(true);
    try {
      const lastCustomer = [...messages]
        .reverse()
        .find((m) => m.sender === "customer");
      const res = await fetch("/api/ops/ai/suggest", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contact_id: selectedId,
          latest_message: lastCustomer?.body ?? "مرحبا",
        }),
      });
      const json = (await res.json()) as {
        error?: string;
        suggestion?: Suggestion;
      };
      if (!res.ok) {
        setToast({ kind: "err", text: json.error ?? "فشل الاقتراح" });
        return;
      }
      if (json.suggestion?.response_text) {
        setDraft(json.suggestion.response_text);
        setToast({ kind: "ok", text: "تم توليد اقتراح AI — راجع قبل الإرسال" });
      }
      await loadThread(selectedId);
    } finally {
      setBusy(false);
    }
  };

  const decideSuggestion = async (
    id: string,
    action: "approve" | "reject" | "edit_send",
  ) => {
    setBusy(true);
    try {
      const res = await fetch("/api/ops/ai/approve", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          suggestion_id: id,
          action,
          manual_edit: action === "edit_send" ? draft : undefined,
          send_channel: action === "reject" ? "none" : "whatsapp",
        }),
      });
      const json = (await res.json()) as { error?: string; text?: string };
      if (!res.ok) {
        setToast({ kind: "err", text: json.error ?? "فشل القرار" });
        return;
      }
      setToast({
        kind: "ok",
        text:
          action === "reject"
            ? "رُفض الاقتراح"
            : "تمت الموافقة وتسجيل الرد",
      });
      if (selectedId) await loadThread(selectedId);
      await loadList();
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="shell dash-page inbox-page">
      <header className="topbar">
        <div>
          <h1>صندوق وارد نابو</h1>
          <div className="meta">واتساب عمل المنصة أولاً — موافقة بشرية على ردود AI</div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void loadList()}>
          تحديث
        </button>
      </header>

      <AdminToastBanner toast={toast} onDismiss={() => setToast(null)} />

      {schemaHint ? (
        <div className="alert" role="status">
          شغّل <code>admin-web/supabase/ops_crm_v1.sql</code> ثم اضبط{" "}
          <code>NABOO_OPS_WEBHOOK_SECRET</code> لاستقبال الرسائل.
        </div>
      ) : null}

      {loading ? (
        <div className="dash-state" role="status">
          جاري التحميل…
        </div>
      ) : null}
      {error && !schemaHint ? (
        <div className="alert" role="alert">
          {error}
        </div>
      ) : null}

      <div className="inbox-layout">
        <aside className="inbox-list" aria-label="المحادثات">
          {conversations.length === 0 && !loading ? (
            <div className="dash-state muted">
              لا محادثات بعد. ستظهر هنا عند وصول webhook واتساب.
            </div>
          ) : (
            <ul>
              {conversations.map((c) => (
                <li key={c.id}>
                  <button
                    type="button"
                    className={
                      selectedId === c.id
                        ? "inbox-conv inbox-conv--active"
                        : "inbox-conv"
                    }
                    onClick={() => setSelectedId(c.id)}
                  >
                    <div className="inbox-conv-name">
                      {c.display_name || c.phone_e164}
                    </div>
                    <div className="meta" dir="ltr">
                      {c.phone_e164}
                    </div>
                    <div className="inbox-conv-preview">
                      {c.last_message?.body?.slice(0, 80) ?? "—"}
                    </div>
                    <div className="meta">
                      {c.lifecycle}
                      {c.auth_user_id ? (
                        <>
                          {" · "}
                          <Link
                            href={`/accounts?account=${encodeURIComponent(c.auth_user_id)}`}
                            onClick={(e) => e.stopPropagation()}
                          >
                            الحساب
                          </Link>
                        </>
                      ) : null}
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </aside>

        <section className="inbox-thread" aria-label="الخيط">
          {!selectedId ? (
            <div className="dash-state muted">اختر محادثة من القائمة.</div>
          ) : (
            <>
              <div className="inbox-thread-head">
                <strong>{contact?.display_name || contact?.phone_e164}</strong>
                <span className="meta" dir="ltr">
                  {contact?.phone_e164}
                </span>
                {contact?.auth_user_id ? (
                  <Link
                    className="btn-sm"
                    href={`/accounts?account=${encodeURIComponent(contact.auth_user_id)}&tab=crm`}
                  >
                    بطاقة CRM
                  </Link>
                ) : null}
              </div>

              <div className="inbox-messages">
                {messages.map((m) => (
                  <div
                    key={m.id}
                    className={
                      m.direction === "inbound"
                        ? "inbox-bubble inbox-bubble--in"
                        : "inbox-bubble inbox-bubble--out"
                    }
                  >
                    <div className="inbox-bubble-meta">
                      {opsChannelLabelAr(m.channel)} · {m.sender} ·{" "}
                      {formatDateTimeLatn(m.created_at)}
                    </div>
                    <div>{m.body}</div>
                  </div>
                ))}
              </div>

              {suggestions.length > 0 ? (
                <div className="inbox-suggestions">
                  <h3>اقتراحات AI بانتظار الموافقة</h3>
                  {suggestions.map((s) => (
                    <div key={s.id} className="inbox-suggestion">
                      <p>{s.response_text}</p>
                      <div className="acct-form-row">
                        <button
                          type="button"
                          className="btn-sm"
                          disabled={busy}
                          onClick={() => {
                            setDraft(s.response_text);
                            void decideSuggestion(s.id, "edit_send");
                          }}
                        >
                          اعتماد وإرسال
                        </button>
                        <button
                          type="button"
                          className="btn-ghost"
                          disabled={busy}
                          onClick={() => void decideSuggestion(s.id, "reject")}
                        >
                          رفض
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              ) : null}

              <div className="inbox-composer">
                <textarea
                  rows={3}
                  value={draft}
                  onChange={(e) => setDraft(e.target.value)}
                  placeholder="اكتب رداً أو ولّد اقتراح AI…"
                  disabled={busy}
                />
                <div className="acct-form-row">
                  <button
                    type="button"
                    className="btn-primary"
                    disabled={busy || draft.trim().length < 1}
                    onClick={() => void send()}
                  >
                    إرسال / تسجيل
                  </button>
                  <button
                    type="button"
                    className="btn-sm"
                    disabled={busy}
                    onClick={() => void suggestAi()}
                  >
                    اقتراح AI
                  </button>
                </div>
              </div>
            </>
          )}
        </section>
      </div>
    </div>
  );
}
