/*
  المرحلة ب6 «التعلّم» لمساعد نابو (4.7، م5).

  1. الدروس: دمج القواعد (merged_from)، وطلب اختبار يدوي من لوحة الإدارة
     (eval_requested_at).
  2. اختيار أسئلة الحَكَم الليلي: غير محكوم من آخر 36 ساعة، بلا تشغيلات
     الاختبار، ومن عليه إشارة فشل أولاً ثم عينة عشوائية.
  3. أثر كل درس: كم سؤالاً استعمله وكم فشل منها، مع المتوسط العام، للتقاعد.
  4. المهمتان الدوريتان: الليلية 23:30 عالمي (02:30 بغداد، خارج الذروة)،
     واختبار المرشحين كل 10 دقائق (استعلام واحد إن لم يوجد مرشح).
     لا تتزامنان مع مهام واتساب (أوقاتها دقائق كاملة 0/5/15).
  5. بريد تنبيه الدعم (م5-10) في جدول الخادم وحده، لا في الإعداد الذي يقرؤه التطبيق.

  كل الدوال للخادم وحده (service_role).
*/
begin;

-- ------------------------------------------------------------ 1. الدروس
alter table public.assistant_lessons
  add column if not exists merged_from bigint[],
  add column if not exists eval_requested_at timestamptz;

alter table public.assistant_support_requests
  add column if not exists notified_at timestamptz;

-- ------------------------------------------------------------ 2. اختيار أسئلة الحَكَم
create or replace function public.assistant_pick_for_judging(p_limit integer, p_channel text default 'app')
returns table (
  id uuid,
  tenant_id text,
  is_owner boolean,
  role_key text,
  route_id text,
  question_clean text,
  answer_clean text,
  tools jsonb,
  finish text,
  s_user_corrected boolean,
  user_correction text
)
language sql
stable
security definer
set search_path = public
as $$
  select t.id, t.tenant_id, t.is_owner, t.role_key, t.route_id, t.question_clean, t.answer_clean,
         t.tools, t.finish, t.s_user_corrected, t.user_correction
    from public.assistant_turns t
   where t.judged_at is null
     and t.channel = p_channel
     and coalesce(t.app_version, '') <> 'eval'
     and t.answer_clean is not null
     and t.created_at > now() - interval '36 hours'
   order by (coalesce(t.s_user_corrected, false)
             or coalesce(t.s_rephrased, false)
             or coalesce(t.s_closed_fast, false)
             or coalesce(t.s_thumb, 0) < 0
             or t.s_guide_abandon_step is not null) desc,
            random()
   limit least(greatest(p_limit, 1), 500);
$$;

-- ------------------------------------------------------------ 3. أثر الدروس
create or replace function public.assistant_lesson_usage(p_days integer default 30)
returns table (
  id bigint,
  activated_at timestamptz,
  uses integer,
  judged integer,
  fails integer,
  overall_judged integer,
  overall_fails integer
)
language sql
stable
security definer
set search_path = public
as $$
  with recent as (
    select t.lesson_ids,
           t.judged_at is not null as judged,
           (t.j_answered is false or t.j_grounded is false or t.j_perm_ok is false
            or t.j_no_invention is false or coalesce(t.s_user_corrected, false)) as failed
      from public.assistant_turns t
     where t.channel = 'app'
       and coalesce(t.app_version, '') <> 'eval'
       and t.created_at > now() - make_interval(days => greatest(p_days, 1))
  ),
  overall as (
    select count(*) filter (where judged)::integer as j,
           count(*) filter (where judged and failed)::integer as f
      from recent
  ),
  per as (
    select u.lid,
           count(*)::integer as uses,
           count(*) filter (where r.judged)::integer as judged,
           count(*) filter (where r.judged and r.failed)::integer as fails
      from recent r, unnest(r.lesson_ids) as u(lid)
     group by u.lid
  )
  select l.id, l.activated_at, coalesce(p.uses, 0), coalesce(p.judged, 0), coalesce(p.fails, 0), o.j, o.f
    from public.assistant_lessons l
    cross join overall o
    left join per p on p.lid = l.id
   where l.status = 'active' and l.audience = 'app';
$$;

revoke all on function public.assistant_pick_for_judging(integer, text) from public, anon, authenticated;
revoke all on function public.assistant_lesson_usage(integer) from public, anon, authenticated;
grant execute on function public.assistant_pick_for_judging(integer, text) to service_role;
grant execute on function public.assistant_lesson_usage(integer) to service_role;

-- ------------------------------------------------------------ 4. المهمتان الدوريتان
insert into public.ops_edge_cron_config (key, value)
values ('assistant_learn_url', 'https://rkofqwcuvbzrnmelvxhz.supabase.co/functions/v1/assistant-learn')
on conflict (key) do update set value = excluded.value;

select cron.unschedule(jobname) from cron.job where jobname in ('assistant-learn-nightly', 'assistant-learn-evaluate');

select cron.schedule(
  'assistant-learn-nightly',
  '30 23 * * *',
  $cron$
    select net.http_post(
      url := (select value from public.ops_edge_cron_config where key = 'assistant_learn_url'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select value from public.ops_edge_cron_config where key = 'cron_bearer')
      ),
      body := '{"op":"nightly"}'::jsonb,
      timeout_milliseconds := 150000
    );
  $cron$
);

-- 3، 13، 23…: بعيداً عن الدقائق الكاملة التي تشغل فيها مهام واتساب.
select cron.schedule(
  'assistant-learn-evaluate',
  '3-59/10 * * * *',
  $cron$
    select net.http_post(
      url := (select value from public.ops_edge_cron_config where key = 'assistant_learn_url'),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || (select value from public.ops_edge_cron_config where key = 'cron_bearer')
      ),
      body := '{"op":"evaluate"}'::jsonb,
      timeout_milliseconds := 150000
    )
    where exists (
      select 1 from public.assistant_lessons
       where status = 'candidate' and audience = 'app' and tenant_id is null
         and (origin = 'learn' or eval_requested_at is not null)
    );
  $cron$
);

-- ------------------------------------------------------------ 5. بريد الدعم
insert into public.ops_edge_cron_config (key, value)
values ('assistant_support_email', 'support@naboo.fun')
on conflict (key) do nothing;

commit;
