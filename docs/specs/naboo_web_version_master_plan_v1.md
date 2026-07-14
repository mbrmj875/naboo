
# NABOO — خطة نسخة الويب

> **النسخة الكاملة** موجودة في مستودع الموقع:  
> [`naboo/docs/naboo_web_version_master_plan_v1.md`](../../../naboo/docs/naboo_web_version_master_plan_v1.md)

هذا الملف مرجع مختصر — افتح الملف أعلاه للخطة التفصيلية (6 مراحل، عوائق تقنية، سكربت النشر، قائمة الشاشات).

## ملخص سريع

| ما تبنيه | أين |
|----------|-----|
| تطبيق ERP في المتصفح | `flutter build web` → `naboo/app/` |
| موقع تسويقي | `naboo/*.html` (جاهز) |
| إدارة تراخيص | `admin-web/` (منفصل) |

## أول 3 خطوات

1. `flutter config --enable-web`
2. إصلاح SQLite للويب (`sqflite_common_ffi_web` في `sqlite_desktop_init_web.dart`)
3. `flutter run -d chrome` مع `--dart-define` لـ Supabase

## النشر

```bash
flutter build web --release --base-href=/app/ --no-tree-shake-icons \
  --dart-define=SUPABASE_URL="..." --dart-define=SUPABASE_ANON_KEY="..."
cp -R build/web ../naboo/app/
cd ../naboo && firebase deploy --only hosting
```
