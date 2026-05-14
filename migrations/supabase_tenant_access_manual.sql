-- تشغيل يدوي في Supabase Studio (ربط Supabase CLI لاحقاً في sprint منفصل).
-- سياسة الوصول: المستخدم يُعتبر «مسموحاً بالعمل» فقط إذا:
--   kill_switch = false  AND  valid_until > الآن (يفضّل وقت موثوق من السيرفر وليس ساعة الجهاز فقط).
--
-- ملاحظة: عدّل مرجع tenant_id حسب مخططك (مثلاً ربط بجدول tenants أو profiles حسب العمود الفعلي).

create table if not exists public.tenant_access (
  tenant_id integer primary key,
  kill_switch boolean not null default false,
  valid_until timestamptz not null,
  access_status text,
  grace_until timestamptz,
  notes text,
  updated_at timestamptz not null default now()
);

comment on table public.tenant_access is
  'Kill switch فوري + صلاحية زمنية؛ النشاط المسموح فقط عندما kill_switch=false و valid_until > الوقت الموثوق.';

alter table public.tenant_access enable row level security;

-- قراءة الصف الخاص بالمستأجر المرتبط بالجلسة فقط (يتطلب دالة app_current_tenant_id() أو ما يعادلها).
-- أنشئ الدالة أولاً إن لم تكن موجودة، ثم فعّل السياسة التالية بعد التحقق من أسماء الجداول.

-- مثال (عدّل الشرط حسب تعريفك لـ tenant في JWT/جدول profiles):
-- create policy "tenant_access_select_own"
--   on public.tenant_access for select
--   using (tenant_id = app_current_tenant_id());
