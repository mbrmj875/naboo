"use client";

import { useEffect, useState } from "react";
import { AdminToastBanner } from "@/components/admin-toast";
import {
  defaultAppRemoteConfig,
  type AppRemoteConfigPayload,
} from "@/lib/dashboard-data";
import { formatDateTimeLatn } from "@/lib/format-ar";
import { useAdminAction } from "@/lib/use-admin-action";
import { useDashboardData } from "@/lib/use-dashboard-data";

export default function SettingsPage() {
  const { data, loadErr, loading, reload } = useDashboardData();
  const { busy, toast, clearToast, run } = useAdminAction({ reload });
  const [rc, setRc] = useState<AppRemoteConfigPayload | null>(null);

  useEffect(() => {
    if (data?.remoteConfig) {
      setRc({ ...data.remoteConfig });
    } else if (!loading && !loadErr) {
      setRc(defaultAppRemoteConfig());
    }
  }, [data?.remoteConfig, data?.fetchedAt, loading, loadErr]);

  return (
    <div className="shell dash-page">
      <header className="topbar">
        <div>
          <h1>إعدادات المنصة</h1>
          <div className="meta">
            التحكم بوضع التطبيق للجميع
            {data?.remoteConfigUpdatedAt ? (
              <>
                {" "}
                · آخر حفظ: {formatDateTimeLatn(data.remoteConfigUpdatedAt)}
              </>
            ) : null}
          </div>
        </div>
        <button type="button" className="btn-ghost" onClick={() => void reload()}>
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
          <div>{loadErr}</div>
          <button type="button" className="btn-ghost" onClick={() => void reload()}>
            إعادة المحاولة
          </button>
        </div>
      ) : null}

      {!loading && !loadErr && rc ? (
        <form
          className="rc-form settings-form"
          onSubmit={(e) => {
            e.preventDefault();
            void run({
              url: "/api/remote-config",
              body: { config: rc },
              successMsg: "تم حفظ إعدادات المنصة",
            });
          }}
        >
          <fieldset className="acct-fieldset" disabled={busy}>
            <legend>الصيانة والمزامنة</legend>
            <label className="rc-row">
              <input
                type="checkbox"
                checked={rc.maintenance_mode}
                onChange={(e) =>
                  setRc({ ...rc, maintenance_mode: e.target.checked })
                }
              />
              وضع الصيانة
            </label>
            <label className="acct-label">
              رسالة الصيانة
              <textarea
                value={rc.maintenance_message_ar}
                onChange={(e) =>
                  setRc({ ...rc, maintenance_message_ar: e.target.value })
                }
                rows={2}
              />
            </label>
            <label className="rc-row">
              <input
                type="checkbox"
                checked={rc.sync_paused_globally}
                onChange={(e) =>
                  setRc({ ...rc, sync_paused_globally: e.target.checked })
                }
              />
              إيقاف المزامنة السحابية للجميع
            </label>
            <label className="acct-label">
              رسالة إيقاف المزامنة
              <input
                type="text"
                value={rc.sync_paused_message_ar}
                onChange={(e) =>
                  setRc({ ...rc, sync_paused_message_ar: e.target.value })
                }
              />
            </label>
          </fieldset>

          <fieldset className="acct-fieldset" disabled={busy}>
            <legend>الإصدارات والتحديث</legend>
            <label className="acct-label">
              أدنى إصدار مدعوم
              <input
                type="text"
                value={rc.min_supported_version}
                onChange={(e) =>
                  setRc({ ...rc, min_supported_version: e.target.value })
                }
              />
            </label>
            <label className="acct-label">
              أحدث إصدار
              <input
                type="text"
                value={rc.latest_version}
                onChange={(e) =>
                  setRc({ ...rc, latest_version: e.target.value })
                }
              />
            </label>
            <label className="rc-row">
              <input
                type="checkbox"
                checked={rc.force_update}
                onChange={(e) =>
                  setRc({ ...rc, force_update: e.target.checked })
                }
              />
              تحديث إجباري
            </label>
            <label className="acct-label">
              رسالة التحديث
              <textarea
                value={rc.update_message_ar}
                onChange={(e) =>
                  setRc({ ...rc, update_message_ar: e.target.value })
                }
                rows={2}
              />
            </label>
            <label className="acct-label">
              رابط التحميل
              <input
                type="url"
                value={rc.update_download_url}
                onChange={(e) =>
                  setRc({ ...rc, update_download_url: e.target.value })
                }
                dir="ltr"
              />
            </label>
          </fieldset>

          <fieldset className="acct-fieldset" disabled={busy}>
            <legend>إعلان عام</legend>
            <label className="acct-label">
              العنوان
              <input
                type="text"
                value={rc.announcement_title_ar}
                onChange={(e) =>
                  setRc({ ...rc, announcement_title_ar: e.target.value })
                }
              />
            </label>
            <label className="acct-label">
              النص
              <textarea
                value={rc.announcement_body_ar}
                onChange={(e) =>
                  setRc({ ...rc, announcement_body_ar: e.target.value })
                }
                rows={3}
              />
            </label>
            <label className="acct-label">
              رابط اختياري
              <input
                type="url"
                value={rc.announcement_url}
                onChange={(e) =>
                  setRc({ ...rc, announcement_url: e.target.value })
                }
                dir="ltr"
              />
            </label>
          </fieldset>

          <div className="acct-form-row">
            <button
              type="button"
              className="btn-ghost"
              disabled={busy}
              onClick={() =>
                setRc({
                  ...(data?.remoteConfig ?? defaultAppRemoteConfig()),
                })
              }
            >
              إعادة من الخادم
            </button>
            <button type="submit" className="btn-primary" disabled={busy}>
              {busy ? "جاري الحفظ…" : "حفظ الإعدادات"}
            </button>
          </div>
        </form>
      ) : null}

      {!loading && !loadErr && !rc ? (
        <div className="dash-state muted">لا توجد إعدادات للعرض.</div>
      ) : null}
    </div>
  );
}
