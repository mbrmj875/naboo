# إعداد بريد رمز التحقق (8 أرقام) — naboo

التطبيق يستدعي `signInWithOtp` بدون رابط → Supabase يستخدم قالب **Magic link or OTP**.

> **خطأ شائع:** تعديل **Confirm sign up** فقط بينما يصل بريد **Your sign-in link** — يجب تعديل **القالبين**.

## أين تلصق القالب؟

**Authentication** → **Emails** → **Templates** (كما في لقطتك)

الملف الجاهز للنسخ: `docs/supabase_email_otp_template_ar.html`  
(انسخ من السطر `<div dir="rtl"` حتى `</div>` الأخير — **بدون** تعليقات `<!--` في أعلى الملف إن رفض المحرر HTML)

---

## 1) الأهم — Magic link or OTP

1. من القائمة اضغط **Magic link or OTP** (الوصف: *Send a one-time sign-in link or one-time password*)
2. **Subject:** `رمز الدخول — نابو` (احذف `Your sign-in link`)
3. **Body:** احذف كل المحتوى الافتراضي (نص Sign in، أي رابط)
4. الصق HTML من `docs/supabase_email_otp_template_ar.html`
   (من `<div dir="rtl"` حتى نهاية الملف — بدون تعليق `<!--` إن رفض المحرر)
5. تأكد أن المحرر يحتوي **`{{ .Token }}`** ولا يحتوي:
   - `{{ .ConfirmationURL }}`
   - `Sign in`
   - أي `<a href=`
6. **Save**

رابط مباشر (إن فتح):  
https://supabase.com/dashboard/project/rkofqwcuvbzrnmelvxhz/auth/templates/magic-link

---

## 2) Confirm sign up

1. اضغط **Confirm sign up**
2. **Subject:** `تأكيد التسجيل — نابو`
3. الصق HTML من `docs/supabase_email_confirm_signup_template_ar.html`
4. **Save**

---

## 2ب) Reset password

1. اضغط **Reset password**
2. **Subject:** `إعادة تعيين كلمة المرور — نابو`
3. الصق HTML من `docs/supabase_email_reset_password_template_ar.html`
4. تأكد من وجود `{{ .ConfirmationURL }}` (هذا القالب برابط)
5. **Save**

---

## 3) طول الرمز

**Authentication** → **Sign In / Providers** → **Email**

- **OTP length:** `8` (إن وُجد)
- **OTP expiry:** `3600` (60 دقيقة)

---

## 4) SMTP (اختياري لكن موصى به)

في نفس صفحة **Emails** → تبويب **SMTP Settings** → Gmail App Password (منفذ 587).  
يقلّل **504** وحد الإرسال.

---

## 5) اختبار نظيف

1. **Authentication** → **Users** → احذف المستخدم التجريبي، **أو** استخدم `اسمك+test2@gmail.com`
2. من التطبيق: طلب رمز **مرة واحدة** (بريد جديد، ليس ردّ على thread قديم)

---

## كيف تعرف أن القالب صحيح؟

| موضوع البريد | ماذا تفعل |
|--------------|-----------|
| **Your sign-in link** | لم تُحفظ **Magic link or OTP** بعد |
| **رمز الدخول — نابو** | صحيح |
| يظهر الاسم **نابو** (وليس نبو) | صحيح |
| يظهر **8 أرقام** في الصندوق | أدخلها في التطبيق |

## متغيرات القالب

| المتغير | استخدمه؟ |
|---------|----------|
| `{{ .Token }}` | **نعم** |
| `{{ .ConfirmationURL }}` | **لا** — يرسل رابطاً |
