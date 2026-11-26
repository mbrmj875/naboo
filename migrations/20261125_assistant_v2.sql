/*
  المساعد الذكي الجديد (خطة docs/specs/naboo_assistant_pro_plan_ar.md، المهام م0-2 و م0-3).

  - كل جداول المساعد هنا للخادم فقط (دور الخدمة). لا سياسة لمستخدمي التطبيق،
    إلا assistant_tenant_settings: المحل يقرأ صفه فقط (هل الجديد مفعّل له).
  - المحادثات تُحفظ منظَّفة بلا نتائج أدوات (ق4، ق50). الحذف بعد 60 يوماً.
  - العدّاد الشهري لكل محل ولكل قناة (app / whatsapp) (ق15، ق51، ق88).
    السقوف من app_remote_config.config.assistant.budget، والسقف الخاص بمحل من
    assistant_tenant_settings.monthly_cap_micro_usd إن وُجد.
  - الهاتف لم يعد يكتب الأمثلة المعتمدة (عيب ع8). صفوفها تُنسخ إلى الدروس كمرشحة.
*/

begin;

create extension if not exists pg_trgm with schema extensions;

-- ------------------------------------------------------------------ المحادثات
create table if not exists public.assistant_turns (
  id               uuid primary key,
  tenant_id        text not null,
  user_id          uuid,
  thread_id        uuid not null,
  channel          text not null default 'app' check (channel in ('app', 'whatsapp')),
  role_key         text not null default '',
  is_owner         boolean not null default false,
  route_id         text,
  app_version      text,
  question_clean   text not null check (length(question_clean) <= 2000),
  answer_clean     text check (length(answer_clean) <= 4000),
  tools            jsonb not null default '[]'::jsonb,
  steps            smallint not null default 1,
  finish           text,
  model            text not null,
  tokens_in        integer,
  tokens_cached    integer,
  tokens_out       integer,
  latency_ms       integer,
  cost_micro_usd   integer,
  budget_mode      text check (budget_mode in ('full', 'economy', 'exhausted')),
  has_image        boolean not null default false,
  used_web         boolean not null default false,
  lesson_ids       bigint[] not null default '{}',
  -- إشارات السلوك (تصل لاحقاً بـ op: signal)
  s_rephrased          boolean,
  s_closed_fast        boolean,
  s_guide_started      boolean,
  s_guide_done         boolean,
  s_guide_abandon_step smallint,
  s_action_kind        text,
  s_action_saved       boolean,
  s_thumb              smallint,
  s_user_corrected     boolean,
  user_correction      text check (length(user_correction) <= 1000),
  -- الحَكَم الليلي
  judged_at        timestamptz,
  j_answered       boolean,
  j_grounded       boolean,
  j_perm_ok        boolean,
  j_no_invention   boolean,
  j_topic          text,
  j_note           text,
  created_at       timestamptz not null default now()
);
create index if not exists assistant_turns_created_idx
  on public.assistant_turns (created_at);
create index if not exists assistant_turns_unjudged_idx
  on public.assistant_turns (created_at) where judged_at is null;
create index if not exists assistant_turns_tenant_idx
  on public.assistant_turns (tenant_id, created_at);

-- ------------------------------------------------------------------ الدروس
create table if not exists public.assistant_lessons (
  id            bigint generated always as identity primary key,
  audience      text not null default 'app' check (audience in ('app', 'whatsapp')),
  -- null = درس عام بشرط المحلَّين. قيمة = تصحيح خاص بمحل واحد (ق90).
  tenant_id     text,
  kind          text not null check (kind in ('rule', 'qa', 'screen_note')),
  topic         text not null,
  trigger_text  text not null,
  body          text not null check (length(body) <= 1200),
  status        text not null check (status in ('candidate', 'active', 'retired', 'rejected')),
  version       integer not null default 1,
  source_turns  integer not null default 0,
  eval_before   numeric,
  eval_after    numeric,
  origin        text not null default 'learn' check (origin in ('learn', 'legacy_example', 'owner_fix', 'manual')),
  created_at    timestamptz not null default now(),
  activated_at  timestamptz,
  retired_at    timestamptz,
  retired_reason text
);
create index if not exists assistant_lessons_trgm_idx
  on public.assistant_lessons using gin (trigger_text extensions.gin_trgm_ops)
  where status = 'active';
