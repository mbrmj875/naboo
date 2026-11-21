"use client";

import { useEffect, useRef, useState } from "react";
import { FieldShell } from "@/components/field/field-shell";
import { BasraMap } from "@/components/field/basra-map";
import { newClientOpId } from "@/lib/field-client-id";
import { computeOperationHashClient } from "@/lib/field-hash-client";
import {
  BASRA_CENTER,
  checkVisitGeo,
  GPS_WEAK_ACCURACY_M,
} from "@/lib/field-geo";
import { FIELD_MESSAGES } from "@/lib/field-messages";
import {
  clearVisitDraft,
  enqueueOp,
  loadVisitDraft,
  putVisitCache,
  saveVisitDraft,
} from "@/lib/field-offline";
import { syncQueue } from "@/lib/field-sync";
import { VoiceNotesField } from "@/components/field/voice-notes-field";
import { reverseGeocode } from "@/lib/field-geocode";
import { readDevicePosition } from "@/lib/field-device-position";

const INTERESTS = [
  { value: "rejected", label: FIELD_MESSAGES.INTEREST_REJECTED },
  { value: "warm", label: FIELD_MESSAGES.INTEREST_WARM },
  { value: "interested", label: FIELD_MESSAGES.INTEREST_INTERESTED },
  { value: "purchased", label: FIELD_MESSAGES.INTEREST_PURCHASED },
] as const;

type Props = {
  stayAfterSave?: boolean;
  title?: string;
};

async function ensureGeoPermission(): Promise<
  "granted" | "denied" | "prompt" | "unsupported"
> {
  if (typeof navigator === "undefined" || !navigator.geolocation) {
    return "unsupported";
  }
  try {
    const perms = (navigator as Navigator & { permissions?: Permissions })
      .permissions;
    if (perms?.query) {
      const status = await perms.query({
        name: "geolocation" as PermissionName,
      });
      return status.state as "granted" | "denied" | "prompt";
    }
  } catch {
    /* ignore */
  }
  return "prompt";
}

