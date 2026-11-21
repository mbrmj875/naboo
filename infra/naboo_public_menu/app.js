/**
 * منيو عام على naboo.fun/m/{slug}[/t/{table}] — قراءة من Supabase + طلب عبر Edge.
 */
(function () {
  const SUPABASE_URL = "https://rkofqwcuvbzrnmelvxhz.supabase.co";
  const ANON_KEY =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJrb2Zxd2N1dmJ6cm5tZWx2eGh6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNDEyNjksImV4cCI6MjA5MTkxNzI2OX0.F5x59dpqtEqQn_MrxA7S07qw6HH136ZMW_P7nfgGFkQ";
  const FUNCTIONS = SUPABASE_URL + "/functions/v1";

  const DEFAULT_THEME = {
    identity: {
      display_name_ar: "المنيو",
      tagline_ar: "اطلب من البيت واستلم من المطعم",
    },
    colors: {
      bg: "#0F172A",
      text: "#F1F5F9",
      primary: "#1E293B",
      accent: "#B8960C",
    },
    toggles: { show_prices: true, show_item_descriptions: true },
  };

  function parseRoute() {
    const parts = location.pathname.replace(/^\/+|\/+$/g, "").split("/");
    // m / {slug} [/ t / {table} | session / {id}]
    if (parts[0] !== "m" || !parts[1] || parts[1] === "{slug}") {
      return { error: "missing_slug" };
    }
    const tenantSlug = decodeURIComponent(parts[1]);
    let tableSlug = null;
    let sessionId = null;
    if (parts[2] === "t" && parts[3]) {
      tableSlug = decodeURIComponent(parts[3]);
    } else if (parts[2] === "session" && parts[3]) {
      sessionId = parts[3];
    }
    return { tenantSlug, tableSlug, sessionId };
  }

  function formatFils(fils) {
    const dinars = fils / 1000;
    if (!Number.isFinite(dinars)) return "— د.ع";
    if (Math.abs(fils % 1000) < 1e-9) {
      return new Intl.NumberFormat("en-US").format(Math.round(dinars)) + " د.ع";
    }
    return (
      new Intl.NumberFormat("en-US", {
        minimumFractionDigits: 2,
        maximumFractionDigits: 2,
      }).format(dinars) + " د.ع"
    );
  }

  async function sbGet(path) {
    const res = await fetch(SUPABASE_URL + "/rest/v1/" + path, {
      headers: {
        apikey: ANON_KEY,
        Authorization: "Bearer " + ANON_KEY,
        Accept: "application/json",
      },
    });
    if (!res.ok) throw new Error("supabase_" + res.status);
    return res.json();
  }

  async function loadMenu(tenantSlug) {
    const slugs = await sbGet(
      "restaurant_tenant_slugs?tenant_slug=eq." +
        encodeURIComponent(tenantSlug) +
        "&select=tenant_uuid",
    );
    if (!slugs.length) return { error: "restaurant_not_found" };
    const tenantUuid = slugs[0].tenant_uuid;

    const themes = await sbGet(
      "restaurant_menu_theme?tenant_uuid=eq." +
        tenantUuid +
        "&deleted_at=is.null&select=published_json,draft_json&limit=1",
    ).catch(() => []);

    let theme = DEFAULT_THEME;
    if (themes[0]) {
      const raw = themes[0].published_json || themes[0].draft_json;
      if (raw && typeof raw === "object") {
        theme = {
          ...DEFAULT_THEME,
          ...raw,
          identity: { ...DEFAULT_THEME.identity, ...(raw.identity || {}) },
          colors: { ...DEFAULT_THEME.colors, ...(raw.colors || {}) },
          toggles: { ...DEFAULT_THEME.toggles, ...(raw.toggles || {}) },
        };
      }
    }

    const categories = await sbGet(
      "restaurant_menu_categories?tenant_uuid=eq." +
        tenantUuid +
        "&is_active=eq.true&deleted_at=is.null&select=id,name_ar,sort_order&order=sort_order.asc",
    );
    const items = await sbGet(
      "restaurant_menu_items?tenant_uuid=eq." +
        tenantUuid +
        "&is_available=eq.true&deleted_at=is.null&select=id,category_id,name_ar,description_ar,price_fils,image_url&order=sort_order.asc",
    );
    let images = [];
    if (items.length) {
      const ids = items.map((i) => i.id).join(",");
      images = await sbGet(
        "restaurant_menu_item_images?tenant_uuid=eq." +
          tenantUuid +
          "&menu_item_id=in.(" +
          ids +
          ")&deleted_at=is.null&select=menu_item_id,image_url,sort_order,is_primary&order=sort_order.asc",
      ).catch(() => []);
    }

    return { tenantUuid, theme, categories, items, images };
  }

  function applyTheme(theme) {
    const root = document.body;
    const c = theme.colors || {};
    if (c.bg) root.style.setProperty("--rst-color-bg", c.bg);
    if (c.text) root.style.setProperty("--rst-color-text", c.text);
    if (c.primary) root.style.setProperty("--rst-color-primary", c.primary);
    if (c.accent) root.style.setProperty("--rst-color-accent", c.accent);
  }

  function el(tag, attrs, children) {
    const node = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach((k) => {
        if (k === "className") node.className = attrs[k];
        else if (k === "text") node.textContent = attrs[k];
        else if (k.startsWith("on") && typeof attrs[k] === "function") {
          node.addEventListener(k.slice(2).toLowerCase(), attrs[k]);
        } else if (attrs[k] != null) node.setAttribute(k, attrs[k]);
      });
    }
    (children || []).forEach((c) => {
      if (c == null) return;
      node.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
    });
    return node;
  }

  function render(route, data) {
    const app = document.getElementById("app");
    app.className = "";
    app.innerHTML = "";

    if (route.error === "missing_slug" || data.error === "restaurant_not_found") {
      app.appendChild(
        el("p", {
          className: "rst-empty",
          text:
            route.error === "missing_slug"
              ? "رابط المنيو غير مكتمل. استخدم /m/معرّف-المطعم"
              : "المطعم غير موجود أو غير مفعّل بعد.",
        }),
      );
      return;
    }

    const theme = data.theme;
    applyTheme(theme);
    document.title =
      (theme.identity?.display_name_ar || "المنيو") + " — نابو";

    const showPrices = theme.toggles?.show_prices !== false;
    const showDesc = theme.toggles?.show_item_descriptions !== false;
    const isTable = Boolean(route.tableSlug);

    let categoryId = "all";
    let cart = [];
    let sessionId = route.sessionId ? Number(route.sessionId) : null;
    let busy = false;
    let message = null;

    const header = el("header", { className: "rst-header" }, [
      el("div", { className: "rst-header-top" }, [
        el("h1", { text: theme.identity?.display_name_ar || "المنيو" }),
        el("span", {
          className: isTable ? "rst-table-badge" : "rst-mode-badge",
          text: isTable ? "طاولة " + route.tableSlug : "استلام من المحل",
        }),
      ]),
      el("p", {
        className: "rst-tagline",
        text:
          theme.identity?.tagline_ar ||
          (isTable
            ? "اطلب من الطاولة مباشرة"
            : "اطلب من البيت واستلم من المطعم"),
      }),
    ]);

    const cats = el("nav", { className: "rst-cats" });
    const list = el("ul", { className: "rst-list" });
    const msg = el("p", { className: "rst-msg", style: "display:none" });
    const cartBar = el("div", { className: "rst-cart", style: "display:none" });

    function imagesFor(itemId) {
      return (data.images || [])
        .filter((img) => img.menu_item_id === itemId)
        .sort((a, b) => a.sort_order - b.sort_order);
    }

    function cartQty() {
      return cart.reduce((a, c) => a + c.qty, 0);
    }

    function addToCart(item) {
      const idx = cart.findIndex((c) => c.menu_item_id === item.id);
      if (idx >= 0) cart[idx].qty += 1;
      else
        cart.push({
          menu_item_id: item.id,
          qty: 1,
          name_ar: item.name_ar,
        });
      paintCart();
    }

    async function submitOrder() {
      if (!cart.length || busy) return;
      busy = true;
      paintCart();
      try {
        const res = await fetch(FUNCTIONS + "/restaurant-create-order", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: ANON_KEY,
            Authorization: "Bearer " + ANON_KEY,
          },
          body: JSON.stringify({
            tenant_slug: route.tenantSlug,
            table_slug: route.tableSlug || undefined,
            channel: route.tableSlug ? "qr_table" : "public_link",
            items: cart.map((c) => ({
              menu_item_id: c.menu_item_id,
              qty: c.qty,
            })),
          }),
        });
        const body = await res.json().catch(() => ({}));
        if (!res.ok) {
          message =
            body.error === "ingredient_shortage"
              ? "عذراً، أحد المكوّنات غير متوفر حالياً."
              : body.error === "table_awaiting_payment"
                ? "الطاولة بانتظار الدفع — لا يمكن إضافة طلب."
                : body.error === "rate_limited"
                  ? "تم تجاوز حد الطلبات — حاول لاحقاً."
                  : "تعذّر إرسال الطلب. تحقق من الاتصال.";
        } else {
          sessionId = body.session_id ?? null;
          cart = [];
          message = isTable
            ? "تم إرسال طلبك إلى المطبخ."
            : "تم استلام طلب الاستلام — بانتظار تأكيد المطعم.";
        }
      } catch (_) {
        message = "الخدمة عبر الجوال متوقفة الآن — الرجاء إبلاغ النادل.";
      } finally {
        busy = false;
        paintCart();
        paintMessage();
      }
    }

    async function requestBill() {
      if (!sessionId || busy) return;
      busy = true;
      paintCart();
      try {
        const res = await fetch(FUNCTIONS + "/restaurant-request-bill", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: ANON_KEY,
            Authorization: "Bearer " + ANON_KEY,
          },
          body: JSON.stringify({
            tenant_slug: route.tenantSlug,
            session_id: sessionId,
          }),
        });
        message = res.ok
          ? "تم طلب الحساب — سيصلك النادل قريباً."
          : "تعذّر طلب الحساب.";
      } catch (_) {
        message = "تعذّر طلب الحساب.";
      } finally {
        busy = false;
        paintCart();
        paintMessage();
      }
    }

    function paintMessage() {
      if (!message) {
        msg.style.display = "none";
        return;
      }
      msg.style.display = "";
      msg.textContent = message;
    }

    function paintCart() {
      const qty = cartQty();
      if (!qty && !sessionId) {
        cartBar.style.display = "none";
        return;
      }
      cartBar.style.display = "flex";
      cartBar.innerHTML = "";
      if (qty) {
        cartBar.appendChild(
          el("div", {
            className: "rst-cart-lines",
            text: qty + " أصناف · " + cart.map((c) => c.name_ar).join("، "),
          }),
        );
        cartBar.appendChild(
          el(
            "button",
            {
              className: "rst-btn",
              disabled: busy ? "true" : null,
              onClick: submitOrder,
            },
            [busy ? "جاري الإرسال…" : "إرسال الطلب"],
          ),
        );
      } else if (sessionId && isTable) {
        cartBar.appendChild(
          el("div", { className: "rst-cart-lines", text: "جلسة نشطة" }),
        );
        cartBar.appendChild(
          el(
            "button",
            {
              className: "rst-btn",
              disabled: busy ? "true" : null,
              onClick: requestBill,
            },
            ["طلب الحساب"],
          ),
        );
      }
    }

    function paintCats() {
      cats.innerHTML = "";
      const allBtn = el(
        "button",
        {
          className: categoryId === "all" ? "active" : "",
          onClick: () => {
            categoryId = "all";
            paintCats();
            paintList();
          },
        },
        ["الكل"],
      );
      cats.appendChild(allBtn);
      data.categories.forEach((c) => {
        cats.appendChild(
          el(
            "button",
            {
              className: categoryId === c.id ? "active" : "",
              onClick: () => {
                categoryId = c.id;
                paintCats();
                paintList();
              },
            },
            [c.name_ar],
          ),
        );
      });
    }

    function paintList() {
      list.innerHTML = "";
      const filtered =
        categoryId === "all"
          ? data.items
          : data.items.filter((i) => i.category_id === categoryId);
      if (!filtered.length) {
        list.appendChild(
          el("li", {
            className: "rst-empty",
            text: "لا أصناف متاحة حالياً.",
            style: "grid-column: 1 / -1",
          }),
        );
        return;
      }
      filtered.forEach((item) => {
        const imgs = imagesFor(item.id);
        const thumb = item.image_url || (imgs[0] && imgs[0].image_url);
        const card = el("li", { className: "rst-card" }, [
          el("div", { className: "rst-thumb-wrap" }, [
            thumb
              ? el("img", {
                  className: "rst-thumb",
                  src: thumb,
                  alt: item.name_ar,
                })
              : el("div", { className: "rst-thumb-empty" }),
          ]),
          el("div", { className: "rst-card-body" }, [
            el("strong", { text: item.name_ar }),
            showDesc && item.description_ar
              ? el("p", {
                  className: "rst-desc",
                  text: item.description_ar,
                })
              : null,
            el("div", { className: "rst-card-actions" }, [
              showPrices
                ? el("span", {
                    className: "rst-price",
                    text: formatFils(item.price_fils),
                  })
                : el("span"),
              el(
                "button",
                { className: "rst-add", onClick: () => addToCart(item) },
                ["+"],
              ),
            ]),
          ]),
        ]);
        list.appendChild(card);
      });
    }

    app.appendChild(header);
    app.appendChild(cats);
    app.appendChild(msg);
    app.appendChild(list);
    app.appendChild(cartBar);
    paintCats();
    paintList();
    paintCart();
  }

  async function main() {
    const route = parseRoute();
    const app = document.getElementById("app");
    if (route.error) {
      render(route, { error: route.error });
      return;
    }
    try {
      const data = await loadMenu(route.tenantSlug);
      render(route, data);
    } catch (e) {
      app.className = "";
      app.innerHTML = "";
      app.appendChild(
        el("p", {
          className: "rst-empty",
          text: "تعذّر تحميل المنيو. تحقق من الاتصال وحاول مجدداً.",
        }),
      );
    }
  }

  main();
})();
