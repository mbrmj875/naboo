"use client";

import { useEffect, useMemo, useState } from "react";
import type { MenuImageRow, MenuItemRow, PublishedTheme } from "@/lib/restaurant-menu";
import { chromeForPreset, formatFils } from "@/lib/restaurant-menu";

type Props = {
  tenantSlug: string;
  tableSlug?: string;
  theme: PublishedTheme;
  items: MenuItemRow[];
  images: MenuImageRow[];
  categories: { id: number; name_ar: string }[];
  functionsBaseUrl: string;
  anonKey?: string;
};

type CartLine = {
  menu_item_id: number;
  qty: number;
  name_ar: string;
  price_fils: number;
};

type Tab = "home" | "cart" | "orders";

type PastOrder = {
  id: string;
  at: string;
  total_fils: number;
  lines: { name_ar: string; qty: number }[];
  status_ar: string;
};

type GuestProfile = {
  full_name: string;
  nickname: string;
  phone: string;
  address1: string;
  address2: string;
  landmark: string;
  lat: number | null;
  lng: number | null;
};

const EMPTY_PROFILE: GuestProfile = {
  full_name: "",
  nickname: "",
  phone: "",
  address1: "",
  address2: "",
  landmark: "",
  lat: null,
  lng: null,
};

const PROFILE_KEY = "naboo.menu.guestProfile.v1";

function ordersKey(slug: string) {
  return `naboo.menu.orders.${slug}.v1`;
}

function cartKey(slug: string) {
  return `naboo.menu.cart.${slug}.v1`;
}

