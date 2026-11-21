# أين تقع مشكلة انقطاع جلسة السحابة بصمت

**تاريخ الفحص:** 2026-10-18  
**النوع:** تقرير تشخيص (قراءة فقط — بلا تنفيذ)  
**المشروع:** Supabase `naboo-lic` (`rkofqwcuvbzrnmelvxhz`, eu-west-3)  
**المنصة المفحوصة:** تطبيق Flutter + Auth + `account_devices` + مسار WhatsApp من التطبيق

> **تحديث ثقة (نفس اليوم):** أُعيد الفحص بميزان C1/C2/C3. بعض الاستنتاجات أدناه كانت أقوى من الدليل.  
> **المرجع الأدق للدراسة قبل أي إصلاح:**  
> [SILENT_CLOUD_SESSION_ENGINEERING_CONFIDENCE_2026-10-18.md](./SILENT_CLOUD_SESSION_ENGINEERING_CONFIDENCE_2026-10-18.md)

---

## الحقيقة في جملة

المشكلة **ليست في إعدادات Auth على السيرفر** (لا timebox ولا inactivity) — هذا مؤكد.  
أما الجزم بأن عطلاً واحداً في العميل يفسّر كل الحالات: **غير مثبت بالدرجة نفسها**. المؤكد أن غياب/موت الجلسة على الجهاز يفسّر شكل العَرَض (أجهزة/واتساب)، بينما سبب الفقدان لحادثة بعينها يحتاج قياساً إضافياً.

---

## أين تقع المشكلة (الموقع الدقيق)

| الطبقة | الحكم | الدليل |
|--------|--------|--------|
| إعدادات Supabase Auth | **ليست السبب** | `sessions_timebox=0`, `sessions_inactivity_timeout=0`, `sessions_single_per_user=false` |
| `custom_access_token_hook` | **ليست السبب** | يضيف `app_role` + `tenant_id` فقط |
| حذف أجهزة من السيرفر | **ليست السبب** | صفوف `account_devices` تبقى؛ تتوقف فقط `last_seen_at` |
| **كود العميل — تجديد الجلسة** | **موقع أساسي** | `lib/services/auth/ensure_fresh_session.dart` |
| **كود العميل — استعادة صامتة** | **موقع أساسي** | `lib/providers/auth_provider.dart` → `tryRestoreCloudSessionSilently` |
| **كود العميل — حارس النبضة** | **موقع أساسي** | `lib/widgets/cloud_session_resume_bridge.dart` |
| **كود العميل — غياب مراقب signedOut** | **موقع مساعد** | لا مستمع عام لـ `onAuthStateChange` في المسار الرئيسي |
| تخزين الجلسة المحلي | **موقع مساعد** | `lib/services/auth/secure_session_storage.dart` + rotation |

---

## أدلة السيرفر (فحص حي 2026-10-18)

### إعدادات Auth الفعلية

| مفتاح | قيمة |
|-------|------|
| `jwt_exp` | 3600 ثانية (ساعة) |
| `refresh_token_rotation_enabled` | true |
| `security_refresh_token_reuse_interval` | 10 ثوانٍ |
| `sessions_timebox` | 0 |
| `sessions_inactivity_timeout` | 0 |
| `sessions_single_per_user` | false |
| `rate_limit_token_refresh` | 150 |
| GoTrue | v2.193.1 |

### أرقام الجلسات وقت الفحص

| مؤشر | قيمة |
|------|------|
| مستخدمون | 16 |
| جلسات `auth.sessions` | 62 |
| جلسات فيها refresh token **نشط** لكن بلا تجديد ≥ 24 ساعة | **61 / 62** |
| مستخدمون جدّدوا الجلسة خلال 24 ساعة | **1** |
| مستخدمون لديهم `account_devices.last_seen_at` خلال 24 ساعة | **1** |

معنى الرقم 61/62: السيرفر ما زال يحتفظ برموز تجديد صالحة، والأجهزة **توقفت عن استخدامها**. هذا عكس فرضية «السيرفر قتل الجلسة».

### عينة حساب العقيلي (`ala***`)

