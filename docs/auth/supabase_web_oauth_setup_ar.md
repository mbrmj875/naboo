# إعداد Google OAuth على الويب — NABOO

## المشكلة الشائعة

بعد اختيار حساب Google يفتح المتصفح `http://localhost:3000/?code=...` ويفشل الاتصال.

**السبب:** في Supabase → Authentication → URL Configuration، حقل **Site URL** مضبوط على `http://localhost:3000` (من التطوير المحلي). عندما لا يكون `redirect_to` مسموحاً، يعيد Supabase التوجيه إلى Site URL.

---

## الحل 1 (مُفضّل في الكود): ID Token بدون إعادة توجيه

النسخة الحالية تستخدم `signInWithIdToken` عبر `google_sign_in` على الويب — لا تحتاج redirect URLs.

### Google Cloud Console

1. افتح [Google Cloud Console](https://console.cloud.google.com/) → مشروع `naboo-m` (أو المشروع المرتبط بـ Supabase).
2. **APIs & Services → Credentials** → عميل OAuth من نوع **Web application**.
3. **Authorized JavaScript origins** — أضف:
   - `https://naboo-93580.web.app`
4. احفظ. انتظر دقيقة ثم جرّب تسجيل Google من الموقع.

### Supabase Dashboard

1. **Authentication → Providers → Google** — مفعّل، و**Client ID** يطابق عميل الويب أعلاه.
2. (اختياري لكن مُستحسن) **URL Configuration**:
   - **Site URL:** `https://naboo-93580.web.app`
   - **Redirect URLs:**
     - `https://naboo-93580.web.app/app/`
     - `https://naboo-93580.web.app/app/oauth_complete.html`

---

## الحل 2: إصلاح Redirect URLs فقط (مسار احتياطي)

إذا فشل ID Token وعاد التطبيق لمسار OAuth القديم:

| الحقل | القيمة |
|--------|--------|
| Site URL | `https://naboo-93580.web.app` |
| Redirect URLs | `https://naboo-93580.web.app/app/**` |

---

## التحقق

- نسخة البناء: `https://naboo-93580.web.app/app/naboo-build.json`
- بعد النشر: امسح كاش المتصفح أو نافذة خاصة جديدة.
- جرّب **تسجيل بـ Google** من `https://naboo-93580.web.app/app/`

---

## متغيرات البناء

```bash
WEB_APP_ORIGIN=https://naboo-93580.web.app
GOOGLE_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
```

تُمرَّر تلقائياً عبر `scripts/deploy_web_to_naboo.sh`.
