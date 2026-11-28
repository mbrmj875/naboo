# صفحة الفاتورة naboo.fun/r/{token}

صفحة ثابتة مثل المنيو `/m/`. تقرأ نسخة الإيصال بالرمز من الدالة العامة
`receipt_public_get` (الهجرة `migrations/20261130_public_receipts.sql`).

## النشر

1. انسخ الملفات إلى مجلد الموقع:
   ```bash
   cp infra/naboo_public_receipt/{index.html,app.js,receipt.css} ~/Development/naboo/r/
   ```
2. يجب أن يحتوي `~/Development/naboo/firebase.json` على:
   - إعادة توجيه `{"source": "/r/**", "destination": "/r/index.html"}`.
   - رؤوس `/r/**`: عدم التخزين المؤقت، و`noindex`، و`no-referrer`، و`DENY`.
3. انشر بـ Node 20 أو أحدث:
   ```bash
   cd ~/Development/naboo && firebase deploy --only hosting
   ```

الخط مأخوذ من `/m/fonts/tajawal`.
