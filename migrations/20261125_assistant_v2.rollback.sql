/* تراجع 20261125_assistant_v2.sql — يحذف جداول المساعد الجديد ودواله ومهمته،
   ويعيد سياستي الإدراج والتحديث على الأمثلة المعتمدة كما كانتا. pg_trgm يبقى. */
begin;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'assistant-purge-old';
  end if;
end $$;

drop function if exists public.assistant_purge_old();
drop function if exists public.assistant_budget_add(text, bigint, integer, integer, text);
drop function if exists public.assistant_budget_check(text, text, boolean);
drop function if exists public.assistant_budget_caps(text, text, boolean);

drop table if exists public.assistant_eval_runs;
drop table if exists public.assistant_eval_cases;
drop table if exists public.assistant_lessons;
drop table if exists public.assistant_budget;
drop table if exists public.assistant_tenant_settings;
drop table if exists public.assistant_turns;

update public.app_remote_config set config = config - 'assistant', updated_at = now() where id = 1;

grant insert, update on table public.assistant_approved_examples to authenticated;
drop policy if exists assistant_examples_insert_tenant on public.assistant_approved_examples;
create policy assistant_examples_insert_tenant on public.assistant_approved_examples
  for insert with check (tenant_id = public.app_current_tenant_id());
drop policy if exists assistant_examples_update_tenant on public.assistant_approved_examples;
create policy assistant_examples_update_tenant on public.assistant_approved_examples
  for update using (tenant_id = public.app_current_tenant_id())
  with check (tenant_id = public.app_current_tenant_id());

commit;
