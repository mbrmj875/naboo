## Regression Security Suite — Supabase (Service Orders)

هذا الملف هو **مجموعة اختبارات أمان رجعية** (Regression) لنظام:
- `service_orders`
- `service_order_items`
- مسار المزامنة عبر `rpc_process_sync_queue(jsonb)` + `_rpc_process_sync_queue_legacy(jsonb)`

### الهدف
ضمان أن أي تعديل لاحق على:
- RLS policies
- trigger `set_tenant_uuid_from_jwt()`
- mapping داخل الـ RPC (camelCase/snake_case)

لا يفتح ثغرة **عزل المستأجر** (Cross-tenant) أو يُنتج “نجاح زائف” في الـ RPC.

> كل اختبار هنا يستخدم `BEGIN … ROLLBACK` لمنع تلويث بيانات أي بيئة.

---

## قبل البدء

استبدل القيمتين:
- `UUID_A`
- `UUID_B`

بـ tenant_id حقيقيين لمستأجرين مختلفين في Supabase.

> تذكير: مشروعنا يقرأ tenant من:
> `auth.jwt() ->> 'tenant_id'`

---

## (1) اختبار RLS العزل (SELECT)

### جلسة tenant A
```sql
begin;

set local role = authenticated;
set local request.jwt.claims = '{"tenant_id":"UUID_A"}';

insert into public.service_orders (customer_name_snapshot, device_name, status)
values ('عميل A', 'Device A', 'pending');

select id, tenant_uuid, customer_name_snapshot, device_name, status
from public.service_orders
where deleted_at is null
order by created_at desc
limit 10;

rollback;
```

### جلسة tenant B (لا يرى بيانات A)
```sql
set local role = authenticated;
set local request.jwt.claims = '{"tenant_id":"UUID_B"}';

select id, tenant_uuid, customer_name_snapshot, device_name, status
from public.service_orders
where deleted_at is null
order by created_at desc
limit 20;
```

---

## (2) اختبار Trigger الختم (tenant_uuid من JWT)

```sql
begin;

set local role = authenticated;
set local request.jwt.claims = '{"tenant_id":"UUID_B"}';

with ins as (
  insert into public.service_orders (customer_name_snapshot, device_name, status)
  values ('عميل اختبار', 'iPhone Test', 'pending')
  returning id, tenant_uuid
)
select
  id,
  tenant_uuid,
  (tenant_uuid = (auth.jwt() ->> 'tenant_id')) as matches_jwt_tenant
from ins;

rollback;
```

**المتوقع:** `matches_jwt_tenant = true`

---

## (3) اختبار RPC mapping — Service Order (camelCase)

```sql
begin;

set local role = authenticated;
set local request.jwt.claims = '{"tenant_id":"UUID_B"}';

select public.rpc_process_sync_queue(
  jsonb_build_array(
    jsonb_build_object(
      '_mutation_id', gen_random_uuid()::text,
      '_entity_type', 'service_order',
      '_operation',   'INSERT',
      'id', gen_random_uuid()::text,
      'customerNameSnapshot', 'أحمد',
      'deviceName', 'iPhone',
      'status', 'pending',
      'estimatedPriceFils', 150000
    )
  )
) as rpc_results;

select id, tenant_uuid, customer_name_snapshot, device_name, estimated_price_fils
from public.service_orders
where tenant_uuid = (auth.jwt() ->> 'tenant_id')
order by created_at desc
limit 5;

rollback;
```

---

## (4) اختبار RPC mapping — Service Order (snake_case)

```sql
begin;

set local role = authenticated;
set local request.jwt.claims = '{"tenant_id":"UUID_B"}';

select public.rpc_process_sync_queue(
  jsonb_build_array(
    jsonb_build_object(
      '_mutation_id', gen_random_uuid()::text,
      '_entity_type', 'service_order',
      '_operation',   'INSERT',
      'id', gen_random_uuid()::text,
      'customer_name_snapshot', 'أحمد',
      'device_name', 'iPhone',
      'status', 'pending',
      'estimated_price_fils', 150000
    )
  )
) as rpc_results;

select id, tenant_uuid, customer_name_snapshot, device_name, estimated_price_fils
from public.service_orders
where tenant_uuid = (auth.jwt() ->> 'tenant_id')
order by created_at desc
limit 5;

rollback;
```

---

## (5) اختبار Cross-tenant عبر RPC — Service Order Item (camelCase)

> هذا الاختبار يفصل بين:
> - **رد الـ RPC**
> - **الحقيقة في DB**
>
> ويستخدم `COUNT(*)` لكشف “نجاح زائف”.

```sql
begin;

-- tenant A: أنشئ تذكرة واحصل على UUID لها
set local role = authenticated;
set local request.jwt.claims = '{"tenant_id":"UUID_A"}';

with a as (
  insert into public.service_orders (customer_name_snapshot, device_name, status)
  values ('عميل A', 'Device A', 'pending')
  returning id
)
select id as order_id_a from a;

-- tenant B: حاول إدراج بند على order_id_a عبر RPC (يجب أن يُمنع)
set local request.jwt.claims = '{"tenant_id":"UUID_B"}';

-- استبدل <UUID_A_order> بالقيمة التي خرجت من الاستعلام أعلاه
select public.rpc_process_sync_queue(
  jsonb_build_array(
    jsonb_build_object(
      '_mutation_id', gen_random_uuid()::text,
      '_entity_type', 'service_order_item',
      '_operation',   'INSERT',
      'id', gen_random_uuid()::text,
      'orderGlobalId', '<UUID_A_order>',
      'productId', 'P999',
      'productName', 'محاولة Cross-tenant',
      'quantity', 1,
      'priceFils', 1000,
      'totalFils', 1000
    )
  )
) as rpc_results;

select count(*) as should_be_zero
from public.service_order_items
where order_global_id = '<UUID_A_order>'::uuid
  and tenant_uuid = 'UUID_B';

rollback;
```

**المتوقع:** `should_be_zero = 0`

---

## (6) اختبار Cross-tenant عبر RPC — Service Order Item (snake_case)

```sql
begin;

-- tenant A: أنشئ تذكرة واحصل على UUID لها
set local role = authenticated;
set local request.jwt.claims = '{"tenant_id":"UUID_A"}';

with a as (
  insert into public.service_orders (customer_name_snapshot, device_name, status)
  values ('عميل A', 'Device A', 'pending')
  returning id
)
select id as order_id_a from a;

-- tenant B: نفس المحاولة لكن snake_case
set local request.jwt.claims = '{"tenant_id":"UUID_B"}';

-- استبدل <UUID_A_order> بالقيمة التي خرجت من الاستعلام أعلاه
select public.rpc_process_sync_queue(
  jsonb_build_array(
    jsonb_build_object(
      '_mutation_id', gen_random_uuid()::text,
      '_entity_type', 'service_order_item',
      '_operation',   'INSERT',
      'id', gen_random_uuid()::text,
      'order_global_id', '<UUID_A_order>',
      'product_id', 'P999',
      'product_name', 'محاولة Cross-tenant (snake_case)',
      'quantity', 1,
      'price_fils', 1000,
      'total_fils', 1000
    )
  )
) as rpc_results;

select count(*) as should_be_zero
from public.service_order_items
where order_global_id = '<UUID_A_order>'::uuid
  and tenant_uuid = 'UUID_B';

rollback;
```

**المتوقع:** `should_be_zero = 0`

