/*
  تراجع عن 20261110_wa_gateways_rls.sql — يعيد السياسة الشاملة والصلاحيات كما كانت
  في الإنتاج بتاريخ 2026-11-07.
*/

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

drop policy if exists tenant_whatsapp_gateways_select_own on public.tenant_whatsapp_gateways;
drop policy if exists tenant_whatsapp_gateways_update_own on public.tenant_whatsapp_gateways;
drop policy if exists tenant_whatsapp_gateways_own on public.tenant_whatsapp_gateways;

create policy tenant_whatsapp_gateways_own
  on public.tenant_whatsapp_gateways
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke update (rating_auto_reply, updated_at)
  on table public.tenant_whatsapp_gateways from authenticated;
grant all on table public.tenant_whatsapp_gateways to anon, authenticated;

commit;
