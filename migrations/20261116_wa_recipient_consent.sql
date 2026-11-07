/*
  موافقة الزبون على تذكير الغيار، وطلب الإيقاف.
  قرار صاحب النظام في 7 نوفمبر 2026: الموافقة تتم عند الفاتورة الأولى، والتذكيرات
  تخرج في مواعيدها. لذلك لا يمنع الإرسال إلا opted_out، وغياب الصف لا يمنعه.

  الـ queued وقت تطبيق الهجرة تُسجل owner_declared بإفادة صاحب النظام، ولا تتغير مواعيدها.
*/

begin;

create table if not exists public.wa_recipient_consent (
  tenant_user_id uuid not null references auth.users (id) on delete cascade,
  phone_key text not null check (phone_key ~ '^[0-9]{8,15}$'),
  status text not null check (status in ('consented', 'opted_out')),
  source text not null check (source in (
    'owner_declared', 'invoice_notice', 'staff_declined', 'customer_reply'
  )),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (tenant_user_id, phone_key)
);

alter table public.wa_recipient_consent enable row level security;

revoke all on table public.wa_recipient_consent from public, anon, authenticated;
grant select on table public.wa_recipient_consent to authenticated;
grant all on table public.wa_recipient_consent to service_role;

drop policy if exists wa_recipient_consent_select_own on public.wa_recipient_consent;
create policy wa_recipient_consent_select_own
  on public.wa_recipient_consent
  for select
  to authenticated
  using (auth.uid() = tenant_user_id);

/* آخر 10 أرقام: 07XXXXXXXXX و9647XXXXXXXXX هما الزبون نفسه. */
create or replace function public.wa_phone_key(p_phone text)
returns text
language sql
immutable
set search_path to 'public'
as $function$
  select right(regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g'), 10);
$function$;

/*
  يستدعيها التطبيق عند حفظ البطاقة. طلب الزبون نفسه الإيقاف لا يلغيه خيار مفعّل
  تلقائيًا في بطاقة لاحقة، فهذا يتطلب أن يطلب الزبون التفعيل بنفسه.
*/
create or replace function public.wa_recipient_consent_set(
  p_phone text,
  p_consented boolean
)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant uuid := auth.uid();
  v_key text := public.wa_phone_key(p_phone);
  v_status text := case when p_consented then 'consented' else 'opted_out' end;
  v_source text := case when p_consented then 'invoice_notice' else 'staff_declined' end;
  v_result text;
begin
  if v_tenant is null then
    raise exception 'not_authenticated';
  end if;
  if length(v_key) < 8 then
    return null;
  end if;

  insert into public.wa_recipient_consent as c (
    tenant_user_id, phone_key, status, source
  ) values (v_tenant, v_key, v_status, v_source)
  on conflict (tenant_user_id, phone_key) do update
    set status = excluded.status,
        source = excluded.source,
        updated_at = now()
    where not (c.status = 'opted_out' and c.source = 'customer_reply');

  select status into v_result
  from public.wa_recipient_consent
  where tenant_user_id = v_tenant and phone_key = v_key;

  if v_result = 'opted_out' then
    update public.wa_oil_followup_jobs
    set status = 'cancelled', last_error = 'opted_out', updated_at = now()
    where tenant_user_id = v_tenant
      and status = 'queued'
      and public.wa_phone_key(customer_phone) = v_key;
  end if;
  return v_result;
end;
$function$;

revoke all on function public.wa_recipient_consent_set(text, boolean)
  from public, anon;
grant execute on function public.wa_recipient_consent_set(text, boolean)
  to authenticated, service_role;

/* لا تتغير حالة أي تذكير ولا موعده. */
insert into public.wa_recipient_consent (tenant_user_id, phone_key, status, source)
select distinct j.tenant_user_id, public.wa_phone_key(j.customer_phone), 'consented', 'owner_declared'
from public.wa_oil_followup_jobs j
where j.status = 'queued'
  and length(public.wa_phone_key(j.customer_phone)) >= 8
on conflict (tenant_user_id, phone_key) do nothing;

commit;
