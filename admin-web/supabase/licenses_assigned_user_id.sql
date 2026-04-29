-- يُشغَّل مرة واحدة من Supabase SQL Editor لمشروع التطبيق.
-- يضيف حقلاً لتتبع من أُعطيَ هذا المفتاح (للوحة الإدارة فقط؛ تطبيق Flutter لا يعتمد على الحقل).

alter table public.licenses
  add column if not exists assigned_user_id uuid references auth.users (id) on delete set null;

comment on column public.licenses.assigned_user_id is 'حساب Supabase الذي أُسند إليه المفتاح (تتبع إداري)';

create index if not exists idx_licenses_assigned_user_id on public.licenses (assigned_user_id);
create index if not exists idx_licenses_expires_at_active on public.licenses (expires_at)
  where expires_at is not null;

-- ────────────────────────────────────────────────────────────────────────────
-- يجب أن يستطيع المستخدم المسجّل (JWT) قراءة صف الترخيص المسند له فقط:
-- التطبيق يستدعي: from('licenses').select().eq('assigned_user_id', user.id)
--
-- 1) إن كان RLS معطّلاً على public.licenses (غالباً كذلك لأن التحقق من المفتاح يمر عبر REST + anon):
grant select on table public.licenses to authenticated;

-- 2) إن كان RLS مفعّلاً على جدول licenses، نفّذ أيضاً السياسات التالية (مع سياسة anon وإلا ينكسر التحقق من المفتاح عبر REST):
-- alter table public.licenses enable row level security;
--
-- drop policy if exists licenses_select_own_assigned on public.licenses;
-- create policy licenses_select_own_assigned
--   on public.licenses for select to authenticated
--   using (assigned_user_id is not null and auth.uid() = assigned_user_id);
--
-- إن لم تكن لديك سياسة لـ anon مسبقاً، أضف نسختك الآمنة لقراءة حسب license_key؛
-- هذا المشروع يستخدم anon GET/PATCH إلى ?license_key=eq — تأكد من عدم قطع ذلك.
