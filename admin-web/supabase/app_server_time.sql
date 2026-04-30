-- Trusted Time (مرحلة 1.5)
-- مصدر وقت موثوق من السيرفر للتطبيق.
--
-- شغّل هذا الملف مرة واحدة في Supabase SQL Editor.
-- ملاحظة: هذه الدالة لا تكشف أي بيانات حساسة؛ فقط now().

create or replace function public.app_server_time()
returns timestamptz
language sql
stable
as $$
  select now();
$$;