function readCart(slug: string): CartLine[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(cartKey(slug));
    if (!raw) return [];
    const parsed = JSON.parse(raw) as CartLine[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

function writeCart(slug: string, lines: CartLine[]) {
  try {
    if (lines.length === 0) {
      localStorage.removeItem(cartKey(slug));
    } else {
      localStorage.setItem(cartKey(slug), JSON.stringify(lines));
    }
  } catch {
    /* ignore */
  }
}

function readProfile(): GuestProfile {
  if (typeof window === "undefined") return EMPTY_PROFILE;
  try {
    const raw = localStorage.getItem(PROFILE_KEY);
    if (!raw) return EMPTY_PROFILE;
    const parsed = JSON.parse(raw) as Partial<GuestProfile>;
    return {
      full_name: String(parsed.full_name ?? ""),
      nickname: String(parsed.nickname ?? ""),
      phone: String(parsed.phone ?? ""),
      address1: String(parsed.address1 ?? ""),
      address2: String(parsed.address2 ?? ""),
      landmark: String(parsed.landmark ?? ""),
      lat: typeof parsed.lat === "number" ? parsed.lat : null,
      lng: typeof parsed.lng === "number" ? parsed.lng : null,
    };
  } catch {
    return EMPTY_PROFILE;
  }
}

function writeProfile(p: GuestProfile) {
  try {
    localStorage.setItem(PROFILE_KEY, JSON.stringify(p));
  } catch {
    /* ignore quota */
  }
}

function readOrders(slug: string): PastOrder[] {
  if (typeof window === "undefined") return [];
  try {
    const raw = localStorage.getItem(ordersKey(slug));
    if (!raw) return [];
    const parsed = JSON.parse(raw) as PastOrder[];
    return Array.isArray(parsed) ? parsed.slice(0, 20) : [];
  } catch {
    return [];
  }
}

function writeOrders(slug: string, list: PastOrder[]) {
  try {
    localStorage.setItem(ordersKey(slug), JSON.stringify(list.slice(0, 20)));
  } catch {
    /* ignore */
  }
}

function normalizeIqPhone(raw: string): string | null {
  const digits = raw.replace(/[^\d+]/g, "").trim();
  if (/^07\d{9}$/.test(digits)) return `+964${digits.slice(1)}`;
  if (/^\+9647\d{9}$/.test(digits)) return digits;
  if (/^9647\d{9}$/.test(digits)) return `+${digits}`;
  if (/^\+?\d{10,15}$/.test(digits)) return digits.startsWith("+") ? digits : `+${digits}`;
  return null;
}

export function PublicMenuClient({
  tenantSlug,
  tableSlug,
  theme,
  items,
  images,
  categories,
  functionsBaseUrl,
  anonKey,
}: Props) {
  const [tab, setTab] = useState<Tab>("home");
  const [search, setSearch] = useState("");
  const [cart, setCart] = useState<CartLine[]>([]);
  const [orders, setOrders] = useState<PastOrder[]>([]);
  const [detail, setDetail] = useState<MenuItemRow | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [sessionId, setSessionId] = useState<number | null>(null);
  const [categoryId, setCategoryId] = useState<number | "all">("all");
  const [checkoutOpen, setCheckoutOpen] = useState(false);
  const [profileOpen, setProfileOpen] = useState(false);
  const [fullName, setFullName] = useState("");
  const [nickname, setNickname] = useState("");
  const [phone, setPhone] = useState("");
  const [address1, setAddress1] = useState("");
  const [address2, setAddress2] = useState("");
  const [landmark, setLandmark] = useState("");
  const [gps, setGps] = useState<{ lat: number; lng: number } | null>(null);
  const [gpsMsg, setGpsMsg] = useState<string | null>(null);
  const [gpsBusy, setGpsBusy] = useState(false);
  const [hydrated, setHydrated] = useState(false);

  const showPrices = theme.toggles?.show_prices !== false;
  const showDesc = theme.toggles?.show_item_descriptions !== false;
  const isTable = Boolean(tableSlug);
  const needsDeliveryContact = !isTable;
  const chrome = chromeForPreset(theme.preset_key);

  const itemIdsKey = useMemo(
    () => items.map((i) => i.id).sort((a, b) => a - b).join(","),
    [items],
  );

  useEffect(() => {
    // عزل صارم: عند تغيير المطعم تُحمَّل سلة/طلبات ذلك الـslug فقط.
    const allowed = new Set(
      itemIdsKey
        ? itemIdsKey.split(",").map((x) => Number(x))
        : [],
    );
    const loaded = readCart(tenantSlug).filter((c) =>
      allowed.size === 0 ? true : allowed.has(c.menu_item_id),
    );
    setCart(loaded);
    setOrders(readOrders(tenantSlug));
    setSessionId(null);
    setDetail(null);
    setTab("home");
    setMessage(null);
    const p = readProfile();
    setFullName(p.full_name);
    setNickname(p.nickname);
    setPhone(p.phone);
    setAddress1(p.address1);
    setAddress2(p.address2);
    setLandmark(p.landmark);
    if (p.lat != null && p.lng != null) {
      setGps({ lat: p.lat, lng: p.lng });
    } else {
      setGps(null);
    }
    setHydrated(true);
  }, [tenantSlug, tableSlug, itemIdsKey]);

  useEffect(() => {
    if (!hydrated) return;
    writeCart(tenantSlug, cart);
  }, [cart, tenantSlug, hydrated]);

  const profileInitial = useMemo(() => {
    const n = (nickname || fullName || "").trim();
    return n ? n.slice(0, 1) : "؟";
  }, [nickname, fullName]);

  const filtered = useMemo(() => {
    const q = search.trim();
    let list = items;
    if (categoryId !== "all") {
      list = list.filter((i) => i.category_id === categoryId);
    }
    if (q) {
      list = list.filter(
        (i) =>
          i.name_ar.includes(q) ||
          (i.description_ar?.includes(q) ?? false),
      );
    }
    return list;
  }, [items, categoryId, search]);

  const cartQty = cart.reduce((a, c) => a + c.qty, 0);
  const cartTotal = cart.reduce((a, c) => a + c.qty * c.price_fils, 0);

  function currentProfile(): GuestProfile {
    return {
      full_name: fullName.trim(),
      nickname: nickname.trim(),
      phone: phone.trim(),
      address1: address1.trim(),
      address2: address2.trim(),
      landmark: landmark.trim(),
      lat: gps?.lat ?? null,
      lng: gps?.lng ?? null,
    };
  }

  function saveProfileFromForm() {
    const p = currentProfile();
    writeProfile(p);
    return p;
  }

  function imagesFor(itemId: number) {
    return images
      .filter((img) => img.menu_item_id === itemId)
      .sort((a, b) => a.sort_order - b.sort_order);
  }

  function addToCart(item: MenuItemRow, qty = 1) {
    // لا تُضاف أصناف إلا من منيو هذا الـtenant المعروض.
    if (!items.some((i) => i.id === item.id)) {
      setMessage("هذا الصنف لا ينتمي لهذا المطعم.");
      return;
    }
    setCart((prev) => {
      const idx = prev.findIndex((c) => c.menu_item_id === item.id);
      if (idx >= 0) {
        const next = [...prev];
        next[idx] = { ...next[idx], qty: next[idx].qty + qty };
        return next;
      }
      return [
        ...prev,
        {
          menu_item_id: item.id,
          qty,
          name_ar: item.name_ar,
          price_fils: item.price_fils,
        },
      ];
    });
    setMessage(null);
  }

  function setQty(menuItemId: number, qty: number) {
    setCart((prev) => {
      if (qty <= 0) return prev.filter((c) => c.menu_item_id !== menuItemId);
      return prev.map((c) =>
        c.menu_item_id === menuItemId ? { ...c, qty } : c,
      );
    });
  }

  function requestGps() {
    if (typeof navigator === "undefined" || !navigator.geolocation) {
      setGpsMsg("المتصفح لا يدعم تحديد الموقع — اكتب العنوان يدوياً.");
      return;
    }
    setGpsBusy(true);
    setGpsMsg("نحتاج إذنك لتحديد موقع التوصيل على الخريطة…");
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setGps({
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
        });
        setGpsMsg("تم حفظ موقعك. يمكنك أيضاً كتابة العنوان للتوضيح.");
        setGpsBusy(false);
      },
      (err) => {
        if (err.code === err.PERMISSION_DENIED) {
          setGpsMsg(
            "لم يُسمح بالوصول للموقع. اكتب العنوان يدوياً أو فعّل الإذن من إعدادات المتصفح.",
          );
        } else {
          setGpsMsg("تعذّر تحديد الموقع. اكتب العنوان يدوياً.");
        }
        setGpsBusy(false);
      },
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 60000 },
    );
  }

  async function submitOrder() {
    if (!cart.length || busy) return;

    if (needsDeliveryContact) {
      const normalized = normalizeIqPhone(phone);
      if (!normalized) {
        setMessage("أدخل رقم هاتف صحيح للتواصل مع عامل التوصيل.");
        setCheckoutOpen(true);
        setTab("cart");
        return;
      }
      if (!gps && !address1.trim()) {
        setMessage("حدّد موقعك عبر GPS أو اكتب عنوان التوصيل.");
        setCheckoutOpen(true);
        setTab("cart");
        return;
      }
    }

    setBusy(true);
    setMessage(null);
    try {
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
      };
      if (anonKey) {
        headers.apikey = anonKey;
        headers.Authorization = `Bearer ${anonKey}`;
      }

      const profile = saveProfileFromForm();
      const guestPayload =
        needsDeliveryContact || profile.phone || profile.full_name
          ? {
              phone: normalizeIqPhone(phone) ?? (phone.trim() || null),
              full_name: profile.full_name || null,
              nickname: profile.nickname || null,
              address_line1: profile.address1 || null,
              address_line2: profile.address2 || null,
              landmark: profile.landmark || null,
              lat: profile.lat,
              lng: profile.lng,
            }
          : undefined;

      const res = await fetch(`${functionsBaseUrl}/restaurant-create-order`, {
        method: "POST",
        headers,
        body: JSON.stringify({
          tenant_slug: tenantSlug,
          table_slug: tableSlug,
          channel: tableSlug ? "qr_table" : "public_link",
          items: cart.map((c) => ({
            menu_item_id: c.menu_item_id,
            qty: c.qty,
          })),
          guest: guestPayload,
        }),
      });
      const data = await res.json();
      if (!res.ok) {
        if (data.error === "ingredient_shortage") {
          setMessage("عذراً، أحد المكوّنات غير متوفر حالياً.");
        } else if (data.error === "table_awaiting_payment") {
          setMessage("الطاولة بانتظار الدفع — لا يمكن إضافة طلب.");
        } else if (data.error === "rate_limited") {
          setMessage("تم تجاوز حد الطلبات — حاول لاحقاً.");
        } else if (data.error === "guest_phone_required") {
          setMessage("رقم الهاتف مطلوب لطلبات التوصيل.");
          setCheckoutOpen(true);
        } else if (data.error === "guest_address_required") {
          setMessage("العنوان أو موقع GPS مطلوب للتوصيل.");
          setCheckoutOpen(true);
        } else {
          setMessage("تعذّر إرسال الطلب. تحقق من الاتصال.");
        }
        return;
      }
      const snapshot: PastOrder = {
        id: String(data.order_id ?? data.session_id ?? Date.now()),
        at: new Date().toISOString(),
        total_fils: cartTotal,
        lines: cart.map((c) => ({ name_ar: c.name_ar, qty: c.qty })),
        status_ar: isTable ? "في المطبخ" : "بانتظار التواصل للتوصيل",
      };
      setOrders((prev) => {
        const next = [snapshot, ...prev].slice(0, 20);
        writeOrders(tenantSlug, next);
        return next;
      });
      setSessionId(data.session_id ?? null);
      setCart([]);
      setCheckoutOpen(false);
      setTab("orders");
      setMessage(
        isTable
          ? "تم إرسال طلبك إلى المطبخ — تابع من «طلباتي»."
          : "تم استلام طلبك — سنتواصل على رقمك. تابع الحالة من «طلباتي».",
      );
    } catch {
      setMessage("الخدمة عبر الجوال متوقفة الآن — الرجاء المحاولة لاحقاً.");
    } finally {
      setBusy(false);
    }
  }

  async function requestBill() {
    if (!sessionId || busy) return;
    setBusy(true);
    try {
      const headers: Record<string, string> = {
        "Content-Type": "application/json",
      };
      if (anonKey) {
        headers.apikey = anonKey;
        headers.Authorization = `Bearer ${anonKey}`;
      }
      const res = await fetch(`${functionsBaseUrl}/restaurant-request-bill`, {
        method: "POST",
        headers,
        body: JSON.stringify({
          session_id: sessionId,
          tenant_slug: tenantSlug,
        }),
      });
      if (!res.ok) {
        setMessage("تعذّر طلب الحساب — تحقق من الاتصال.");
      } else {
        setMessage("تم إبلاغ النادل بطلب الحساب.");
      }
    } catch {
      setMessage("تعذّر طلب الحساب — تحقق من الاتصال.");
    } finally {
      setBusy(false);
    }
  }

  function renderContactFields(compact?: boolean) {
    return (
      <div className={compact ? "rst-checkout rst-checkout--profile" : "rst-checkout"}>
        {!compact ? <h3>بيانات التوصيل</h3> : null}
        {!compact ? (
          <p className="rst-checkout-hint">
            لأنك دخلت عبر الرابط من خارج المطعم، نحتاج رقمك ليتواصل معك عامل
            التوصيل، وعنوان الاستلام. تُحفظ في ملفك الشخصي للمرات القادمة.
          </p>
        ) : (
          <p className="rst-checkout-hint">
            تُحفظ هذه البيانات على جهازك وتُملأ تلقائياً عند الطلب.
          </p>
        )}
        <label className="rst-field">
          <span>الاسم</span>
          <input
            type="text"
            placeholder="اسمك الكامل"
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            autoComplete="name"
          />
        </label>
        <label className="rst-field">
          <span>اللقب / الاسم المستعار</span>
          <input
            type="text"
            placeholder="اختياري"
            value={nickname}
            onChange={(e) => setNickname(e.target.value)}
          />
        </label>
        <label className="rst-field">
          <span>رقم الهاتف</span>
          <input
            type="tel"
            inputMode="tel"
            placeholder="07XXXXXXXXX"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            autoComplete="tel"
          />
        </label>
        <label className="rst-field">
          <span>العنوان (سطر 1)</span>
          <input
            type="text"
            placeholder="المحافظة · المنطقة"
            value={address1}
            onChange={(e) => setAddress1(e.target.value)}
            autoComplete="street-address"
          />
        </label>
        <label className="rst-field">
          <span>العنوان (سطر 2) — اختياري</span>
          <input
            type="text"
            placeholder="تفاصيل إضافية للوصول"
            value={address2}
            onChange={(e) => setAddress2(e.target.value)}
          />
        </label>
        <label className="rst-field">
          <span>أقرب نقطة دالة</span>
          <input
            type="text"
            placeholder="معلم معروف قريب"
            value={landmark}
            onChange={(e) => setLandmark(e.target.value)}
          />
        </label>
        <div className="rst-gps-block">
          <button
            type="button"
            className="rst-gps-btn"
            disabled={gpsBusy}
            onClick={requestGps}
          >
            {gps ? "تحديث موقعي من GPS" : "السماح بتحديد موقعي (GPS)"}
          </button>
          {gps ? (
            <p className="rst-gps-ok">
              موقع محفوظ: {gps.lat.toFixed(5)}, {gps.lng.toFixed(5)}
            </p>
          ) : null}
          {gpsMsg ? <p className="rst-gps-msg">{gpsMsg}</p> : null}
        </div>
      </div>
    );
  }

  const detailImages = detail ? imagesFor(detail.id) : [];

  return (
    <div className="rst-menu rst-menu--app" data-rst-chrome={chrome}>
      {!detail ? (
        <div className="rst-search-wrap">
          <div className="rst-search-row">
            <button
              type="button"
              className="rst-search-action rst-search-action--category"
              aria-label="تصفية حسب التصنيف"
              title="التصنيف"
            >
              الكل
              <span aria-hidden="true">▾</span>
            </button>
            <label className="rst-search">
              <span className="sr-only">بحث في المنيو</span>
              <span className="rst-search-icon" aria-hidden="true">
                ⌕
              </span>
              <input
                type="search"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="ابحث عن طبق أو مشروب…"
                enterKeyHint="search"
                autoComplete="off"
              />
              <button
                type="button"
                className="rst-search-mic"
                aria-label="بحث صوتي"
                title="بحث صوتي"
              >
                🎤
              </button>
            </label>
            <button
              type="button"
              className="rst-search-action rst-search-action--filter"
              aria-label="فلاتر القائمة"
              title="فلاتر"
            >
              ⚙
            </button>
            <button
              type="button"
              className="rst-search-action rst-search-action--submit"
              aria-label="بحث"
              title="بحث"
            >
              ⌕
            </button>
            <button
              type="button"
              className="rst-profile-btn"
              aria-label="الملف الشخصي"
              title={
                hydrated && (fullName || nickname)
                  ? fullName || nickname
                  : "الملف الشخصي"
              }
              onClick={() => setProfileOpen(true)}
            >
              <span aria-hidden>{profileInitial}</span>
            </button>
          </div>
        </div>
      ) : null}

      {profileOpen ? (
        <div
          className="rst-profile-sheet"
          role="dialog"
          aria-modal="true"
          aria-label="الملف الشخصي"
          onClick={() => setProfileOpen(false)}
        >
          <div
            className="rst-profile-sheet-inner"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="rst-profile-grab" aria-hidden="true" />
            <div className="rst-profile-hero" aria-hidden="true">
              <span className="rst-profile-avatar">
                {(fullName || nickname || "ض").trim().charAt(0)}
              </span>
              <p className="rst-profile-hero-name">
                {fullName || nickname || "ضيف المنيو"}
              </p>
            </div>
            <header className="rst-profile-head">
              <h2>ملفي الشخصي</h2>
              <button
                type="button"
                className="rst-close"
                onClick={() => {
                  saveProfileFromForm();
                  setProfileOpen(false);
                }}
              >
                إغلاق
              </button>
            </header>
            {renderContactFields(true)}
            <button
              type="button"
              className="rst-submit rst-submit--block rst-profile-save"
              onClick={() => {
                saveProfileFromForm();
                setProfileOpen(false);
                setMessage("تم حفظ ملفك الشخصي على هذا الجهاز.");
              }}
            >
              حفظ الملف الشخصي
            </button>
          </div>
        </div>
      ) : null}

      {tab === "home" && !detail ? (
        <div className="rst-home-body">
          <nav className="rst-cats" aria-label="أقسام المنيو">
            <button
              type="button"
              className={categoryId === "all" ? "active" : undefined}
              onClick={() => setCategoryId("all")}
            >
              <span className="rst-cat-ico" aria-hidden="true">
                ▦
              </span>
              <span className="rst-cat-lbl">الكل</span>
            </button>
            {categories.map((c) => (
              <button
                key={c.id}
                type="button"
                className={categoryId === c.id ? "active" : undefined}
                onClick={() => setCategoryId(c.id)}
              >
                <span className="rst-cat-ico" aria-hidden="true">
                  ○
                </span>
                <span className="rst-cat-lbl">{c.name_ar}</span>
              </button>
            ))}
          </nav>

          {filtered.length === 0 ? (
            <p className="rst-empty">لا نتائج مطابقة للبحث.</p>
          ) : (
            <ul className="rst-list" data-rst-chrome={chrome}>
              {filtered.map((item, index) => {
                const imgs = imagesFor(item.id);
                const primary = imgs.find((i) => i.is_primary) ?? imgs[0];
                const src = primary?.image_url ?? item.image_url;
                return (
                  <li key={item.id} className="rst-card">
                    <button
                      type="button"
                      className="rst-card-hit"
                      onClick={() => setDetail(item)}
                    >
                      <div className="rst-thumb-wrap">
                        {src ? (
                          // eslint-disable-next-line @next/next/no-img-element
                          <img
                            src={src}
                            alt={primary?.alt_ar ?? item.name_ar}
                            loading={index < 4 ? "eager" : "lazy"}
                            fetchPriority={index === 0 ? "high" : "auto"}
                            className="rst-thumb"
                          />
                        ) : (
                          <span className="rst-thumb-empty" aria-hidden />
                        )}
                      </div>
                      <div className="rst-card-body">
                        <span className="rst-item-name">{item.name_ar}</span>
                        {showDesc && item.description_ar ? (
                          <p className="rst-desc">{item.description_ar}</p>
                        ) : null}
                        <div className="rst-row">
                          {showPrices ? (
                            <span className="rst-price">
                              {formatFils(item.price_fils)}
                            </span>
                          ) : (
                            <span />
                          )}
                          <span className="rst-open-hint">عرض</span>
                        </div>
                      </div>
                    </button>
                  </li>
                );
              })}
            </ul>
          )}
        </div>
      ) : null}

      {tab === "orders" && !detail ? (
        <section className="rst-orders-page" aria-label="طلباتي">
          <h2 className="rst-cart-title">طلباتي</h2>
          {orders.length === 0 ? (
            <p className="rst-empty">
              لا طلبات بعد. أضف من الرئيسية ثم أكّد من السلة.
            </p>
          ) : (
            <ul className="rst-orders-list">
              {orders.map((o) => (
                <li key={o.id} className="rst-order-card">
                  <div className="rst-order-head">
                    <strong>طلب #{o.id}</strong>
                    <span className="rst-order-status">{o.status_ar}</span>
                  </div>
                  <ul className="rst-order-lines">
                    {o.lines.map((l, i) => (
                      <li key={`${o.id}-${i}`}>
                        {l.name_ar} × {l.qty}
                      </li>
                    ))}
                  </ul>
                  {showPrices ? (
                    <p className="rst-price">{formatFils(o.total_fils)}</p>
                  ) : null}
                  <p className="rst-order-time">
                    {new Date(o.at).toLocaleString("ar-IQ")}
                  </p>
                </li>
              ))}
            </ul>
          )}
        </section>
      ) : null}

      {tab === "cart" && !detail ? (
        <section className="rst-cart-page" aria-label="السلة">
          <h2 className="rst-cart-title">سلّة الطلب</h2>
          {cart.length === 0 ? (
            <p className="rst-empty">السلة فارغة — اختر أكلات من الرئيسية.</p>
          ) : (
            <>
              <ul className="rst-cart-list">
                {cart.map((line) => (
                  <li key={line.menu_item_id} className="rst-cart-line">
                    <div>
                      <strong>{line.name_ar}</strong>
                      {showPrices ? (
                        <p className="rst-price">
                          {formatFils(line.price_fils * line.qty)}
                        </p>
                      ) : null}
                    </div>
                    <div className="rst-qty">
                      <button
                        type="button"
                        aria-label="إنقاص"
                        onClick={() => setQty(line.menu_item_id, line.qty - 1)}
                      >
                        −
                      </button>
                      <span>{line.qty}</span>
                      <button
                        type="button"
                        aria-label="زيادة"
                        onClick={() => setQty(line.menu_item_id, line.qty + 1)}
                      >
                        +
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
              {showPrices ? (
                <p className="rst-cart-total">
                  المجموع: <strong>{formatFils(cartTotal)}</strong>
                </p>
              ) : null}

              {needsDeliveryContact || checkoutOpen
                ? renderContactFields()
                : null}

              <button
                type="button"
                className="rst-submit rst-submit--block"
                disabled={busy}
                onClick={() => {
                  if (needsDeliveryContact && !checkoutOpen) {
                    setCheckoutOpen(true);
                  }
                  void submitOrder();
                }}
              >
                {busy
                  ? "جارٍ الإرسال…"
                  : isTable
                    ? "تأكيد الطلب للمطبخ"
                    : "تأكيد الطلب والتواصل للتوصيل"}
              </button>
            </>
          )}
        </section>
      ) : null}

      {sessionId && isTable ? (
        <div className="rst-bill-bar">
          <button
            type="button"
            className="rst-submit"
            disabled={busy}
            onClick={requestBill}
          >
            طلب الحساب
          </button>
        </div>
      ) : null}

      {message ? <p className="rst-msg" role="status">{message}</p> : null}

      {detail ? (
        <div className="rst-detail" role="dialog" aria-modal="true">
          <button
            type="button"
            className="rst-detail-back"
            onClick={() => setDetail(null)}
          >
            رجوع
          </button>
          <div className="rst-detail-gallery">
            {(detailImages.length
              ? detailImages
              : [{ image_url: detail.image_url, alt_ar: detail.name_ar }]
            ).map((img, i) =>
              img.image_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img
                  key={i}
                  src={img.image_url}
                  alt={
                    "alt_ar" in img
                      ? (img.alt_ar ?? detail.name_ar)
                      : detail.name_ar
                  }
                  loading={i === 0 ? "eager" : "lazy"}
                />
              ) : null,
            )}
          </div>
          <h2>{detail.name_ar}</h2>
          {showDesc && detail.description_ar ? (
            <p className="rst-desc">{detail.description_ar}</p>
          ) : null}
          {showPrices ? (
            <p className="rst-price">{formatFils(detail.price_fils)}</p>
          ) : null}
          <button
            type="button"
            className="rst-submit rst-submit--block"
            onClick={() => {
              addToCart(detail);
              setDetail(null);
              setTab("cart");
              setMessage("أُضيف إلى السلة.");
            }}
          >
            أضف إلى السلة
          </button>
        </div>
      ) : null}

      {!detail ? (
        <nav className="rst-bottom-nav" aria-label="تنقل المنيو">
          <button
            type="button"
            className={tab === "home" ? "active" : undefined}
            onClick={() => setTab("home")}
          >
            <span className="rst-nav-ico" aria-hidden="true">
              ⌂
            </span>
            <span className="rst-nav-lbl">الرئيسية</span>
          </button>
          <button
            type="button"
            className={`rst-nav-cart${tab === "cart" ? " active" : ""}`}
            onClick={() => setTab("cart")}
          >
            <span className="rst-nav-ico" aria-hidden="true">
              ◉
            </span>
            <span className="rst-nav-lbl">السلة</span>
            {cartQty > 0 ? (
              <span className="rst-nav-badge">{cartQty}</span>
            ) : null}
          </button>
          <button
            type="button"
            className={tab === "orders" ? "active" : undefined}
            onClick={() => setTab("orders")}
          >
            <span className="rst-nav-ico" aria-hidden="true">
              ≡
            </span>
            <span className="rst-nav-lbl">طلباتي</span>
            {orders.length > 0 ? (
              <span className="rst-nav-badge rst-nav-badge--soft">
                {orders.length}
              </span>
            ) : null}
          </button>
        </nav>
      ) : null}
    </div>
  );
}