create index if not exists assistant_lessons_status_idx
  on public.assistant_lessons (audience, status);

-- ------------------------------------------------------------------ مجموعة الاختبار
create table if not exists public.assistant_eval_cases (
  id          bigint generated always as identity primary key,
  case_key    text not null unique,
  audience    text not null default 'app' check (audience in ('app', 'whatsapp')),
  category    text not null,
  profile     text not null check (profile in ('owner', 'staff_full', 'staff_limited', 'guide_only', 'customer', 'stranger')),
  question    text not null,
  fixtures    jsonb not null default '{}'::jsonb,
  expect      jsonb not null default '{}'::jsonb,
  active      boolean not null default true,
  updated_at  timestamptz not null default now()
);

create table if not exists public.assistant_eval_runs (
  id          bigint generated always as identity primary key,
  target      text not null default 'assistant-chat',
  lesson_id   bigint references public.assistant_lessons (id) on delete set null,
  model       text not null,
  passed      integer not null,
  total       integer not null,
  per_case    jsonb not null,
  note        text,
  created_at  timestamptz not null default now()
);

-- ------------------------------------------------------------------ الكلفة
create table if not exists public.assistant_budget (
  tenant_id        text not null,
  month            date not null,
  channel          text not null default 'app' check (channel in ('app', 'whatsapp')),
  micro_usd        bigint not null default 0,
  today            date,
  today_micro_usd  bigint not null default 0,
  requests         integer not null default 0,
  searches         integer not null default 0,
  images           integer not null default 0,
  updated_at       timestamptz not null default now(),
  primary key (tenant_id, month, channel)
);

-- ------------------------------------------------------------------ إعدادات المحل
create table if not exists public.assistant_tenant_settings (
  tenant_id               text primary key,
  v2_enabled              boolean not null default false,
  -- يرفع أو يخفض السقف الشهري لمحل بعينه. null = الافتراضي من الإعداد العام.
  monthly_cap_micro_usd   bigint check (monthly_cap_micro_usd >= 0),
  wa_monthly_cap_micro_usd bigint check (wa_monthly_cap_micro_usd >= 0),
  -- المحل النموذجي (ق54): لا يدخل التعلّم ولا يُحسب عليه سقف.
  is_demo                 boolean not null default false,
  note                    text,
  updated_at              timestamptz not null default now()
);

-- ------------------------------------------------------------------ الصلاحيات
alter table public.assistant_turns           enable row level security;
alter table public.assistant_lessons         enable row level security;
alter table public.assistant_eval_cases      enable row level security;
alter table public.assistant_eval_runs       enable row level security;
alter table public.assistant_budget          enable row level security;
alter table public.assistant_tenant_settings enable row level security;

revoke all on table public.assistant_turns, public.assistant_lessons,
  public.assistant_eval_cases, public.assistant_eval_runs,
  public.assistant_budget, public.assistant_tenant_settings
  from public, anon, authenticated;
grant all on table public.assistant_turns, public.assistant_lessons,
  public.assistant_eval_cases, public.assistant_eval_runs,
  public.assistant_budget, public.assistant_tenant_settings
  to service_role;

grant select on table public.assistant_tenant_settings to authenticated;
drop policy if exists assistant_tenant_settings_own on public.assistant_tenant_settings;
create policy assistant_tenant_settings_own on public.assistant_tenant_settings
  for select to authenticated
  using (tenant_id = public.app_current_tenant_id());

