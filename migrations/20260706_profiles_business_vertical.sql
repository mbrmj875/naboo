-- تخصص النشاط مرتبط بالحساب (مرة واحدة) — يُستورد على كل جهاز عند تسجيل الدخول.
alter table public.profiles
  add column if not exists business_vertical text;

comment on column public.profiles.business_vertical is
  'نوع النشاط (oil_change, supermarket, …) — يُضبط مرة واحدة عند الإعداد الأول';
