/*
  المرحلة ب7 «مجيب واتساب» (خطة المساعد، القسم 4.13، المهام م6-4 إلى م6-17).

  - جدار الجمهور للمقالات: درس أو مقال داخلي لا يصل المجيب، والعكس (م6-4).
  - صفحة «ما يقوله المجيب للزبائن» لكل محل (م6-5، م6-6). على الخادم لا في اللقطة،
    لأن إعدادات واتساب الأخرى هنا أصلاً، وأثر التغيير يصير فورياً.
  - التسليم لإنسان (م6-9) وطلبات الزيارة (م6-10).
  - ربط الرد الآلي بدور المجيب في assistant_turns، و«رد خاطئ» (م6-13).

  كل الجداول الجديدة: المحل يقرأ ويعدّل ما له فقط (auth.uid() = حساب المحل)،
  والكتابة من المجيب بمفتاح الخدمة.
*/

-- ------------------------------------------------------------------ م6-4 الجدار
alter table public.assistant_knowledge
  add column if not exists audience text not null default 'app';
do $$ begin
  alter table public.assistant_knowledge
    add constraint assistant_knowledge_audience_check check (audience in ('app', 'whatsapp', 'both'));
exception when duplicate_object then null; end $$;

-- ------------------------------------------------------------------ م6-13 ربط الرد بدوره
alter table public.whatsapp_message_logs
  add column if not exists assistant_turn_id uuid;

-- ------------------------------------------------------------------ م6-5 صفحة المجيب
create table if not exists public.whatsapp_responder_profiles (
  tenant_user_id   uuid primary key,
  -- المفتاح الخاص بكل محل: مطفأ = السلوك الحالي كما هو.
  enabled          boolean not null default false,
  hours            text not null default '' check (char_length(hours) <= 300),
  services         text[] not null default '{}',
  service_duration text not null default '' check (char_length(service_duration) <= 120),
  offer_text       text not null default '' check (char_length(offer_text) <= 300),
  offer_until      date,
  -- [{"text": "...", "source": "owner" | "correction", "at": "..."}]، حتى 20.
  notes            jsonb not null default '[]'::jsonb check (jsonb_typeof(notes) = 'array' and jsonb_array_length(notes) <= 20),
  mention_prices   boolean not null default true,
  mention_stock    boolean not null default true,
  oil_advice       boolean not null default true,
  tone             text not null default 'playful' check (tone in ('playful', 'calm', 'formal')),
  silence          text not null default '2h' check (silence in ('30m', '2h', 'eod')),
  updated_at       timestamptz not null default now(),
  check (coalesce(array_length(services, 1), 0) <= 30)
);

alter table public.whatsapp_responder_profiles enable row level security;
drop policy if exists whatsapp_responder_profiles_own on public.whatsapp_responder_profiles;
create policy whatsapp_responder_profiles_own on public.whatsapp_responder_profiles
  for all to authenticated
  using (tenant_user_id = auth.uid())
  with check (tenant_user_id = auth.uid());

-- ------------------------------------------------------------------ م6-9 التسليم لإنسان
create table if not exists public.whatsapp_handoffs (
  id             bigint generated always as identity primary key,
  tenant_user_id uuid not null,
  customer_phone text not null,
  reason         text not null check (reason in ('no_answer', 'low_rating', 'human', 'fault', 'angry', 'media')),
  question       text not null default '' check (char_length(question) <= 600),
  started_at     timestamptz not null default now(),
  ends_at        timestamptz not null,
  ended_at       timestamptz,
  ended_by       text check (ended_by in ('shop_reply', 'app', 'timeout'))
);

create index if not exists whatsapp_handoffs_open_idx
  on public.whatsapp_handoffs (tenant_user_id, customer_phone, ends_at)
  where ended_at is null;

alter table public.whatsapp_handoffs enable row level security;
drop policy if exists whatsapp_handoffs_own_select on public.whatsapp_handoffs;
create policy whatsapp_handoffs_own_select on public.whatsapp_handoffs
  for select to authenticated using (tenant_user_id = auth.uid());