-- ------------------------------------------------------------------ م0-3: إغلاق كتابة الهاتف في الأمثلة
drop policy if exists assistant_examples_insert_tenant on public.assistant_approved_examples;
drop policy if exists assistant_examples_update_tenant on public.assistant_approved_examples;
revoke insert, update, delete on table public.assistant_approved_examples from anon, authenticated;

insert into public.assistant_lessons (audience, kind, topic, trigger_text, body, status, origin)
select 'app', 'qa', coalesce(nullif(e.topic_key, ''), 'general'),
       left(e.question, 500), left(e.answer, 1200), 'candidate', 'legacy_example'
from public.assistant_approved_examples e
where not exists (
  select 1 from public.assistant_lessons l
  where l.origin = 'legacy_example' and l.trigger_text = left(e.question, 500)
);

-- ------------------------------------------------------------------ الدوال

/* سقوف المحل والقناة بجزء من مليون من الدولار. */
create or replace function public.assistant_budget_caps(
  p_tenant text, p_channel text, p_is_trial boolean
)
returns table (monthly bigint, daily bigint, economy_at bigint, is_demo boolean)
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_cfg jsonb;
  v_monthly bigint;
  v_daily_pct numeric;
  v_economy_pct numeric;
  v_override bigint;
  v_demo boolean := false;
begin
  select coalesce(config -> 'assistant' -> 'budget', '{}'::jsonb)
    into v_cfg from public.app_remote_config where id = 1;
  v_cfg := coalesce(v_cfg, '{}'::jsonb);

  if p_channel = 'whatsapp' then
    v_monthly := coalesce((v_cfg ->> 'wa_monthly_micro_usd')::bigint, 500000);
  elsif p_is_trial then
    v_monthly := coalesce((v_cfg ->> 'trial_monthly_micro_usd')::bigint, 250000);
  else
    v_monthly := coalesce((v_cfg ->> 'monthly_micro_usd')::bigint, 1000000);
  end if;
  v_daily_pct   := coalesce((v_cfg ->> 'daily_pct')::numeric, 8);
  v_economy_pct := coalesce((v_cfg ->> 'economy_pct')::numeric, 70);

  select case when p_channel = 'whatsapp' then s.wa_monthly_cap_micro_usd
              else s.monthly_cap_micro_usd end,
         s.is_demo
    into v_override, v_demo
    from public.assistant_tenant_settings s where s.tenant_id = p_tenant;
  if v_override is not null then v_monthly := v_override; end if;

  monthly    := v_monthly;
  daily      := ceil(v_monthly * v_daily_pct / 100.0)::bigint;
  economy_at := floor(v_monthly * v_economy_pct / 100.0)::bigint;
  is_demo    := coalesce(v_demo, false);
  return next;
end;
$function$;

