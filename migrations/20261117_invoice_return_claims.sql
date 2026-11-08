/*
  الاسترجاع المحمي: مطالبات الاسترجاع في الخادم.
  الغرض: منع استرجاع المادة نفسها مرتين من جهازين، أو من جهاز كان بلا إنترنت.
  التطبيق يطالب هنا قبل حفظ المرتجع محلياً؛ بلا إنترنت لا يُسترجع.

  - المستأجر من JWT فقط (app_current_tenant_id)، لا من الجهاز.
  - مفتاح السطر = المعرّف العالمي لسطر الفاتورة الأصلية (ثابت بين الأجهزة).
  - الكمية المباعة تُثبَّت من أول مطالبة للسطر، فلا تتضخم بطلب لاحق.
  - قفل على (المستأجر، الأصل): جهازان في اللحظة نفسها لا يتجاوزان المباع.
  - إعادة الطلب نفسه (نفس معرّف المرتجع) تعيد النتيجة دون تكرار.
  - لا كتابة مباشرة على الجدول: الوصول عبر الدالتين فقط.
*/

begin;

create table if not exists public.invoice_return_claims (
  id bigint generated always as identity primary key,
  tenant_id text not null,
  original_invoice_global_id uuid not null,
  return_invoice_global_id uuid not null,
  line_key text not null check (length(line_key) between 1 and 200),
  qty numeric(14, 4) not null check (qty > 0),
  sold_qty numeric(14, 4) not null check (sold_qty > 0),
  amount numeric(14, 2) not null check (amount >= 0),
  actor text,
  created_at timestamptz not null default now(),
  voided_at timestamptz,
  unique (return_invoice_global_id, line_key)
);

create index if not exists invoice_return_claims_original_idx
  on public.invoice_return_claims (tenant_id, original_invoice_global_id)
  where voided_at is null;

alter table public.invoice_return_claims enable row level security;

revoke all on table public.invoice_return_claims from public, anon, authenticated;
grant all on table public.invoice_return_claims to service_role;

/*
  p_lines: [{"key": "<item global id>", "qty": 2, "sold": 5}, ...]
  يعيد: {"ok": true} أو {"ok": false, "reason": "...", "key": "...", "remaining": n}
*/
create or replace function public.rpc_claim_invoice_return(
  p_original uuid,
  p_return uuid,
  p_lines jsonb,
  p_amount numeric,
  p_actor text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant text := public.app_current_tenant_id();
  v_line jsonb;
  v_key text;
  v_qty numeric;
  v_sold numeric;
  v_fixed_sold numeric;
  v_already numeric;
begin
  if v_tenant is null or v_tenant = '' then
    raise exception 'not_authenticated';
  end if;
  if p_original is null or p_return is null or p_original = p_return then
    return jsonb_build_object('ok', false, 'reason', 'bad_ids');
  end if;
  if jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0
     or jsonb_array_length(p_lines) > 500 then
    return jsonb_build_object('ok', false, 'reason', 'bad_lines');
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(v_tenant || ':' || p_original::text, 0)
  );

  -- الطلب نفسه أعيد (انقطاع بعد النجاح): لا تكرار.
  if exists (
    select 1 from public.invoice_return_claims
    where return_invoice_global_id = p_return
      and tenant_id = v_tenant
      and voided_at is null
  ) then
    return jsonb_build_object('ok', true, 'replay', true);
  end if;

  -- التحقق أولاً لكل الأسطر (مجمّعة بالمفتاح)، ثم الإدراج: لا مطالبة جزئية.
  for v_line in select * from jsonb_array_elements(p_lines) loop
    v_key := nullif(trim(v_line ->> 'key'), '');
    v_qty := (v_line ->> 'qty')::numeric;
    v_sold := (v_line ->> 'sold')::numeric;
    if v_key is null or v_qty is null or v_qty <= 0
       or v_sold is null or v_sold <= 0 then
      return jsonb_build_object('ok', false, 'reason', 'bad_line', 'key', v_key);
    end if;
  end loop;

  for v_key, v_qty, v_sold in
    select trim(e ->> 'key'), sum((e ->> 'qty')::numeric), max((e ->> 'sold')::numeric)
    from jsonb_array_elements(p_lines) e
    group by trim(e ->> 'key')
  loop
    select min(sold_qty), coalesce(sum(qty) filter (where voided_at is null), 0)
      into v_fixed_sold, v_already
    from public.invoice_return_claims
    where tenant_id = v_tenant
      and original_invoice_global_id = p_original
      and line_key = v_key;

    v_fixed_sold := coalesce(v_fixed_sold, v_sold);
    if v_already + v_qty > v_fixed_sold + 0.0001 then
      return jsonb_build_object(
        'ok', false,
        'reason', 'exceeds_sold',
        'key', v_key,
        'remaining', greatest(v_fixed_sold - v_already, 0)
      );
    end if;
  end loop;

  insert into public.invoice_return_claims (
    tenant_id, original_invoice_global_id, return_invoice_global_id,
    line_key, qty, sold_qty, amount, actor
  )
  select v_tenant, p_original, p_return, g.k, g.q,
         coalesce(
           (select min(c.sold_qty) from public.invoice_return_claims c
            where c.tenant_id = v_tenant
              and c.original_invoice_global_id = p_original
              and c.line_key = g.k),
           g.s),
         coalesce(p_amount, 0), left(p_actor, 120)
  from (
    select trim(e ->> 'key') as k,
           sum((e ->> 'qty')::numeric) as q,
           max((e ->> 'sold')::numeric) as s
    from jsonb_array_elements(p_lines) e
    group by trim(e ->> 'key')
  ) g;

  return jsonb_build_object('ok', true);
end;
$function$;

/* يلغي مطالبة لم يكتمل حفظها محلياً، فلا تُحجز المواد ظلماً. */
create or replace function public.rpc_void_return_claim(p_return uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant text := public.app_current_tenant_id();
  v_count integer;
begin
  if v_tenant is null or v_tenant = '' then
    raise exception 'not_authenticated';
  end if;
  update public.invoice_return_claims
     set voided_at = now()
   where return_invoice_global_id = p_return
     and tenant_id = v_tenant
     and voided_at is null;
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$function$;

revoke all on function public.rpc_claim_invoice_return(uuid, uuid, jsonb, numeric, text)
  from public, anon;
revoke all on function public.rpc_void_return_claim(uuid) from public, anon;
grant execute on function public.rpc_claim_invoice_return(uuid, uuid, jsonb, numeric, text)
  to authenticated;
grant execute on function public.rpc_void_return_claim(uuid) to authenticated;

commit;
