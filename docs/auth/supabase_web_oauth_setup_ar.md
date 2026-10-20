# إعداد Google OAuth على الويب — NABOO

## المشكلة الشائعة: `Error 400: origin_mismatch`

تظهر عند تسجيل Google من نطاق **غير** مضاف في **Authorized JavaScript origins**.

مثال: الدخول من `https://naboo.fun` بينما المسموح فقط `https://naboo-93580.web.app`.

---

## الحل في Google Cloud Console (مطلوب)

1. افتح [Google Cloud Console → Credentials](https://console.cloud.google.com/apis/credentials)  
   مشروع مرتبط بعميل الويب (غالباً `naboo` / رقم `281392172783`).
2. افتح عميل OAuth من نوع **Web application**  
   (مثال Client ID: `281392172783-ngr4g28b2c4cap8mvfdav60t9b62pj13.apps.googleusercontent.com`).
3. تحت **Authorized JavaScript origins** أضف **كل** النطاقات التي يفتح منها التطبيق:

| Origin |
|--------|
| `https://naboo.fun` |
| `https://www.naboo.fun` *(إن وُجد)* |
| `https://naboo-93580.web.app` |
| `https://naboo-93580.firebaseapp.com` |

4. تحت **Authorized redirect URIs** (لمسار OAuth الاحتياطي / Supabase):

| Redirect URI |
|--------------|
| `https://naboo.fun/app/` |
| `https://naboo.fun/app/oauth_complete.html` |
| `https://naboo-93580.web.app/app/` |
| `https://naboo-93580.web.app/app/oauth_complete.html` |
| `https://rkofqwcuvbzrnmelvxhz.supabase.co/auth/v1/callback` |

5. **Save** — انتظر 1–5 دقائق ثم أعد المحاولة من نافذة خاصة.

> لا تضع مساراً في Origins (خطأ: `https://naboo.fun/app/`). Origin = مخطط + مضيف فقط.

---

## Supabase Dashboard (مُستحسن)

**Authentication → URL Configuration:**

- **Site URL:** `https://naboo.fun` *(أو `https://naboo-93580.web.app` إن كان هو الأساس)*
- **Redirect URLs** أضف:
  - `https://naboo.fun/app/**`
  - `https://naboo-93580.web.app/app/**`
  - `https://naboo.fun/app/oauth_complete.html`
  - `https://naboo-93580.web.app/app/oauth_complete.html`

**Authentication → Providers → Google:** Client ID / Secret يطابقان عميل الويب أعلاه.

---

## سلوك التطبيق (من أغسطس 2026)

على **الويب** التطبيق يستخدم **إعادة توجيه Supabase OAuth فقط** — لا نافذة GIS
(`google_sign_in`) — لتفادي `origin_mismatch` على أي نطاق (naboo.fun، web.app، …).

**مطلوب في Supabase Dashboard → Authentication → URL Configuration → Redirect URLs:**

```
https://naboo.fun/app/**
https://naboo-93580.web.app/app/**
```

**مطلوب في Google Cloud → Redirect URIs** (ليس JavaScript origins):

```
https://rkofqwcuvbzrnmelvxhz.supabase.co/auth/v1/callback
```

---

## التحقق

- `https://naboo.fun/app/naboo-build.json`
- `https://naboo-93580.web.app/app/naboo-build.json`
- نافذة خاصة → تسجيل بـ Google

---

## متغيرات البناء

```bash
WEB_APP_ORIGIN=https://naboo.fun
GOOGLE_WEB_CLIENT_ID=281392172783-....apps.googleusercontent.com
```
