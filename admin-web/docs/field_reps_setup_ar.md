# مندوبو الميدان — الرابط والصلاحيات

## الروابط الجاهزة (مباشرة على الهاتف)

**مندوب (أي هاتف من أي مكان):**
```
https://admin.naboo.fun/field/login
```

**أدمن — إنشاء مندوبين ومراقبة الخريطة:**
```
https://admin.naboo.fun/reps
```
(بعد دخول كلمة مرور الأدمن من `/login`)

بديل Vercel:
```
https://naboo-admin.vercel.app/field/login
https://naboo-admin.vercel.app/reps
```

---

## ما تم إنجازه

- [x] نشر Production على Vercel → مُعرَّف على `https://admin.naboo.fun`
- [x] تطبيق جداول SQL `field_reps_v1` على Supabase (`naboo-lic`)
- [x] RLS مفعّل — الوصول عبر service role من السيرفر فقط

---

## كيف تستخدمه الآن

1. افتح `https://admin.naboo.fun/login` وادخل كأدمن.
2. اذهب إلى `https://admin.naboo.fun/reps` وأنشئ مندوباً (اسم ظاهر + اسم مستخدم + كلمة مرور).
3. أعطِ المندوب الرابط `https://admin.naboo.fun/field/login` + حسابه.
4. على الهاتف عند «زيارة جديدة» اسمح بصلاحية **الموقع (GPS)** من المتصفح.

| ماذا | أين |
|------|-----|
| جداول DB | تم تطبيقها على Supabase |
| حساب مندوب | `/reps` من الأدمن |
| GPS | إذن المتصفح على هاتف المندوب |