/* الوضع قبل الطلب: full أو economy أو exhausted. */
create or replace function public.assistant_budget_check(
  p_tenant text, p_channel text default 'app', p_is_trial boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_caps record;
  v_row public.assistant_budget%rowtype;
  v_month date := date_trunc('month', (now() at time zone 'Asia/Baghdad'))::date;
  v_today date := (now() at time zone 'Asia/Baghdad')::date;
  v_used_today bigint := 0;
  v_mode text := 'full';
begin
  if p_tenant is null or p_tenant = '' then
    raise exception 'bad_tenant';
  end if;
  select * into v_caps from public.assistant_budget_caps(p_tenant, p_channel, p_is_trial);
  select * into v_row from public.assistant_budget b
   where b.tenant_id = p_tenant and b.month = v_month and b.channel = p_channel;
  if v_row.today = v_today then v_used_today := v_row.today_micro_usd; end if;

  if not v_caps.is_demo then
    if coalesce(v_row.micro_usd, 0) >= v_caps.monthly or v_used_today >= v_caps.daily then
      v_mode := 'exhausted';
    elsif coalesce(v_row.micro_usd, 0) >= v_caps.economy_at then
      v_mode := 'economy';
    end if;
  end if;

  return jsonb_build_object(
    'mode', v_mode,
    'used', coalesce(v_row.micro_usd, 0),
    'used_today', v_used_today,
    'monthly', v_caps.monthly,
    'daily', v_caps.daily,
    'pct', case when v_caps.monthly > 0
                then round(coalesce(v_row.micro_usd, 0) * 100.0 / v_caps.monthly, 1)
                else 100 end
  );
end;
$function$;

/* زيادة ذرّية بعد الطلب بالكلفة الفعلية. */
create or replace function public.assistant_budget_add(
  p_tenant text, p_micro_usd bigint, p_searches integer default 0,
  p_images integer default 0, p_channel text default 'app'
)
returns void
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  v_month date := date_trunc('month', (now() at time zone 'Asia/Baghdad'))::date;
  v_today date := (now() at time zone 'Asia/Baghdad')::date;
begin
  if p_tenant is null or p_tenant = '' or p_micro_usd < 0 then
    raise exception 'bad_args';
  end if;
  insert into public.assistant_budget as b
    (tenant_id, month, channel, micro_usd, today, today_micro_usd, requests, searches, images)
  values (p_tenant, v_month, p_channel, p_micro_usd, v_today, p_micro_usd, 1,
          greatest(p_searches, 0), greatest(p_images, 0))
  on conflict (tenant_id, month, channel) do update set
    micro_usd       = b.micro_usd + excluded.micro_usd,
    today_micro_usd = case when b.today = v_today
                           then b.today_micro_usd + excluded.micro_usd
                           else excluded.micro_usd end,
    today           = v_today,
    requests        = b.requests + 1,
    searches        = b.searches + excluded.searches,
    images          = b.images + excluded.images,
    updated_at      = now();
end;
$function$;

/* حذف المحادثات الأقدم من 60 يوماً. */
create or replace function public.assistant_purge_old()
returns integer
language plpgsql
volatile
security definer
set search_path to 'public'
as $function$
declare
  v_n integer;
begin
  delete from public.assistant_turns where created_at < now() - interval '60 days';
  get diagnostics v_n = row_count;
  return v_n;
end;
$function$;

revoke all on function public.assistant_budget_caps(text, text, boolean) from public, anon, authenticated;
revoke all on function public.assistant_budget_check(text, text, boolean) from public, anon, authenticated;
revoke all on function public.assistant_budget_add(text, bigint, integer, integer, text) from public, anon, authenticated;
revoke all on function public.assistant_purge_old() from public, anon, authenticated;
grant execute on function public.assistant_budget_caps(text, text, boolean) to service_role;
grant execute on function public.assistant_budget_check(text, text, boolean) to service_role;
grant execute on function public.assistant_budget_add(text, bigint, integer, integer, text) to service_role;
grant execute on function public.assistant_purge_old() to service_role;

-- ------------------------------------------------------------------ الإعداد العام (ق31: مفتاح الإيقاف ومفاتيح القدرات)
update public.app_remote_config
   set config = config || jsonb_build_object('assistant', jsonb_build_object(
         'v2_rollout', 'tenants',
         'kill', false,
         'caps', jsonb_build_object(
           'execute', true, 'web', true, 'images', true, 'whatsapp_responder', true),
         'budget', jsonb_build_object(
           'monthly_micro_usd', 1000000,
           'trial_monthly_micro_usd', 250000,
           'wa_monthly_micro_usd', 500000,
           'daily_pct', 8,
           'economy_pct', 70)
       )),
       updated_at = now()
 where id = 1 and not (config ? 'assistant');

-- ------------------------------------------------------------------ مهمة الحذف اليومية (03:40 بغداد، بعيداً عن مهام واتساب)
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'assistant-purge-old';
    perform cron.schedule('assistant-purge-old', '40 0 * * *',
      $cron$ select public.assistant_purge_old(); $cron$);
  end if;
end $$;

commit;
