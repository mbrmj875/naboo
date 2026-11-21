# منيو المطاعم العام على naboo.fun

## القرار
- المضيف الكانوني: **`https://naboo.fun`** (HTTPS فقط).
- المسارات:
  - طاولة QR: `https://naboo.fun/m/{tenant_slug}/t/{table_slug}`
  - رابط منزل/سوشيال: `https://naboo.fun/m/{tenant_slug}`
  - تتبع جلسة: `https://naboo.fun/m/{tenant_slug}/session/{session_id}`

## التصميم (Stitch)
- مشروع Stitch: `Naboo Restaurant Public Menu - naboo.fun` (id `10648793285769585911`)
- نظام تصميم: **Royal Naboo Reserve** — فحمي `#0F1419` + كهرماني `#C45C26`، RTL عربي، شبكة مربعات 2 أعمدة.
- التنفيذ في `admin-web/app/m/**` + `public-menu-client.tsx` + `menu.css`.

## النشر على naboo.fun (Firebase Hosting)

الموقع التسويقي + Flutter على `/app` يُخدَم من مجلد `~/Development/naboo`.
المنيو العام يُخدم كـ SPA ثابتة تحت `/m/**` (بدون انتظار نشر Vercel لـ admin-web).

1. انسخ من المستودع إلى موقع الاستضافة:
   ```bash
   rsync -a infra/naboo_public_menu/ ~/Development/naboo/m/ \
     --exclude firebase.hosting.snippet.json
   ```
2. تأكد أن `firebase.json` يحتوي:
   ```json
   "rewrites": [{ "source": "/m/**", "destination": "/m/index.html" }]
   ```
3. انشر: `cd ~/Development/naboo && firebase deploy --only hosting`
4. افتح رابط حقيقي مثل: `https://naboo.fun/m/thesijdh`  
   (لا تستخدم `{slug}` حرفياً من الوثائق).

## Flutter QR
- `RestaurantTenantSlugService` يقرأ `tenant_slug` من `restaurant_tenant_slugs`.
- لا تُمرَّر قيم وهمية مثل `tenant` أو `{slug}`.


## أمان
- مسارات `/m/*` عامة (بدون جلسة أدمن) مع:
  - HSTS
  - CSP مضبوط (self + supabase)
  - `X-Frame-Options: DENY`
  - Rate limit داخل `restaurant-create-order`
  - `restaurant-auto-accept-tick` محمي بـ `x-cron-secret`