| حدث | وقت UTC |
|-----|---------|
| آخر `auth.sessions.refreshed_at` | 2026-10-07 21:53:15 |
| آخر `account_devices.last_seen_at` (Redmi) | 2026-10-07 21:58:44 |
| بعد ذلك | لا تجديد Auth، لا نبضة جهاز |
| WhatsApp بعد 10-07 في السحِّابة | غالباً `rating_auto_reply` (ويب هوك/سيرفر) وليس بطاقات من التطبيق |

جهاز Redmi بقي مسجلاً `access_status=active` لكن بلا نبضة — لذلك يظهر «غير متصل» رغم وجود الصف.

---

## الأسباب في الكود (مرتبة)

### السبب 1 — مهلة تجديد تُعامل كـ«انتهاء جلسة» ثم `signOut`

**الملف:** `lib/services/auth/ensure_fresh_session.dart`  
إذا بقي أقل من 10 دقائق على انتهاء JWT يُستدعى `refreshSession().timeout(12s)`. عند تجاوز المهلة تُرمى `SessionExpiredException`.

**الملف:** `lib/providers/auth_provider.dart` — `tryRestoreCloudSessionSilently`  
عند التقاط `SessionExpiredException` يُنفَّذ:

```dart
await Supabase.instance.client.auth.signOut();
```

`signOut` الافتراضي يمسح الجلسة محلياً ويحاول إلغاءها على السيرفر.  
**النتيجة:** بطء شبكة / راديو نائم بعد الخلفية → فقدان دائم للجلسة على الجهاز.

### السبب 2 — حارس النبضة قد يتوقف نهائياً

**الملف:** `lib/widgets/cloud_session_resume_bridge.dart`

- إعادة جدولة الـ Timer تحدث **بعد** انتهاء `_runSessionCare`.
- خطوات التسجيل/النبضة (`registerCurrentDevice` / bootstrap) بلا timeout شامل.
- إذا علق طلب واحد: لا تُجدول النبضة التالية؛ و`_sessionCareRunning` يمنع استدعاءات `resume`.

**النتيجة:** التطبيق يعمل محلياً لأيام بلا تجديد JWT وبلا تحديث `last_seen_at` — مطابق لأرقام السيرفر (61 جلسة يتيمة).

### السبب 3 — لا إشعار عند موت الجلسة

مكتبة `gotrue 2.20.0`: عند فشل تجديد غير قابل لإعادة المحاولة تُمسح الجلسة محلياً ويُبث `AuthChangeEvent.signedOut`.  
التطبيق **لا يستمع** لهذا الحدث في المسار العام (فقط مسارات OAuth/marketplace).  
لا بانر دائم؛ التنبيه مدفون في قائمة الحساب عند `currentUser == null`.

### السبب 4 — الاستعادة الصامتة تفشل لمسار Google ثم لا طريق بديل واضح

معظم الحسابات `provider=google`.  
الاستعادة الصامتة تعتمد على كلمة داخلية مخزّنة أو `signInSilently`.  
أي خطأ لا يُصنَّف «شبكة» في `_attemptSupabasePasswordSignIn` يُعامل كبيانات خاطئة وقد يُفضي لمسح كلمة مخزّنة.  
بعدها يبقى المستخدم داخل التطبيق المحلي بدون جلسة سحابة حتى خروج يدوي أو مسح بيانات.

### السبب 5 — تخزين الجلسة + rotation

**الملف:** `lib/services/auth/secure_session_storage.dart`  
عند فشل Keychain/Keystore يُكتب الرمز في SharedPreferences، ثم في إقلاع لاحق قد تُفضَّل نسخة آمنة أقدم.  
مع `refresh_token_rotation_enabled=true` و`reuse_interval=10s`: رمز قديم → فشل تجديد → مسح محلي.  
يفسّر حالات «لا يصلح إلا بمسح بيانات التطبيق».

### السبب 6 (مساعد سيرفر) — نافذة reuse قصيرة

