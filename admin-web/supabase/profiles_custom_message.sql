-- يشغّل مرة واحدة من Supabase SQL Editor
-- رسالة مخصصة لكل مستخدم (تُعرض في التطبيق بتصميم ملكي).

alter table public.profiles
  add column if not exists custom_message_title_ar text;

alter table public.profiles
  add column if not exists custom_message_body_ar text;

alter table public.profiles
  add column if not exists custom_message_active boolean not null default false;

alter table public.profiles
  add column if not exists custom_message_updated_at timestamptz;

comment on column public.profiles.custom_message_title_ar is 'عنوان الرسالة المخصصة للمستخدم';
comment on column public.profiles.custom_message_body_ar is 'نص الرسالة المخصصة للمستخدم';
comment on column public.profiles.custom_message_active is 'تفعيل/إخفاء الرسالة المخصصة';
comment on column public.profiles.custom_message_updated_at is 'آخر تحديث للرسالة المخصصة';
