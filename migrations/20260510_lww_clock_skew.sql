-- ============================================================================
-- Migration: 20260510_lww_clock_skew.sql
-- Step 19 — حارس Clock Skew لمنع هجوم LWW عبر "ساعة من المستقبل".
--
-- يُشغَّل يدوياً من Supabase Studio (SQL Editor) كـ superuser.
-- المتطلبات المسبقة:
--   - 20260507_rls_tenant.sql            (Step 11 — JWT + RLS)
--   - 20260508_rpc_per_mutation.sql      (Step 17 — per-mutation results)
--
-- 🎯 الخطر:
--   استراتيجية Last-Write-Wins تستخدم client timestamp للتحكيم بين النسخ
--   على عدّة أجهزة (`expenses.updated_at < EXCLUDED.updated_at`، إلى آخره).
--   عميل خبيث أو ساعة جهاز خاطئة يستطيع أن يكتب `updated_at = '9999-12-31'`
--   ⇒ أي تعديل لاحق من جهاز سليم لن يتفوّق عليه أبداً. نتيجةً: تجميد البيانات
--   الفعلية في كلّ المتاجر.
--
-- 🛡️ الحلّ:
--   فحص قبل تطبيق أيّ mutation: لو زعم العميل أنّ `updated_at` (أو ما يكافئها)
--   تتجاوز `now()` الخادم بمقدار >= 5 دقائق ⇒ نرفض العملية برسالة
--   `clock_skew_rejected`. الـ mutations الصحيحة (now ± 5min) تعمل بدون
--   احتكاك، والعميل المنحرف بسبب ساعة خاطئة قابلة للإصلاح يحصل على رسالة
--   واضحة.
--
-- 🔧 لماذا في wrapper Step 17 وليس داخل _rpc_process_sync_queue_legacy؟
--   نفس فلسفة Step 18 (audit triggers): نُبقي legacy كصندوق أسود.
--     1) wrapper Step 17 هو نقطة الدخول الموحَّدة لكلّ مزامنة RPC.
--     2) wrapper لديه فعلاً per-mutation BEGIN/EXCEPTION — مثالي لـ guard
--        يرمي فيُلتقط عنده تماماً.
--     3) الـ mutation المرفوضة لا تصل إلى legacy إطلاقاً ⇒ توفير عمل وعدم
--        تلويث transactional state.
--     4) لا حاجة لإعادة كتابة 350 سطر من legacy.
--     5) السلوك من ناحية العميل (Dart):
--        {status:'fail', error:'clock_skew_rejected: ...'} ⇒ Step 17 يضع
--        الصفّ في حالة failed ويزيد retry_count تلقائياً (defensive: العميل
--        قد يصلح ساعته ويعيد المحاولة لاحقاً).
--     6) `_reject_clock_skew(jsonb)` متاحة كـ helper لأي RPC مستقبلي أو
--        trigger كـ defense-in-depth.
--
-- 🔒 السرية الصارمة:
--   لا نقبل أي مصدر زمني آخر سوى `now()` الخادم. لا نقرأ من العميل وقتاً
--   نقارنه به. حتى المقارنة الحدّية تتمّ على الخادم فقط.
--
-- ⚠️ idempotent — يمكن تشغيله أكثر من مرة بأمان.
-- ============================================================================


-- ============================================================================
-- 1) المتطلب المسبق: rpc_process_sync_queue يجب أن تكون نسخة Step 17 (jsonb).
-- ============================================================================
do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_process_sync_queue'
      and pg_catalog.format_type(p.prorettype, null) = 'jsonb'
  ) then
    raise exception
      'Missing rpc_process_sync_queue(jsonb) returning jsonb. Run 20260508_rpc_per_mutation.sql first.'
      using errcode = 'P0001';
  end if;
end $$;