export function VisitForm({
  stayAfterSave = true,
  title = "محل جديد",
}: Props) {
  const [shop_name, setShop] = useState("");
  const [owner_name, setOwner] = useState("");
  const [phone, setPhone] = useState("");
  const [notes, setNotes] = useState("");
  const [interest, setInterest] =
    useState<(typeof INTERESTS)[number]["value"]>("warm");
  const [lat, setLat] = useState<number | null>(null);
  const [lng, setLng] = useState<number | null>(null);
  const [accuracy, setAccuracy] = useState<number | null>(null);
  const [location_source, setSource] = useState<"gps" | "manual">("gps");
  const [locationReady, setLocationReady] = useState(false);
  const [mapOpen, setMapOpen] = useState(false);
  const [addressLabel, setAddressLabel] = useState<string | null>(null);
  const [addressLoading, setAddressLoading] = useState(false);
  const [geo_confirmed, setGeoConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [warn, setWarn] = useState<string | null>(null);
  const [okMsg, setOkMsg] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [draftPrompt, setDraftPrompt] = useState(false);
  const [locating, setLocating] = useState(false);
  const [mapCenterTick, setMapCenterTick] = useState(0);
  const autoLocateAttempted = useRef(false);

  useEffect(() => {
    (async () => {
      const draft = await loadVisitDraft();
      if (draft?.data) setDraftPrompt(true);
    })();
  }, []);

  useEffect(() => {
    const t = setInterval(() => {
      void saveVisitDraft({
        shop_name,
        owner_name,
        phone,
        notes,
        interest,
        lat,
        lng,
        location_source,
        locationReady,
      });
    }, 10_000);
    return () => clearInterval(t);
  }, [
    shop_name,
    owner_name,
    phone,
    notes,
    interest,
    lat,
    lng,
    location_source,
    locationReady,
  ]);

  const applyDevicePosition = async (opts?: {
    openMap?: boolean;
    silentFail?: boolean;
  }): Promise<boolean> => {
    setLocating(true);
    setWarn(null);
    setError(null);

    const perm = await ensureGeoPermission();
    if (perm === "unsupported") {
      setWarn("الجهاز لا يدعم الموقع");
      setLocating(false);
      if (opts?.openMap) {
        setSource("manual");
        setLat(BASRA_CENTER.lat);
        setLng(BASRA_CENTER.lng);
        setMapOpen(true);
      }
      return false;
    }
    if (perm === "denied") {
      if (!opts?.silentFail) {
        setError("اسمح بالموقع من إعدادات الهاتف ثم أعد المحاولة");
      }
      setLocating(false);
      return false;
    }

    const result = await readDevicePosition();
    setLocating(false);

    if (!result.ok) {
      if (result.error === "denied") {
        setError("اسمح بالموقع من إعدادات الهاتف ثم أعد المحاولة");
        return false;
      }
      if (!opts?.silentFail) {
        setWarn(
          result.error === "timeout"
            ? "تعذّر الموقع — فعّل GPS أو حدّد على الخريطة"
            : "تعذّر الموقع — حدّد على الخريطة",
        );
      }
      if (opts?.openMap) {
        setSource("manual");
        if (lat == null || lng == null) {
          setLat(BASRA_CENTER.lat);
          setLng(BASRA_CENTER.lng);
        }
        setMapOpen(true);
      }
      return false;
    }

    const { position } = result;
    setLat(position.lat);
    setLng(position.lng);
    setAccuracy(position.accuracy);
    setSource("gps");
    setLocationReady(true);
    setMapCenterTick((n) => n + 1);

    if (
      position.accuracy != null &&
      position.accuracy > GPS_WEAK_ACCURACY_M
    ) {
      setWarn(FIELD_MESSAGES.GPS_WEAK);
    }
    const geo = checkVisitGeo({
      lat: position.lat,
      lng: position.lng,
      gpsAccuracy: position.accuracy,
    });
    if (geo.code === "GEO_CONFIRM_REQUIRED") {
      setWarn(FIELD_MESSAGES.OUT_OF_BASRA);
    }
    if (opts?.openMap) setMapOpen(true);
    return true;
  };

  const applyGps = async () => {
    setOkMsg(null);
    await applyDevicePosition({ openMap: true });
  };

  useEffect(() => {
    if (!mapOpen || lat == null || lng == null) return;
    const ac = new AbortController();
    setAddressLoading(true);
    const t = setTimeout(() => {
      void reverseGeocode(lat, lng, ac.signal)
        .then((r) => {
          if (!ac.signal.aborted) {
            setAddressLabel(r?.shortLabel || r?.displayName || null);
          }
        })
        .catch(() => {
          if (!ac.signal.aborted) setAddressLabel(null);
        })
        .finally(() => {
          if (!ac.signal.aborted) setAddressLoading(false);
        });
    }, 350);
    return () => {
      ac.abort();
      clearTimeout(t);
    };
  }, [mapOpen, lat, lng]);

  useEffect(() => {
    if (!mapOpen) {
      autoLocateAttempted.current = false;
      return;
    }
    if (autoLocateAttempted.current) return;
    autoLocateAttempted.current = true;
    if (location_source === "gps" && lat != null && lng != null) {
      setMapCenterTick((n) => n + 1);
      return;
    }
    void applyDevicePosition({ silentFail: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mapOpen]);

  const locateOnMap = () => {
    void applyDevicePosition();
  };

  const restoreDraft = async () => {
    const draft = await loadVisitDraft();
    if (!draft?.data) return;
    const d = draft.data;
    setShop(String(d.shop_name ?? ""));
    setOwner(String(d.owner_name ?? ""));
    setPhone(String(d.phone ?? ""));
    setNotes(String(d.notes ?? ""));
    if (d.interest) setInterest(d.interest as typeof interest);
    if (typeof d.lat === "number") setLat(d.lat);
    if (typeof d.lng === "number") setLng(d.lng);
    if (d.locationReady) setLocationReady(true);
    setDraftPrompt(false);
  };

  const resetForm = () => {
    setShop("");
    setOwner("");
    setPhone("");
    setNotes("");
    setInterest("warm");
    setLat(null);
    setLng(null);
    setAccuracy(null);
    setLocationReady(false);
    setGeoConfirmed(false);
    setWarn(null);
    setError(null);
    setAddressLabel(null);
    setSource("gps");
  };

  const save = async () => {
    setError(null);
    setOkMsg(null);
    if (!shop_name.trim() || !owner_name.trim()) {
      setError("أدخل اسم المحل وصاحبه");
      return;
    }
    if (!locationReady || lat == null || lng == null) {
      setError(FIELD_MESSAGES.LOCATION_NEEDED);
      return;
    }
    const geo = checkVisitGeo({
      lat,
      lng,
      gpsAccuracy: accuracy,
      geoConfirmed: geo_confirmed,
    });
    if (!geo.ok) {
      if (geo.code === "GEO_CONFIRM_REQUIRED") {
        setWarn(FIELD_MESSAGES.GEO_CONFIRM_REQUIRED);
        setError("أكّد الموقع للمتابعة");
        return;
      }
      setError(FIELD_MESSAGES.OUT_OF_GOVERNORATE);
      return;
    }

    const label = INTERESTS.find((i) => i.value === interest)?.label ?? interest;
    if (!window.confirm(`حفظ بحالة «${label}»؟`)) return;

    setSaving(true);
    try {
      const client_op_id = newClientOpId();
      const client_updated_at = new Date().toISOString();
      const payload = {
        shop_name: shop_name.trim(),
        owner_name: owner_name.trim(),
        phone: phone.trim() || null,
        lat,
        lng,
        interest,
        notes: notes.trim() || null,
        location_source,
        gps_accuracy: accuracy,
        geo_confirmed,
      };
      const operation_hash = await computeOperationHashClient(
        "create_visit",
        payload,
        null,
      );
      const localKey = `local-${client_op_id}`;
      await putVisitCache({
        id: localKey,
        local_key: localKey,
        shop_name: payload.shop_name,
        owner_name: payload.owner_name,
        phone: payload.phone,
        lat,
        lng,
        interest,
        notes: payload.notes,
        visited_at: client_updated_at,
        sync_status: "pending",
        location_source,
        geo_warning: geo.geoWarning,
      });
      await enqueueOp({
        client_op_id,
        op: "create_visit",
        payload,
        operation_hash,
        client_updated_at,
      });
      await clearVisitDraft();
      void syncQueue();
      setOkMsg(FIELD_MESSAGES.VISIT_SAVED);
      if (stayAfterSave) resetForm();
    } finally {
      setSaving(false);
    }
  };

  const pickLat = lat ?? BASRA_CENTER.lat;
  const pickLng = lng ?? BASRA_CENTER.lng;
  const locSummary =
    addressLabel ||
    (lat != null && lng != null
      ? `${lat.toFixed(5)}, ${lng.toFixed(5)}`
      : null);

  return (
    <FieldShell title={title}>
      <div className="field-panel">
        {draftPrompt && (
          <div className="field-banner">
            <span>مسودة سابقة</span>
            <div className="field-banner-actions">
              <button
                type="button"
                className="field-text-btn primary"
                onClick={() => void restoreDraft()}
              >
                متابعة
              </button>
              <button
                type="button"
                className="field-text-btn"
                onClick={() => {
                  setDraftPrompt(false);
                  void clearVisitDraft();
                }}
              >
                تجاهل
              </button>
            </div>
          </div>
        )}

        {okMsg && <div className="field-alert ok">{okMsg}</div>}
        {warn && <div className="field-alert warn">{warn}</div>}
        {error && <div className="field-alert err">{error}</div>}

        <section className="field-card field-stack">
          <div className="field-field">
            <label className="field-label" htmlFor="shop_name">
              اسم المحل
            </label>
            <input
              id="shop_name"
              className="field-input"
              value={shop_name}
              onChange={(e) => setShop(e.target.value)}
              placeholder="محل الأمل"
              autoComplete="organization"
            />
          </div>
          <div className="field-field">
            <label className="field-label" htmlFor="owner_name">
              صاحب المحل
            </label>
            <input
              id="owner_name"
              className="field-input"
              value={owner_name}
              onChange={(e) => setOwner(e.target.value)}
              placeholder="الاسم"
              autoComplete="name"
            />
          </div>
          <div className="field-field">
            <label className="field-label" htmlFor="phone">
              الهاتف
            </label>
            <input
              id="phone"
              className="field-input"
              inputMode="tel"
              dir="ltr"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="07XXXXXXXXX"
              autoComplete="tel"
            />
          </div>
        </section>

        <section className="field-card">
          {locationReady && locSummary ? (
            <button
              type="button"
              className="field-loc-row"
              onClick={() => setMapOpen(true)}
            >
              <span className="field-loc-dot ok" aria-hidden />
              <span className="field-loc-text">
                <strong>الموقع جاهز</strong>
                <small>{locSummary}</small>
              </span>
              <span className="field-loc-edit">تعديل</span>
            </button>
          ) : (
            <button
              type="button"
              className="field-btn primary block"
              disabled={locating}
              onClick={() => void applyGps()}
            >
              {locating ? "جاري التحديد…" : "تحديد الموقع"}
            </button>
          )}
        </section>

        <section className="field-card">
          <div className="field-interest-grid" role="group" aria-label="الحالة">
            {INTERESTS.map((i) => (
              <button
                key={i.value}
                type="button"
                className={`field-interest-btn ${interest === i.value ? `active ${i.value}` : ""}`}
                onClick={() => setInterest(i.value)}
              >
                {i.label}
              </button>
            ))}
          </div>
        </section>

        <section className="field-card">
          <VoiceNotesField value={notes} onChange={setNotes} placeholder="ملاحظة…" />
        </section>

        {warn?.includes("بعيد") && (
          <label className="field-confirm-row">
            <input
              type="checkbox"
              checked={geo_confirmed}
              onChange={(e) => setGeoConfirmed(e.target.checked)}
            />
            <span>أؤكد صحة الموقع</span>
          </label>
        )}

        <button
          type="button"
          className="field-btn primary block field-save"
          disabled={saving}
          onClick={() => void save()}
        >
          {saving ? "جاري الحفظ…" : "حفظ"}
        </button>
      </div>

      {mapOpen && (
        <div className="field-map-modal" role="dialog" aria-modal="true">
          <div className="field-map-modal-bar">
            <div className="field-map-address">
              {addressLoading
                ? "…"
                : addressLabel ||
                  (lat != null && lng != null
                    ? `${lat.toFixed(5)}, ${lng.toFixed(5)}`
                    : "اختر النقطة")}
            </div>
            <div className="field-map-bar-actions">
              <button
                type="button"
                className="field-btn ghost"
                onClick={() => setMapOpen(false)}
              >
                إلغاء
              </button>
              <button
                type="button"
                className="field-btn primary"
                onClick={() => {
                  setLocationReady(true);
                  setMapOpen(false);
                }}
              >
                تأكيد
              </button>
            </div>
          </div>
          <div className="field-map-modal-body">
            <BasraMap
              visits={[]}
              pickMode
              pickLatLng={{
                lat: pickLat,
                lng: pickLng,
                accuracy: location_source === "gps" ? accuracy : null,
              }}
              centerOn={{
                lat: pickLat,
                lng: pickLng,
                zoom: 18,
                tick: mapCenterTick,
              }}
              onPick={(la, ln) => {
                setLat(la);
                setLng(ln);
                setAccuracy(null);
                setSource("manual");
                setLocationReady(true);
                setWarn(null);
              }}
            />
            <button
              type="button"
              className="field-map-locate"
              disabled={locating}
              onClick={locateOnMap}
              aria-label="موقعي"
            >
              <span className="field-map-locate-ico" aria-hidden>
                ◎
              </span>
            </button>
          </div>
        </div>
      )}
    </FieldShell>
  );
}