drop policy if exists whatsapp_handoffs_own_update on public.whatsapp_handoffs;
create policy whatsapp_handoffs_own_update on public.whatsapp_handoffs
  for update to authenticated using (tenant_user_id = auth.uid()) with check (tenant_user_id = auth.uid());

-- ------------------------------------------------------------------ م6-10 طلب الزيارة
create table if not exists public.whatsapp_visit_requests (
  id             bigint generated always as identity primary key,
  tenant_user_id uuid not null,
  customer_phone text not null,
  customer_name  text not null default '' check (char_length(customer_name) <= 80),
  car            text not null default '' check (char_length(car) <= 120),
  request        text not null default '' check (char_length(request) <= 300),
  status         text not null default 'open' check (status in ('open', 'carded', 'closed')),
  created_at     timestamptz not null default now(),
  closed_at      timestamptz
);

-- طلب واحد مفتوح لكل زبون في اليوم: تكرار «أريد أجي» لا يملأ القائمة.
create unique index if not exists whatsapp_visit_requests_one_open
  on public.whatsapp_visit_requests (tenant_user_id, customer_phone, ((created_at at time zone 'Asia/Baghdad')::date))
  where status = 'open';

alter table public.whatsapp_visit_requests enable row level security;
drop policy if exists whatsapp_visit_requests_own_select on public.whatsapp_visit_requests;
create policy whatsapp_visit_requests_own_select on public.whatsapp_visit_requests
  for select to authenticated using (tenant_user_id = auth.uid());
drop policy if exists whatsapp_visit_requests_own_update on public.whatsapp_visit_requests;
create policy whatsapp_visit_requests_own_update on public.whatsapp_visit_requests
  for update to authenticated using (tenant_user_id = auth.uid()) with check (tenant_user_id = auth.uid());

-- ------------------------------------------------------------------ م6-13 «رد خاطئ»
/*
  الصواب يصير ملاحظة في صفحة المجيب لهذا المحل (يستعملها من الرسالة التالية)،
  ويُعلَّم دور المجيب كتصحيح للتعلّم العام. الملاحظات 20 كحد: يسقط أقدم تصحيح،
  وملاحظات المالك لا تُمس.
*/
create or replace function public.whatsapp_correct_reply(p_log_id uuid, p_correct text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tenant uuid := auth.uid();
  v_log record;
  v_text text := left(btrim(coalesce(p_correct, '')), 200);
  v_notes jsonb;
  v_idx int;
begin
  if v_tenant is null then raise exception 'not_signed_in'; end if;
  if char_length(v_text) < 2 then raise exception 'empty_correction'; end if;

  select id, body, assistant_turn_id into v_log
    from public.whatsapp_message_logs
   where id = p_log_id and tenant_user_id = v_tenant and template_key = 'rating_auto_reply';
  if not found then raise exception 'not_found'; end if;

  insert into public.whatsapp_responder_profiles (tenant_user_id) values (v_tenant)
  on conflict (tenant_user_id) do nothing;

  select notes into v_notes from public.whatsapp_responder_profiles where tenant_user_id = v_tenant for update;
  while jsonb_array_length(v_notes) >= 20 loop
    select min(i) - 1 into v_idx
      from jsonb_array_elements(v_notes) with ordinality as e(n, i)
     where e.n ->> 'source' = 'correction';
    if v_idx is null then raise exception 'notes_full'; end if;
    v_notes := v_notes - v_idx;
  end loop;
  v_notes := v_notes || jsonb_build_array(jsonb_build_object(
    'text', v_text, 'source', 'correction', 'at', now()
  ));
  update public.whatsapp_responder_profiles
     set notes = v_notes, updated_at = now()
   where tenant_user_id = v_tenant;

  if v_log.assistant_turn_id is not null then
    update public.assistant_turns
       set s_user_corrected = true, user_correction = v_text
     where id = v_log.assistant_turn_id and tenant_id = v_tenant::text and channel = 'whatsapp';
  end if;

  return jsonb_build_object('ok', true, 'notes', jsonb_array_length(v_notes));
end;
$$;

revoke all on function public.whatsapp_correct_reply(uuid, text) from public, anon;
grant execute on function public.whatsapp_correct_reply(uuid, text) to authenticated;
