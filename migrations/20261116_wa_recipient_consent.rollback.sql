/*
  يحذف جدول الموافقة ودوالها. الدوال المنشورة تتجاهل غياب الجدول وترسل كالمعتاد.
  تنبيه: يضيع معه سجل من طلب الإيقاف، فصدّر الصفوف قبل التنفيذ.
*/
begin;
drop function if exists public.wa_recipient_consent_set(text, boolean);
drop table if exists public.wa_recipient_consent;
drop function if exists public.wa_phone_key(text);
commit;
