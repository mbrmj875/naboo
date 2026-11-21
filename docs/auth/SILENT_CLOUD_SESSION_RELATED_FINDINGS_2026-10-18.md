# ملحق — فحوص سابقة مرتبطة بانقطاع الجلسة / واتساب

**تاريخ التجميع:** 2026-10-18  
**الغرض:** حفظ نتائج الفحوص السابقة حول نفس الموضوع بصيغة Markdown (كانت في المحادثة فقط).  
**التقرير الجذري (أول قراءة):** [SILENT_CLOUD_SESSION_DEATH_ROOT_CAUSE_2026-10-18.md](./SILENT_CLOUD_SESSION_DEATH_ROOT_CAUSE_2026-10-18.md)  
**مرجع الثقة الهندسية (أعيد التحقق — أدق):** [SILENT_CLOUD_SESSION_ENGINEERING_CONFIDENCE_2026-10-18.md](./SILENT_CLOUD_SESSION_ENGINEERING_CONFIDENCE_2026-10-18.md)

---

## 1) واتساب العقيلي — توقف الإرسال من التطبيق

### ماذا رُصد

- رسائل بطاقات زيت فشلت محلياً برسالة من نوع «سبب غير معروف من واتساب».
- السبب الفعلي في مسار العميل: غياب جلسة Supabase (`currentUser == null` / `no_session`) قبل استدعاء Edge Function `whatsapp-gateway`.
- الرسائل دخلت جدول outbox المحلي `oil_change_wa_outbox` بدل الوصول للبوابة.

### ربط زمني مع السيرفر

| مؤشر | قيمة |
|------|------|
| آخر تجديد Auth للعقيلي | 2026-10-07 21:53 UTC |
| آخر نبضة جهاز Redmi | 2026-10-07 21:58 UTC |
| رسائل سحابية بعد ذلك لنفس المستأجر | غالباً `rating_auto_reply` (مسار سيرفر)، ليست بطاقات من التطبيق |

### ملفات المسار

- `lib/verticals/oil_change/services/oil_change_whatsapp_gateway_service.dart` — يرفض عند لا جلسة
- `lib/verticals/oil_change/services/oil_change_whatsapp_outbox.dart` — طابور محلي
- `lib/verticals/oil_change/utils/whatsapp_failure_reason_ar.dart` — ترجمة سبب الفشل للواجهة

### ملاحظة منفصلة (ليست موت الجلسة)

- عطل سابق لحالة `sending` في قيد `whatsapp_message_logs` حُلّ بإضافة حالات `queued` / `sending` / `accepted` وتعديل إدراج المحفظة إلى `queued`. هذا عطل مختلف عن انقطاع الجلسة.

---

## 2) عَرَض «التطبيق يعمل لكن بلا أجهزة»

### ماذا يحدث في الواجهة

عند `Supabase.auth.currentUser == null`:

1. قائمة الحساب تعرض «جلسة السحابة منتهية» وعدد أجهزة `—`.
2. `CloudSyncService.refreshDevices()` لا يُحدّث القائمة أو يصفّرها (`devices.value = []` عند غياب المستخدم أو في `stopForSignOut`).
3. صفوف `account_devices` على السيرفر **لا تُحذف**؛ فقط تتوقف `last_seen_at`.

### ملفات المسار

- `lib/owner/widgets/owner_account_profile_menu.dart` — عرض حالة الجلسة/الأجهزة
- `lib/services/cloud_sync_service.dart` — `cloudSessionHeartbeat` / `registerCurrentDevice` / `refreshDevices`

---

## 3) سلسلة المكوّنات المتصلة بالمشكلة

```
[تخزين جلسة] SecureLocalStorage / SharedPreferences
        ↓
[JWT ساعة + refresh rotation] gotrue / Supabase Auth
        ↓
[تجديد صريح] ensureFreshSession  ←── timeout 12s = SessionExpiredException
        ↓
[استعادة صامتة] tryRestoreCloudSessionSilently  ←── signOut عند SessionExpiredException
        ↓
[نبضة دورية] CloudSessionResumeBridge → cloudSessionHeartbeat → account_devices.last_seen_at
        ↓
[عمليات سحابية] WhatsApp gateway / sync / قائمة الأجهزة
```

كسر أي حلقة فوق خط النبضة يوقف الأجهزة وواتساب التطبيق دون إيقاف العمل المحلي.

---

## 4) وثائق أخرى في المستودع (سياق Auth أوسع)

ليست كلها عن «الموت الصامت»، لكنها ذات صلة عند الإصلاح لاحقاً:

| ملف | موضوع |
|-----|--------|
| `docs/auth/WEB_SESSION_STORAGE_ACCEPTED_RISK_AR.md` | مخاطر تخزين الجلسة على الويب |
| `docs/auth/PROFESSIONAL_GRADE_AUDIT_V1.md` | تدقيق Auth شامل |
| `docs/auth/PROFESSIONAL_GRADE_FIX_PLAN_V1.md` | خطة إصلاح Auth |
| `docs/auth/DELETE_RELOGIN_DIAGNOSIS.md` | حذف حساب / إعادة دخول |
| `docs/auth/SENSITIVE_ISSUES_AUDIT_REPORT.md` | قضايا حساسة |
| `docs/auth/phase5_deferred_decisions.md` | قرارات مؤجّلة تشمل تجديد الجلسة |
| `docs/specs/oil_change_whatsapp_reliability_v1.md` | مصفوفة فشل واتساب (لا تذكر موت جلسة السحابة صراحةً) |

---

## 5) الحكم المختصر من الفحوص السابقة + فحص السيرفر

| سؤال | جواب |
|------|------|
| أين المشكلة؟ | عميل Flutter (تجديد + استعادة + نبضة + تخزين) |
| هل السيرفر يُسقط الجلسات بسياسة زمنية؟ | لا |
| هل أجهزة الحساب تُحذف؟ | لا |
| هل واتساب البطاقات يتعطل بسبب ذلك؟ | نعم، عند غياب الجلسة محلياً |
| هل خروج/مسح البيانات حل جذري؟ | لا — إعادة إنشاء جلسة فقط |

**نهاية الملحق — بلا تنفيذ.**
