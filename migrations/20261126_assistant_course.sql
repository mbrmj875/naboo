/*
  دورة الموظف الجديد (ق63، م3-14).

  - صف لكل مهمة أنهاها موظف. المفتاح (المحل، الموظف، المهمة)، فالتكرار يحدّث الوقت فقط.
  - المحل يقرأ ويكتب صفوفه فقط. المالك يرى نسب موظفيه من هنا على جهازه.
  - لا أسماء مهام حرة: task_id قصير بحروف لاتينية، والاسم الظاهر مقصوص.
*/
begin;

create table if not exists public.assistant_course_progress (
  tenant_id  text not null default public.app_current_tenant_id(),
  user_key   text not null check (length(user_key) between 1 and 80),
  user_name  text check (length(user_name) <= 80),
  task_id    text not null check (task_id ~ '^[a-z0-9_]{1,60}$'),
  done_at    timestamptz not null default now(),
  -- عدد مهام مسار هذا الموظف حسب صلاحياته، ليحسب المالك نسبته الصحيحة.
  path_total smallint check (path_total between 0 and 100),
  primary key (tenant_id, user_key, task_id)
);

alter table public.assistant_course_progress enable row level security;

revoke all on table public.assistant_course_progress from anon;
revoke delete, truncate, references, trigger on table public.assistant_course_progress from authenticated;
grant select, insert, update on table public.assistant_course_progress to authenticated;

drop policy if exists assistant_course_select_own on public.assistant_course_progress;
create policy assistant_course_select_own on public.assistant_course_progress
  for select to authenticated
  using (tenant_id = public.app_current_tenant_id());

drop policy if exists assistant_course_insert_own on public.assistant_course_progress;
create policy assistant_course_insert_own on public.assistant_course_progress
  for insert to authenticated
  with check (tenant_id = public.app_current_tenant_id());

drop policy if exists assistant_course_update_own on public.assistant_course_progress;
create policy assistant_course_update_own on public.assistant_course_progress
  for update to authenticated
  using (tenant_id = public.app_current_tenant_id())
  with check (tenant_id = public.app_current_tenant_id());

commit;
