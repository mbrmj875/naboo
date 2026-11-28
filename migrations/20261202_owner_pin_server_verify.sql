-- التحقق من رمز PIN المالك على السيرفر مع حد للمحاولات (المرحلة 1).
--
-- رمز PIN أربعة أرقام فقط: من يحصل على الـ hash يجرّب 10,000 احتمال دون
-- اتصال خلال ثوانٍ. لذلك ينتقل التحقق إلى دالة الحافة owner-pin-verify، وهذه
-- الهجرة تعطيها عدّاد محاولات ذرّياً لا يصل إليه التطبيق مباشرة.
--
-- المرحلة 2 (هجرة لاحقة بعد تحديث كل الأجهزة): app_get_owner_auth_secret
-- لا يُرجع الـ hash إلا بعد رمز بريد حديث، وتُحذف سياسة القراءة المباشرة.
-- الرجوع: 20261202_owner_pin_server_verify.rollback.sql

begin;

create table if not exists public.owner_pin_attempts (
  user_id         uuid primary key references auth.users (id) on delete cascade,
  failed_count    integer not null default 0,
  lockouts        integer not null default 0,
  locked_until    timestamptz,
  last_attempt_at timestamptz not null default now()
);

alter table public.owner_pin_attempts enable row level security;
revoke all on table public.owner_pin_attempts from public, anon, authenticated;

-- يحجز محاولة قبل حساب PBKDF2، فلا تتخطى الطلبات المتوازية الحد.
-- يُرجع: {allowed, locked_until, remaining}.
create or replace function public.owner_pin_attempt_begin(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  c_max_failures constant int := 5;
  r public.owner_pin_attempts%rowtype;
begin
  if p_user_id is null then
    raise exception 'PIN_USER_REQUIRED';
  end if;

  insert into public.owner_pin_attempts (user_id) values (p_user_id)
  on conflict (user_id) do nothing;

  select * into r from public.owner_pin_attempts where user_id = p_user_id for update;

  if r.locked_until is not null and r.locked_until > now() then
    return jsonb_build_object('allowed', false, 'locked_until', r.locked_until, 'remaining', 0);
  end if;

  -- انتهى القفل: صفحة جديدة من المحاولات، ويبقى عدد مرات القفل للتصعيد.
  if r.locked_until is not null then
    r.failed_count := 0;
    r.locked_until := null;
  end if;

  r.failed_count := r.failed_count + 1;
  if r.failed_count >= c_max_failures then
    -- 15 دقيقة، ثم 30، ثم ساعة… حتى 12 ساعة. إعادة تعيين PIN بالبريد تمسحه.
    r.locked_until := now() + least(interval '15 minutes' * power(2, r.lockouts), interval '12 hours');
    r.lockouts := r.lockouts + 1;
  end if;

  update public.owner_pin_attempts
  set failed_count = r.failed_count,
      lockouts = r.lockouts,
      locked_until = r.locked_until,
      last_attempt_at = now()
  where user_id = p_user_id;

  -- المحاولة الخامسة نفسها مسموحة؛ القفل يسري على ما بعدها إن فشلت.
  return jsonb_build_object(
    'allowed', true,
    'locked_until', r.locked_until,
    'remaining', greatest(c_max_failures - r.failed_count, 0)
  );
end;
$function$;

-- رمز صحيح: تُمسح المحاولات كلها.
create or replace function public.owner_pin_attempt_success(p_user_id uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $function$
  delete from public.owner_pin_attempts where user_id = p_user_id;
$function$;

revoke execute on function public.owner_pin_attempt_begin(uuid) from public, anon, authenticated;
revoke execute on function public.owner_pin_attempt_success(uuid) from public, anon, authenticated;
grant execute on function public.owner_pin_attempt_begin(uuid) to service_role;
grant execute on function public.owner_pin_attempt_success(uuid) to service_role;

-- تعيين PIN جديد (بعد رمز البريد) يفك القفل.
create or replace function public.owner_pin_attempts_clear_on_secret_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
begin
  if tg_op = 'INSERT' or new.pin_hash is distinct from old.pin_hash then
    delete from public.owner_pin_attempts where user_id = new.user_id;
  end if;
  return new;
end;
$function$;
revoke execute on function public.owner_pin_attempts_clear_on_secret_change() from public, anon, authenticated;

drop trigger if exists trg_owner_pin_attempts_clear on public.owner_auth_secrets;
create trigger trg_owner_pin_attempts_clear
  after insert or update of pin_hash on public.owner_auth_secrets
  for each row execute function public.owner_pin_attempts_clear_on_secret_change();

commit;
