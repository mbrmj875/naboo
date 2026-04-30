## نشر APK على GitHub + تنزيل من موقعك (naboo)

### 1) لماذا البناء المحلي لا يعمل عندك؟
في جهازك ظهر تعليق Gradle على `assembleRelease` مع تحذيرات شبكة (`maven.google.com` / `storage.googleapis.com`).
هذا سبب بيئي (شبكة/حجب/ DNS) — ليس خطأ كود.  
الحل العملي: **استخدم GitHub Actions** لبناء النسخة وإرفاقها كـ Release.

### 2) نشر إصدار جديد (Android + Windows) عبر GitHub Releases
في هذا المستودع يوجد Workflow لـ **Windows فقط**:
- `.github/workflows/release.yml` — يبني `naboo-windows-setup.exe` ويرفقه لوسم الإصدار على GitHub.
- **Android:** ارفع `naboo.apk` يدوياً من واجهة GitHub Release عند الحاجة (لا يُبنى في CI في هذا الملف).

لإصدار نسخة جديدة:

```bash
git tag v2.0.1
git push origin v2.0.1
```

بعدها GitHub سيبني ويرفع ملفات التحميل داخل Release تلقائياً، منها:
- `naboo.apk` (Android)
- `naboo-windows-setup.exe` (Windows)

### 3) التنزيل "من نفس الموقع"
في مجلد موقعك `/Users/mohamed123/Development/naboo` أضفنا:
- `downloads/android/` (يحّول إلى آخر APK في GitHub Release)
- `downloads/windows/` (يحّول إلى آخر Setup في GitHub Release)

وتم تعديل روابط قسم التنزيل في `naboo/index.html` لتذهب إلى هذه الصفحات.

عند نشر Firebase Hosting، سيصبح الرابط مثل:
- `https://<domain>/downloads/android/`
- `https://<domain>/downloads/windows/`

### 4) نشر الموقع على Firebase Hosting
داخل مجلد `naboo`:

```bash
firebase deploy --only hosting
```
