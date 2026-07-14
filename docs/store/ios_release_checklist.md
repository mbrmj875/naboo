# Naboo v1.0 — iOS (TestFlight / App Store)

## 1. إعداد Xcode (يدوي — ~10 دقائق)

```bash
open ios/Runner.xcworkspace
```

في Xcode:

1. **Runner** (المشروع) → **Runner** (الهدف)
2. **Signing & Capabilities**
3. **Team:** Apple Developer Account أو Personal Team (مجاني للاختبار على جهازك)
4. **Bundle Identifier:** `com.basra.storemanager` (موحّد مع Android)
5. **Automatically manage signing:** مفعّل
6. احفظ (Cmd+S)

إذا ظهرت أخطاء شهادات:

- Xcode → **Settings → Accounts** → Apple ID → **Download Manual Profiles**
- أو:

```bash
flutter clean
cd ios && pod deintegrate && pod install && cd ..
flutter pub get
```

## 2. بناء Release

```bash
flutter build ios --release --no-tree-shake-icons
```

المخرج: `build/ios/iphoneos/Runner.app`

## 3. TestFlight (موصى به)

```bash
flutter build ipa --release --no-tree-shake-icons
```

المخرج: `build/ios/ipa/*.ipa`

الرفع:

1. [App Store Connect](https://appstoreconnect.apple.com) → **Naboo**
2. **TestFlight** → ارفع IPA عبر **Transporter** أو Xcode **Organizer**
3. انتظر المعالجة (10–15 دقيقة)
4. أضف مختبرين وأرسل الدعوات

## 4. App Store Connect — المتطلبات

| الحقل | القيمة |
|-------|--------|
| Bundle ID | `com.basra.storemanager` |
| الاسم على الشاشة الرئيسية | Naboo |
| الاسم في المتجر (Listing) | Naboo |
| الفئة | Business |
| السعر | مجاني |
| Privacy Policy | `docs/PRIVACY.md` (ارفع على موقعك أو GitHub Pages) |
| Copyright | © 2026 Naboo Systems |

**الوصف:** أذكر التخصصات المدعومة (صيدلية، تجزئة، غيارات زيت، …) — ليس صيدلية فقط.

**لقطات:** 4+ شاشات — رئيسية، POS، تخصص (صيدلية أو زيوت)، لوحة المالك.

**كلمات مفتاحية:** POS, inventory, ERP, pharmacy, retail, صيدلية, مخزون, إدارة

## 5. ملاحظات

- **Personal Team (مجاني):** لا يدعم **Push Notifications**. `Runner.entitlements` فارغ حالياً للسماح بالبناء. إشعارات المالك لن تعمل على iOS حتى تفعّل الحساب المدفوع — راجع `ios/Runner/Runner.push.entitlements.example`.
- **Apple Developer Program (مدفوع):** مطلوب لـ TestFlight/App Store + Push. بعد الاشتراك: أعد `aps-environment` و`UIBackgroundModes` → `remote-notification`.

## 6. جدول زمني تقريبي

| المرحلة | الوقت |
|---------|-------|
| Xcode setup | ~10 دقائق |
| Build IPA | ~10 دقائق |
| TestFlight upload | ~5 دقائق |
| Processing | 10–15 دقيقة |
| App Store review | 5–7 أيام |