-- ============================================================================
-- 2) دالّة مساعِدة: _parse_client_ts(payload jsonb) -> timestamptz
--
--    تستخرج timestamptz من الـ mutation عبر مفاتيح متعدّدة (camelCase
--    و snake_case) المستخدَمة في الكيانات المختلفة. NULL إن لم تجد قيمة
--    صالحة. لا ترمي أبداً — الأخطاء الداخلية تُلتقط لتجنّب إفشال الـ RPC
--    بسبب payload مشوّه.
-- ============================================================================
create or replace function public._parse_client_ts(payload jsonb)
returns timestamptz
language plpgsql
immutable
as $$
declare
  v_str  text;
  v_ts   timestamptz;
  v_keys text[] := array[
    'updatedAt', 'updated_at',
    'createdAt', 'created_at',
    'occurredAt', 'occurred_at'
  ];
  k text;
begin
  if payload is null then
    return null;
  end if;

  foreach k in array v_keys loop
    v_str := payload ->> k;
    if v_str is null or v_str = '' then
      continue;
    end if;
    begin
      v_ts := v_str::timestamptz;
      return v_ts;
    exception when others then
      -- مدخل مشوّه — جرّب المفتاح التالي.
      continue;
    end;
  end loop;
  return null;
end;
$$;

comment on function public._parse_client_ts(jsonb) is
  'Step 19 — يستخرج timestamptz من mutation عبر مفاتيح متعدّدة. لا يرمي إطلاقاً.';


-- ============================================================================
-- 3) دالّة الحارس: _reject_clock_skew(payload jsonb)
--
--    ترمي clock_skew_rejected إن كان زمن العميل (المُستخرَج من الـ payload)
--    >= now() الخادم + 5 دقائق.
--
--    لماذا `>=` بدل `>`؟
--      الحدّ "5 دقائق بالضبط" يجب أن يُرفَض كي يبقى السلوك قطعياً (بدون
--      اعتماد على دقّة الميلي/الميكرو ثانية بين العميل والخادم). الاختبارات
--      تثبّت هذا: +5min بالضبط ⇒ مرفوض، +4m59s ⇒ مقبول.
--
--    لاحظ: `now()` تُقرأ مرتين تماماً من نفس الـ transaction (نفس القيمة).
--    لذلك المقارنة قطعية ولا تتأثر بتأخير الشبكة بين العميل والخادم.
-- ============================================================================
create or replace function public._reject_clock_skew(payload jsonb)
returns void
language plpgsql
as $$
declare
  v_client_ts timestamptz;
  v_server_now timestamptz;
  v_threshold timestamptz;
begin
  v_client_ts := public._parse_client_ts(payload);
  if v_client_ts is null then
    -- لا توجد timestamp قابل للقراءة ⇒ لا يمكن تحديد إن كان هناك انحراف.
    -- legacy سيطبّق سياسته الخاصّة (مثلاً تجاهل الـ mutation أو التعامل بـ
    -- updated_at = NULL). الحارس لا يتدخّل هنا.
    return;
  end if;

  v_server_now := now();
  v_threshold := v_server_now + interval '5 minutes';

  if v_client_ts >= v_threshold then
    raise exception
      'clock_skew_rejected: client timestamp % is >= server now()+5min (server now=%, threshold=%)',
      v_client_ts, v_server_now, v_threshold
      using errcode = 'P0001';
  end if;
end;
$$;

comment on function public._reject_clock_skew(jsonb) is
  'Step 19 — يرمي clock_skew_rejected إن ادّعى العميل زمناً >= now()+5min. '
  'يستعمل now() الخادم فقط — لا يثق بأي مصدر زمني خارجي.';


