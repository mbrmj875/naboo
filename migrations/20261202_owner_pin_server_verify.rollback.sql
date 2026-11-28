-- الرجوع عن 20261202_owner_pin_server_verify.sql.
-- التطبيق الجديد يرجع تلقائياً إلى التحقق على الجهاز إذا اختفت دالة الحافة أو فشلت.
begin;
drop trigger if exists trg_owner_pin_attempts_clear on public.owner_auth_secrets;
drop function if exists public.owner_pin_attempts_clear_on_secret_change();
drop function if exists public.owner_pin_attempt_success(uuid);
drop function if exists public.owner_pin_attempt_begin(uuid);
drop table if exists public.owner_pin_attempts;
commit;
