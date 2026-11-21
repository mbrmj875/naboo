# متغيّرات البناء (dart-define)

يقرأ التطبيق المفاتيح الحسّاسة وقت البناء عبر `String.fromEnvironment` — لا تُخزَّن في الكود.

## الإعداد

1. انسخ المثال:
   ```bash
   cp env/prod.env.example env/prod.env
   ```
2. املأ القيم الحقيقية في `env/prod.env` (لا تُدرجه في Git).

## البناء للإصدار

**القاعدة:** كل بناء إصدار (release) لأي منصة يحتاج تمرير المفاتيح، لأنها تُدمج
وقت التصريف. لكن الملف `env/prod.env` واحد لكل المنصات — تكتب أمراً واحداً لكل
منصة، والمفاتيح تُقرأ تلقائياً.

### الطريقة المختصرة (سكربت جاهز)

```bash
# macOS / Linux
bash scripts/build_release.sh appbundle   # Android AAB (نشر Play)
bash scripts/build_release.sh apk         # Android APK
bash scripts/build_release.sh ios         # iOS (على macOS)
bash scripts/build_release.sh macos       # macOS
bash scripts/build_release.sh web         # الويب
```

```powershell
# Windows (PowerShell)
.\scripts\build_release.ps1 windows        # تطبيق Windows
.\scripts\build_release.ps1 appbundle      # Android AAB
```

### الأوامر المباشرة (نفس الشيء يدوياً)

| المنصة | الجهاز المطلوب للبناء | الأمر |
|--------|----------------------|-------|
| Android (Play) | أي (Windows/macOS/Linux) | `flutter build appbundle --release --dart-define-from-file=env/prod.env` |
| Android (APK) | أي | `flutter build apk --release --dart-define-from-file=env/prod.env` |
| iOS | **macOS فقط** + Xcode | `flutter build ipa --release --dart-define-from-file=env/prod.env` |
| macOS | **macOS فقط** | `flutter build macos --release --dart-define-from-file=env/prod.env` |
| Windows | **Windows فقط** | `flutter build windows --release --dart-define-from-file=env/prod.env` |
| Web | أي | `flutter build web --release --dart-define-from-file=env/prod.env` |

### أثناء التطوير (تشغيل مباشر)

```bash
flutter run --dart-define-from-file=env/prod.env
```

> **كم مرة؟** مرة واحدة لكل بناء لكل منصة. الملف يُقرأ آلياً في كل مرة، فلا تعيد
> كتابة المفاتيح. iOS/macOS لا يُبنيان إلا على جهاز Apple، وWindows إلا على Windows.

## المفاتيح

| المفتاح | ضروري | الأثر عند غيابه |
|---------|--------|------------------|
| `SUPABASE_URL` | نعم | فشل الإقلاع (`SupabaseConfig.assertConfigured`) |
| `SUPABASE_ANON_KEY` | نعم | فشل الإقلاع |
| `GOOGLE_WEB_CLIENT_ID` | موصى به بشدّة | دخول Google يسقط إلى المتصفح الخارجي بدل منتقي الحسابات الأصلي (تجربة أقل احترافية) — يظهر تحذير في اللوغ عند الإقلاع |

> **ملاحظة أمنية:** لا تضع مفتاح `service_role` هنا أبداً؛ يُستخدم `anon key` فقط في تطبيق Flutter مع الاعتماد على RLS.
