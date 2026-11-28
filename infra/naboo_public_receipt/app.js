/**
 * صفحة الفاتورة للزبون على naboo.fun/r/{token}.
 * تقرأ نسخة الإيصال بالرمز فقط عبر الدالة العامة receipt_public_get.
 * كل النصوص تُكتب بـ textContent: لا HTML من البيانات.
 */
(function () {
  const SUPABASE_URL = "https://rkofqwcuvbzrnmelvxhz.supabase.co";
  const ANON_KEY =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJrb2Zxd2N1dmJ6cm5tZWx2eGh6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzNDEyNjksImV4cCI6MjA5MTkxNzI2OX0.F5x59dpqtEqQn_MrxA7S07qw6HH136ZMW_P7nfgGFkQ";
  const TOKEN = /^[A-Za-z0-9]{22,64}$/;
  const app = document.getElementById("app");

  function el(tag, cls, text) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = String(text);
    return e;
  }

  function iqd(fils) {
    const d = Math.round(Number(fils || 0) / 1000);
    return d.toLocaleString("en-US") + " د.ع";
  }

  function safeColor(c, fallback) {
    return typeof c === "string" && /^#[0-9a-fA-F]{6}$/.test(c) ? c : fallback;
  }

  function message(title, body) {
    app.replaceChildren();
    const card = el("section", "rcp-card rcp-message");
    card.append(el("h1", null, title), el("p", null, body));
    app.append(card);
  }

  function qtyText(l) {
    if (l.qty == null) return null;
    const q = Number.isInteger(l.qty) ? String(l.qty) : Number(l.qty).toFixed(2);
    const unit = l.unit ? " " + l.unit : "";
    return l.price != null ? q + unit + " × " + iqd(l.price) : q + unit;
  }

  function whatsappLink(r) {
    const n = r.store && r.store.whatsapp;
    if (!n || !/^964\d{10}$/.test(n)) return null;
    const text = r.number
      ? "مرحباً، بخصوص " + r.title + " رقم " + r.number
      : "مرحباً، بخصوص " + r.title;
    return "https://wa.me/" + n + "?text=" + encodeURIComponent(text);
  }

  const WA_ICON =
    "M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2Zm0 18.2a8.2 8.2 0 0 1-4.2-1.2l-.3-.2-3 .8.8-2.9-.2-.3A8.2 8.2 0 1 1 12 20.2Zm4.5-6.1c-.2-.1-1.5-.7-1.7-.8s-.4-.1-.6.1-.7.8-.8 1-.3.2-.5.1a6.7 6.7 0 0 1-3.3-2.9c-.2-.4.2-.4.7-1.3a.4.4 0 0 0 0-.4l-.8-1.9c-.2-.5-.4-.4-.6-.4h-.5a1 1 0 0 0-.7.3 3 3 0 0 0-.9 2.2 5.2 5.2 0 0 0 1.1 2.7 11.8 11.8 0 0 0 4.5 4c1.7.7 2.3.8 3.2.6a2.7 2.7 0 0 0 1.7-1.2 2.2 2.2 0 0 0 .2-1.2c-.1-.1-.3-.2-.5-.3Z";

  function render(r) {
    app.replaceChildren();
    app.style.setProperty("--accent", safeColor(r.colors && r.colors.accent, "#1f2937"));
    app.style.setProperty("--on-accent", safeColor(r.colors && r.colors.onAccent, "#ffffff"));
    const store = r.store || {};
    const card = el("section", "rcp-card");

    const head = el("header", "rcp-head");
    head.append(el("h1", null, store.name || "المحل"));
    if (store.address) head.append(el("p", null, store.address));
    if (store.phone) {
      const a = el("a", "rcp-phone", store.phone);
      a.href = "tel:" + String(store.phone).replace(/[^0-9+]/g, "");
      head.append(a);
    }
    card.append(head);

    const title = el("div", "rcp-title");
    title.append(
      el("strong", null, r.title),
      el(
        "span",
        null,
        (r.number ? "رقم " + r.number + " · " : "") + (r.date || "") + (r.status ? " · " + r.status : ""),
      ),
    );
    card.append(title);

    if (r.state === "returned") card.append(el("p", "rcp-banner", "هذه الفاتورة مسترجعة."));

    const fields = Array.isArray(r.fields) ? r.fields : [];
    if (fields.length) {
      const dl = el("dl", "rcp-fields");
      for (const f of fields) {
        const row = el("div");
        row.append(el("dt", null, f[0]), el("dd", null, f[1]));
        dl.append(row);
      }
      card.append(dl);
    }

    for (const h of Array.isArray(r.highlights) ? r.highlights : []) {
      const box = el("div", "rcp-highlight");
      box.append(el("span", null, h[0]), el("strong", null, h[1]));
      card.append(box);
    }

    const l = r.loyalty;
    if (l && (l.line || l.visit)) {
      const box = el("div", "rcp-loyalty");
      if (l.line) box.append(el("p", null, l.line));
      if (l.done != null && l.total != null && l.total >= 2 && l.total <= 20) {
        const dots = el("span", "rcp-dots");
        dots.setAttribute("aria-label", l.done + " من " + l.total);
        for (let i = 0; i < l.total; i++) dots.append(el("span", i < l.done ? "on" : ""));
        box.append(dots);
      }
      if (l.visit) {
        box.append(
          el("p", null, l.visit === 1 ? "أول زيارة لسيارتك — أهلاً بك" : "زيارتك رقم " + l.visit + " — شكراً لثقتك"),
        );
      }
      card.append(box);
    }

    const lines = Array.isArray(r.lines) ? r.lines : [];
    if (lines.length) {
      const ul = el("ul", "rcp-lines");
      for (const x of lines) {
        const li = el("li");
        const left = el("div");
        left.append(el("span", null, x.name));
        const q = qtyText(x);
        if (q) left.append(el("small", null, q));
        li.append(left, el("b", null, iqd(x.total)));
        ul.append(li);
      }
      card.append(ul);
    }

    const totals = Array.isArray(r.totals) ? r.totals : [];
    const main = totals.find((t) => t.main) || totals[totals.length - 1];
    const tbox = el("div", "rcp-totals");
    for (const t of totals) {
      const row = el("div", t === main ? "rcp-main" : null);
      row.append(el("span", null, t.label), el(t === main ? "strong" : "b", null, iqd(t.fils)));
      tbox.append(row);
    }
    card.append(tbox);

    const notes = Array.isArray(r.notes) ? r.notes : [];
    if (notes.length) {
      const nb = el("div", "rcp-notes");
      for (const n of notes) nb.append(el("p", null, n));
      card.append(nb);
    }
    card.append(el("p", "rcp-thanks", "شكراً لزيارتكم"));
    app.append(card);

    const wa = whatsappLink(r);
    if (wa) {
      const a = el("a", "rcp-wa");
      a.href = wa;
      a.target = "_blank";
      a.rel = "noopener noreferrer";
      const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
      svg.setAttribute("viewBox", "0 0 24 24");
      svg.setAttribute("aria-hidden", "true");
      const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
      path.setAttribute("fill", "currentColor");
      path.setAttribute("d", WA_ICON);
      svg.append(path);
      a.append(svg, document.createTextNode("تواصل مع المحل على واتساب"));
      app.append(a);
    }
    if (r.title) document.title = r.title + (store.name ? " — " + store.name : "");
  }

  async function main() {
    const parts = location.pathname.split("/").filter(Boolean);
    const token = parts[0] === "r" ? parts[1] || "" : "";
    if (!TOKEN.test(token)) {
      message("الفاتورة غير موجودة", "تأكد من الرابط، أو اطلب من المحل إعادة إرسال الإيصال.");
      return;
    }
    try {
      const res = await fetch(SUPABASE_URL + "/rest/v1/rpc/receipt_public_get", {
        method: "POST",
        headers: {
          apikey: ANON_KEY,
          Authorization: "Bearer " + ANON_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ p_token: token }),
        cache: "no-store",
      });
      if (!res.ok) throw new Error("HTTP " + res.status);
      const r = await res.json();
      if (!r || typeof r !== "object") {
        message("الفاتورة غير موجودة", "تأكد من الرابط، أو اطلب من المحل إعادة إرسال الإيصال.");
      } else if (r.state === "deleted") {
        message("الفاتورة غير متاحة", "ألغى المحل هذه الفاتورة. للاستفسار تواصل مع المحل مباشرة.");
      } else {
        render(r);
      }
    } catch (e) {
      message("تعذّر تحميل الفاتورة", "تأكد من الإنترنت ثم أعد فتح الرابط.");
    }
  }

  main();
})();