`security_refresh_token_reuse_interval=10` مع rotation: تجديدان متزامنان (autoRefresh + `ensureFreshSession`) خارج 10 ثوانٍ قد يُسقطان عائلة الرموز على العميل.  
هذا **مضاعف** للمشكلة وليس السبب الوحيد (لأن 61 جلسة ما زال لها token نشط على السيرفر = العميل توقّف عن الاستخدام أكثر مما السيرفر ألغى).

---

## لماذا تظهر الأعراض الثلاثة معاً

| العَرَض | الآلية |
|---------|--------|
| التطبيق يعمل بشكل طبيعي | الدخول محلي (`deviceOwnerBound` + SQLite + PIN)؛ لا يعتمد على JWT |
| لا أجهزة متصلة في الحساب | `currentUser == null` → `refreshDevices` لا يملأ القائمة أو يصفّرها؛ و`last_seen_at` لا تُحدَّث |
| WhatsApp بطاقات لا تُرسل | البوابة ترفض عند غياب الجلسة → outbox محلي؛ بينما ردود التقييم من السيرفر قد تستمر |

---

## ما الذي يستبعده الفحص

- السيرفر يُنهي الجلسة بعد مدة ثابتة → **مرفوض** (timebox/inactivity = 0).
- السيرفر يحذف أجهزة الحساب → **مرفوض** (الصفوف باقية).
- الـ hook يكسر التجديد → **غير مدعوم بالدليل**.
- المشكلة «إنترنت مقطوع دائماً» فقط → **جزئي**: الشبكة قد تكون الشرارة؛ الكود يحوّلها لفقدان دائم أو يجمّد الحارس.

---

## لماذا خروج / مسح البيانات «يصلح»

يعيدان إنشاء جلسة Auth جديدة ورمز تجديد جديد في التخزين المحلي، ثم bootstrap + تسجيل الجهاز.  
لا يعالجان الأسباب أعلاه؛ يعيدان الدورة حتى الانقطاع التالي.

---

## ملفات الكود المسؤولة (قائمة عمل لاحقة — بلا تنفيذ الآن)

1. `lib/services/auth/ensure_fresh_session.dart` — تصنيف timeout ≠ انتهاء جلسة  
2. `lib/providers/auth_provider.dart` — منع `signOut` على أخطاء مؤقتة؛ تصنيف أدق لأخطاء الاستعادة  
3. `lib/widgets/cloud_session_resume_bridge.dart` — timeout + إعادة جدولة مضمونة  
4. مستمع `onAuthStateChange` عام + مؤشر اتصال سحابي دائم  
5. `lib/services/auth/secure_session_storage.dart` — عدم تفضيل نسخة أقدم من الرمز  
6. (اختياري سيرفر) مراجعة `security_refresh_token_reuse_interval`

---

## تقارير / وثائق مرتبطة

| ملف | علاقته |
|-----|--------|
| [SILENT_CLOUD_SESSION_RELATED_FINDINGS_2026-10-18.md](./SILENT_CLOUD_SESSION_RELATED_FINDINGS_2026-10-18.md) | ملخص فحوص سابقة في نفس الموضوع (واتساب العقيلي + سلسلة الجلسة) |
| [WEB_SESSION_STORAGE_ACCEPTED_RISK_AR.md](./WEB_SESSION_STORAGE_ACCEPTED_RISK_AR.md) | مخاطر تخزين الجلسة على الويب |
| [PROFESSIONAL_GRADE_AUDIT_V1.md](./PROFESSIONAL_GRADE_AUDIT_V1.md) | تدقيق Auth أوسع (سابق) |
| [DELETE_RELOGIN_DIAGNOSIS.md](./DELETE_RELOGIN_DIAGNOSIS.md) | تشخيص حذف/إعادة دخول |
| `docs/specs/oil_change_whatsapp_reliability_v1.md` | موثوقية واتساب (لا يغطي موت جلسة السحابة صراحةً) |

---

## حدود هذا الفحص

- سجلات Auth التفصيلية عبر Management API (`logs.all`) غير متاحة بنفس المسار القديم.
- لا تلميتر من أجهزة العملاء بعد (`cloud_session_lost(reason)` غير موجود بعد).
- لم يُفحص Keystore على أجهزة العملاء مباشرة.

**نهاية التقرير — بلا تنفيذ.**