-- ============================================================================
-- 4) إعادة تعريف rpc_process_sync_queue من Step 17 مع إدراج الحارس
--    قبل التفويض إلى _legacy.
--
--    الفوارق عن Step 17:
--      - إضافة سطر `perform public._reject_clock_skew(mutation);` داخل
--        نفس BEGIN/EXCEPTION (الحارس يرمي ⇒ EXCEPTION when others يلتقط
--        ⇒ نتيجة `fail` بـ error = 'clock_skew_rejected: ...').
--      - تحديث comment ليعكس Step 19.
-- ============================================================================
create or replace function public.rpc_process_sync_queue(mutations_json jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_tenant_uuid text;
  mutation jsonb;
  v_claim text;
  v_mutation_id text;
  v_results jsonb := '[]'::jsonb;
  v_error text;
begin
  -- (أ) حارس JWT.
  v_tenant_uuid := public.app_current_tenant_id();
  if v_tenant_uuid is null or v_tenant_uuid = '' then
    raise exception 'tenant_unauthenticated: refusing sync without authenticated tenant'
      using errcode = 'P0001';
  end if;

  -- مصفوفة فارغة أو NULL ⇒ نُرجع [] فوراً.
  if mutations_json is null or jsonb_typeof(mutations_json) <> 'array' then
    return '[]'::jsonb;
  end if;

  -- (ب) فحص cross-tenant على كامل الباتش — أيّ تباين يُلغي الكلّ.
  for mutation in select * from jsonb_array_elements(mutations_json)
  loop
    v_claim := nullif(mutation->>'tenant_uuid', '');
    if v_claim is not null and v_claim is distinct from v_tenant_uuid then
      raise exception
        'tenant_mismatch: client claimed tenant_uuid=% but JWT yields %',
        v_claim, v_tenant_uuid
        using errcode = 'P0001';
    end if;
  end loop;

  -- (ج) معالجة لكلّ mutation: clock-skew guard ثم legacy.
  --     كلاهما داخل BEGIN/EXCEPTION ⇒ فشل أيّ منهما يصبح
  --     {status:'fail', error:<message>} في نتيجة هذا العنصر فقط.
  for mutation in select * from jsonb_array_elements(mutations_json)
  loop
    v_mutation_id := mutation->>'_mutation_id';

    begin
      -- Step 19: حارس clock-skew.
      perform public._reject_clock_skew(mutation);

      -- Step 17: تفويض فردي إلى legacy.
      perform public._rpc_process_sync_queue_legacy(jsonb_build_array(mutation));

      v_results := v_results || jsonb_build_object(
        'mutation_id', v_mutation_id,
        'status',      'ok',
        'error',       null
      );
    exception when others then
      v_error := SQLERRM;
      v_results := v_results || jsonb_build_object(
        'mutation_id', v_mutation_id,
        'status',      'fail',
        'error',       v_error
      );
    end;
  end loop;

  return v_results;
end;
$$;

comment on function public.rpc_process_sync_queue(jsonb) is
  'Step 19 — يضيف حارس clock-skew فوق Step 17 per-mutation results. '
  'يحتفظ بحرّاس JWT و cross-tenant. النتائج jsonb[]: '
  '{mutation_id, status, error}.';


-- ============================================================================
-- 5) فحص سريع (يطبع الإصدار النهائي لكي يُلاحَظ في log الـ SQL Editor).
-- ============================================================================
do $$
begin
  raise notice 'Step 19 applied. rpc_process_sync_queue now rejects mutations >= now()+5min as clock_skew_rejected.';
end $$;


-- =============================================================================
-- ROLLBACK (للاستعمال الطارئ — يعيد سلوك Step 17 بدون حارس clock-skew)
-- =============================================================================
-- ⚠️ يُلغي الحارس. لا تشغّل إلا عند الضرورة القصوى (مثلاً لو تبيّن أن منطق
--    التحكيم تغيّر أو تأكّد عدم وجود انحراف ساعات في كلّ الميدان).
--
-- 1) أعد تثبيت إصدار Step 17 لـ rpc_process_sync_queue:
--    (انسخ كتلة CREATE OR REPLACE من 20260508_rpc_per_mutation.sql.)
--
-- 2) (اختياري) أسقط الـ helpers:
--    drop function if exists public._reject_clock_skew(jsonb);
--    drop function if exists public._parse_client_ts(jsonb);
-- =============================================================================
-- نهاية الترحيل.
-- =============================================================================
