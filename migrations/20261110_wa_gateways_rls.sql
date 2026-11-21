/*
  تضييق صف الربط: كان صاحب الحساب يستطيع بالرمز العادي أن يكتب أي عمود في صفه،
  مثل status أو cloud_phone_number_id، فيدّعي ربطًا غير موجود أو رقمًا ليس له.
  بعد الهجرة يقرأ صفه ويغيّر rating_auto_reply فقط، وبقية الكتابة عبر الدوال.

  شرط التطبيق: نشر whatsapp-gateway بالكتابة عبر عميل الإدارة، ثم الانتظار 24 ساعة.
  الاختبار: 20261110_wa_gateways_rls.test.sql
  الرجوع: 20261110_wa_gateways_rls.rollback.sql
*/

begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';

drop policy if exists tenant_whatsapp_gateways_own on public.tenant_whatsapp_gateways;
drop policy if exists tenant_whatsapp_gateways_select_own on public.tenant_whatsapp_gateways;
drop policy if exists tenant_whatsapp_gateways_update_own on public.tenant_whatsapp_gateways;

create policy tenant_whatsapp_gateways_select_own
  on public.tenant_whatsapp_gateways
  for select to authenticated
  using (user_id = auth.uid());

create policy tenant_whatsapp_gateways_update_own
  on public.tenant_whatsapp_gateways
  for update to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

revoke all on table public.tenant_whatsapp_gateways from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.tenant_whatsapp_gateways from authenticated;
grant select on table public.tenant_whatsapp_gateways to authenticated;
grant update (rating_auto_reply, updated_at)
  on table public.tenant_whatsapp_gateways to authenticated;

commit;
