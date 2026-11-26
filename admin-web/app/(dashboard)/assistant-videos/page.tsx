"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { AdminToastBanner } from "@/components/admin-toast";
import { ASSISTANT_SCREENS } from "@/lib/assistant-screens";
import { useAdminAction } from "@/lib/use-admin-action";

/** فيديو شرح لكل شاشة (م3-15). يظهر في التطبيق زر «شاهد الشرح» تحت
 *  «اشرح لي هذه الشاشة» بعد الحفظ مباشرة، بلا تحديث للتطبيق. */
export default function AssistantVideosPage() {
  const [videos, setVideos] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [loadErr, setLoadErr] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setLoadErr(null);
    try {
      const res = await fetch("/api/assistant-videos", { cache: "no-store" });
      const json = (await res.json()) as { videos?: Record<string, string>; error?: string };
      if (!res.ok) throw new Error(json.error ?? "تعذّر التحميل");
      setVideos(json.videos ?? {});
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

  const groups = useMemo(() => {
    const m = new Map<string, typeof ASSISTANT_SCREENS>();
    for (const s of ASSISTANT_SCREENS) m.set(s.group, [...(m.get(s.group) ?? []), s]);
    return [...m.entries()];
  }, []);

  const count = Object.values(videos).filter((v) => v.trim()).length;

  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>فيديوهات المساعد</h1>
          <div className="meta">
            رابط فيديو لكل شاشة · {count} من {ASSISTANT_SCREENS.length}
          </div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void load()}>
          تحديث
        </button>
      </header>

      <AdminToastBanner toast={toast} onDismiss={clearToast} />

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

      {!loading && !loadErr ? (
        <form
          className="rc-form settings-form"
          onSubmit={(e) => {
            e.preventDefault();
            void run({
              url: "/api/assistant-videos",
              body: { videos },
              successMsg: "تم حفظ روابط الفيديو",
            });
          }}
        >
          <p className="meta">
            ضع رابط https (يوتيوب أو غيره). الرابط الفارغ يُخفي الزر من الشاشة.
          </p>
          {groups.map(([group, items]) => (
            <fieldset key={group} className="acct-fieldset" disabled={busy}>
              <legend>{group}</legend>
              {items.map((s) => (
                <label key={s.routeId} className="acct-label">
                  {s.title}
                  <input
                    type="url"
                    dir="ltr"
                    inputMode="url"
                    placeholder="https://"
                    value={videos[s.routeId] ?? ""}
                    onChange={(e) => setVideos({ ...videos, [s.routeId]: e.target.value })}
                  />
                </label>
              ))}
            </fieldset>
          ))}
          <button type="submit" className="btn-primary" disabled={busy}>
            {busy ? "جاري الحفظ…" : "حفظ"}
          </button>
        </form>
      ) : null}
    </div>
  );
}
