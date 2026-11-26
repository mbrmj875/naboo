/*
  المرحلة ب4 «البيانات والخبرة» لمساعد نابو.

  1. دليل السيارات المشترك (4.9، م1-13): مواصفات الزيت لكل موديل، وأسماء دارجة.
     الخادم وحده يقرأ ويكتب (service role). لا وصول للتطبيق.
  2. طلبات الدعم من المساعد (م1-18): ملخص منظَّف بلا أرقام مالية، يقرؤه صاحب
     المشروع من لوحة الإدارة. الخادم يكتب.
  3. مكتبة المعرفة ونصوص نابو (م1-30، 4.13ج): يكتبها صاحب المشروع من اللوحة،
     ويسترجعها الخادم للسؤال. لا وصول للتطبيق.
  4. ذاكرة المحل (م1-17، ق52): ما طلب المستخدم تذكّره. كل محل يرى صفوفه فقط،
     ويُقرأ من كل أجهزته. الحذف من التطبيق للمالك وحده (الحساب مشترك بين
     أجهزة المحل، فالقيد في التطبيق).
*/
begin;

-- ------------------------------------------------------------ 1. دليل السيارات
create table if not exists public.assistant_car_specs (
  id                bigserial primary key,
  make              text not null check (length(make) between 1 and 40),
  model             text not null check (length(model) between 1 and 60),
  year_from         smallint not null check (year_from between 1970 and 2100),
  year_to           smallint not null check (year_to between 1970 and 2100),
  engine            text check (length(engine) <= 40),
  fuel              text check (fuel in ('petrol', 'diesel', 'hybrid')),
  oil_capacity_l    numeric(4, 2) check (oil_capacity_l between 0.5 and 30),
  viscosity_primary text check (length(viscosity_primary) <= 20),
  viscosity_alt     text check (length(viscosity_alt) <= 20),
  oil_spec          text check (length(oil_spec) <= 80),
  oil_filter_refs   jsonb not null default '[]',
  interval_km       integer check (interval_km between 1000 and 50000),
  notes             text check (length(notes) <= 400),
  sources           jsonb not null default '[]',
  confidence        text not null check (confidence in ('verified', 'single_source')),
  locked            boolean not null default false,
  hits              integer not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check (year_to >= year_from)
);
create index if not exists assistant_car_specs_lookup
  on public.assistant_car_specs (make, model, year_from, year_to);

create table if not exists public.assistant_car_aliases (
  alias_norm text primary key check (length(alias_norm) between 1 and 60),
  make       text not null,
  model      text not null
);

-- ------------------------------------------------------------ 2. طلبات الدعم
create table if not exists public.assistant_support_requests (
  id          bigserial primary key,
  tenant_id   text not null,
  user_id     uuid,
  role_key    text,
  route_id    text check (length(route_id) <= 80),
  summary     text not null check (length(summary) between 1 and 600),
  status      text not null default 'open' check (status in ('open', 'done')),
  created_at  timestamptz not null default now(),
  resolved_at timestamptz
);
create index if not exists assistant_support_requests_open
  on public.assistant_support_requests (status, created_at desc);

-- ------------------------------------------------------------ 3. المكتبة ونصوص نابو
create table if not exists public.assistant_knowledge (
  id         bigserial primary key,
  kind       text not null check (kind in ('library', 'naboo')),
  title      text not null check (length(title) between 1 and 120),
  body       text not null check (length(body) between 1 and 4000),
  keywords   text not null default '' check (length(keywords) <= 400),
  published  boolean not null default false,
  updated_at timestamptz not null default now()
);
create index if not exists assistant_knowledge_published
  on public.assistant_knowledge (kind, published);

-- ------------------------------------------------------------ 4. ذاكرة المحل
create table if not exists public.assistant_shop_memory (
  id         bigserial primary key,
  tenant_id  text not null default public.app_current_tenant_id(),
  text       text not null check (length(text) between 1 and 300),
  created_by text check (length(created_by) <= 80),
  created_at timestamptz not null default now()
);
create index if not exists assistant_shop_memory_tenant on public.assistant_shop_memory (tenant_id, created_at desc);

-- الخادم وحده للجداول الثلاثة الأولى.
alter table public.assistant_car_specs enable row level security;
alter table public.assistant_car_aliases enable row level security;
alter table public.assistant_support_requests enable row level security;
alter table public.assistant_knowledge enable row level security;
revoke all on table public.assistant_car_specs, public.assistant_car_aliases,
  public.assistant_support_requests, public.assistant_knowledge from anon, authenticated;

-- الذاكرة: المحل يقرأ ويضيف ويحذف صفوفه فقط، ولا تعديل.
alter table public.assistant_shop_memory enable row level security;
revoke all on table public.assistant_shop_memory from anon;
revoke update, truncate, references, trigger on table public.assistant_shop_memory from authenticated;
grant select, insert, delete on table public.assistant_shop_memory to authenticated;
grant usage on sequence public.assistant_shop_memory_id_seq to authenticated;

drop policy if exists assistant_memory_select_own on public.assistant_shop_memory;
create policy assistant_memory_select_own on public.assistant_shop_memory
  for select to authenticated using (tenant_id = public.app_current_tenant_id());

drop policy if exists assistant_memory_insert_own on public.assistant_shop_memory;
create policy assistant_memory_insert_own on public.assistant_shop_memory
  for insert to authenticated with check (tenant_id = public.app_current_tenant_id());

drop policy if exists assistant_memory_delete_own on public.assistant_shop_memory;
create policy assistant_memory_delete_own on public.assistant_shop_memory
  for delete to authenticated using (tenant_id = public.app_current_tenant_id());

commit;
