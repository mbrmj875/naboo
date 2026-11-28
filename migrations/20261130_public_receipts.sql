/*
  صفحة الفاتورة للزبون على naboo.fun/r/{token} (خطة الطباعة، المرحلة 6).

  - نسخة ثابتة من الإيصال تُرفع عند الطباعة أو المشاركة فقط، لا لكل فاتورة.
  - الجدول مغلق (RLS بلا سياسات): لا يُقرأ ولا يُكتب مباشرة من أي عميل.
  - الكتابة بدالة للحساب المسجّل فقط، وتكتب باسم auth.uid() دائماً.
  - القراءة العامة بدالة تأخذ الرمز وحده وتُرجع النسخة فقط؛ لا تصل لأي جدول آخر.
  - الرمز عشوائي 22 حرفاً أو أكثر (≈131 بت) يولّده الجهاز، فلا يُخمَّن.
  - يبقى الرابط يعمل حتى تُحذف الفاتورة أو تُسترجع (تُعلَّم النسخة ولا تُمسح).
*/

create table if not exists public.public_receipts (
  token             text primary key
                    check (token ~ '^[A-Za-z0-9]{22,64}$'),
  owner_uid         uuid not null,
  local_tenant_id   integer not null default 1,
  invoice_global_id text not null check (char_length(invoice_global_id) <= 64),
  -- نسخة الإيصال كما طُبع: العنوان والأسطر والمجاميع واسم المحل وهاتفه.
  snapshot          jsonb not null
                    check (jsonb_typeof(snapshot) = 'object'
                           and pg_column_size(snapshot) <= 32768),
  -- null = سارية، 'returned' = مسترجعة، 'deleted' = محذوفة.
  state             text check (state in ('returned', 'deleted')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists public_receipts_owner_invoice_idx
  on public.public_receipts (owner_uid, invoice_global_id);

alter table public.public_receipts enable row level security;
revoke all on table public.public_receipts from public, anon, authenticated;

-- ------------------------------------------------------------------ الرفع
-- يُنشئ أو يحدّث نسخة الرمز. رمز موجود لحساب آخر = رفض (لا يُستولى عليه).
create or replace function public.receipt_publish(
  p_token text,
  p_local_tenant_id integer,
  p_invoice_global_id text,
  p_snapshot jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_today int;
begin
  if v_uid is null then
    raise exception 'RECEIPT_UNAUTHENTICATED' using errcode = 'P0001';
  end if;
  if p_token is null or p_token !~ '^[A-Za-z0-9]{22,64}$' then
    raise exception 'RECEIPT_BAD_TOKEN' using errcode = 'P0001';
  end if;
  -- حدّ يومي يمنع إغراق الجدول من حساب واحد.
  select count(*) into v_today from public.public_receipts
   where owner_uid = v_uid and created_at > now() - interval '1 day';
  if v_today >= 5000 then
    raise exception 'RECEIPT_DAILY_LIMIT' using errcode = 'P0001';
  end if;
  insert into public.public_receipts
    (token, owner_uid, local_tenant_id, invoice_global_id, snapshot)
  values
    (p_token, v_uid, coalesce(p_local_tenant_id, 1), p_invoice_global_id, p_snapshot)
  on conflict (token) do update
    set snapshot = excluded.snapshot,
        updated_at = now()
    where public_receipts.owner_uid = v_uid;
  if not found then
    raise exception 'RECEIPT_TOKEN_TAKEN' using errcode = 'P0001';
  end if;
end;
$$;

-- ------------------------------------------------------------------ الحالة
-- عند حذف الفاتورة أو استرجاعها كاملة: كل روابطها تُظهر الحالة.
create or replace function public.receipt_set_state(
  p_invoice_global_id text,
  p_state text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'RECEIPT_UNAUTHENTICATED' using errcode = 'P0001';
  end if;
  if p_state is not null and p_state not in ('returned', 'deleted') then
    raise exception 'RECEIPT_BAD_STATE' using errcode = 'P0001';
  end if;
  update public.public_receipts
     set state = p_state, updated_at = now()
   where owner_uid = v_uid and invoice_global_id = p_invoice_global_id;
end;
$$;

-- ------------------------------------------------------------------ القراءة العامة
-- الرمز وحده يكفي ولا يكشف غير نسخته. رمز بصيغة خاطئة لا يلمس الجدول.
create or replace function public.receipt_public_get(p_token text)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if p_token is null or p_token !~ '^[A-Za-z0-9]{22,64}$' then
    return null;
  end if;
  select case
           when r.state = 'deleted' then jsonb_build_object('state', 'deleted')
           else r.snapshot || jsonb_build_object('state', r.state)
         end
    into v
    from public.public_receipts r
   where r.token = p_token;
  return v;
end;
$$;

-- ------------------------------------------------------------------ مسح داخل التطبيق
-- جهاز آخر في المحل مسح رمزاً لم يُطبع عنده: يعرف فاتورته من الرمز، لحسابه فقط.
create or replace function public.receipt_owner_lookup(p_token text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select r.invoice_global_id
    from public.public_receipts r
   where r.token = p_token and r.owner_uid = auth.uid();
$$;

revoke all on function public.receipt_publish(text, integer, text, jsonb) from public, anon;
revoke all on function public.receipt_set_state(text, text) from public, anon;
revoke all on function public.receipt_public_get(text) from public;
revoke all on function public.receipt_owner_lookup(text) from public, anon;
grant execute on function public.receipt_publish(text, integer, text, jsonb) to authenticated;
grant execute on function public.receipt_set_state(text, text) to authenticated;
grant execute on function public.receipt_public_get(text) to anon, authenticated;
grant execute on function public.receipt_owner_lookup(text) to authenticated;
