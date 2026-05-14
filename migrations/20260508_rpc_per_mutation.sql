-- ============================================================================
-- Migration: 20260508_rpc_per_mutation.sql
-- Step 17 — نتائج لكل mutation داخل rpc_process_sync_queue.
--
-- يُشغَّل يدوياً من Supabase Studio (SQL editor) كـ superuser.
-- المتطلب المسبق: تنفيذ migrations/20260507_rls_tenant.sql أوّلاً (يُنشئ
-- _rpc_process_sync_queue_legacy و app_current_tenant_id()).
--
-- 🎯 لماذا التغيير؟
--   النسخة القديمة كانت ترجع void: إذا فشل أي mutation داخل الباتش، لم يعرف
--   العميل أيّها فشل، فكان يضع كامل الباتش في حالة failed ويزيد retry_count
--   لكلّ المتدفقات الناجحة. النتيجة: Mutations سليمة تتوقف بسبب جار مكسور.
--
-- 🔧 ماذا يفعل هذا التغيير؟
--   الواجهة الجديدة rpc_process_sync_queue(jsonb) ترجع jsonb (مصفوفة) بشكل:
--     [
--       {"mutation_id": "<uuid>", "status": "ok",   "error": null},
--       {"mutation_id": "<uuid>", "status": "fail", "error": "<message>"},
--       ...
--     ]
--   كل mutation تُمرَّر منفصلة إلى _rpc_process_sync_queue_legacy داخل
--   BEGIN ... EXCEPTION، فيُحصَر فشلها في عنصر واحد ولا يُلغي الباتش كله.
--
--   حُرّاس JWT والمستأجر من Step 11 يبقيان كما هما (يرفضان أي جلسة غير موثَّقة
--   أو mutation يدّعي tenant مختلف عن JWT — قبل أيّ معالجة).
--
-- ⚠️ هذا الملف idempotent — يمكن تشغيله أكثر من مرة بأمان.
-- ⚠️ تغيير نوع الإرجاع (void → jsonb) يستوجب DROP قبل CREATE في Postgres.
-- ============================================================================


-- ============================================================================
-- 0) تحقّق من وجود الدالة القديمة _rpc_process_sync_queue_legacy
--    إن لم تكن موجودة فهذا يعني أنّ Step 11 لم يُشغَّل — نوقف الترحيل بوضوح.
-- ============================================================================
do $$
begin
  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = '_rpc_process_sync_queue_legacy'
  ) then
    raise exception
      'Missing _rpc_process_sync_queue_legacy. Run 20260507_rls_tenant.sql first.'
      using errcode = 'P0001';
  end if;
end $$;


-- ============================================================================
-- 1) إسقاط الإصدار العمومي القديم (void) لأن نوع الإرجاع سيتغيّر إلى jsonb.
-- ============================================================================
drop function if exists public.rpc_process_sync_queue(jsonb);


-- ============================================================================
-- 2) الإصدار الجديد: نتائج لكل mutation
--
--    الترتيب:
--      أ) حارس JWT — رفض الجلسة غير الموثَّقة (يقطع كامل الاستدعاء).
--      ب) فحص cross-tenant — يرفض أيّ mutation يدّعي tenant مختلف عن JWT.
--      ج) معالجة لكل mutation — استدعاء _rpc_process_sync_queue_legacy
--         بـ array أحادي العنصر داخل BEGIN ... EXCEPTION لعزل الفشل.
--      د) إرجاع مصفوفة النتائج.
--
--    ⚠️ النقطتان (أ) و (ب) تُلقيان exception للمحافظة على نفس عقد Step 11
--       (لا نسمح بمزامنة بدون JWT أبداً، حتى ولو كانت mutation واحدة).
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

  -- إذا كانت المصفوفة فارغة أو NULL نُرجع [] فوراً.
  if mutations_json is null or jsonb_typeof(mutations_json) <> 'array' then
    return '[]'::jsonb;
  end if;

  -- (ب) فحص cross-tenant على كامل الباتش قبل البدء — أيّ تباين يلغي الكل.
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

  -- (ج) معالجة لكل mutation داخل BEGIN ... EXCEPTION (تحقيق per-mutation isolation).
  for mutation in select * from jsonb_array_elements(mutations_json)
  loop
    v_mutation_id := mutation->>'_mutation_id';

    begin
      -- استدعاء المنطق القديم على mutation واحدة (array أحادي العنصر).
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

  -- (د) إعادة المصفوفة. شكل كل عنصر:
  --     {"mutation_id": "...", "status": "ok"|"fail", "error": null|"<text>"}
  return v_results;
end;
$$;

comment on function public.rpc_process_sync_queue(jsonb) is
  'Step 17 — يعالج كل mutation منفصلة داخل blok BEGIN/EXCEPTION ويعيد '
  'jsonb[] بنتائج فردية {mutation_id, status, error}. يحتفظ بحرّاس JWT '
  'و cross-tenant من Step 11.';


-- =============================================================================
-- ROLLBACK (للاستعمال الطارئ فقط — يعيد سلوك Step 11)
-- =============================================================================
-- ⚠️ تنفيذ هذا القسم يُلغي per-mutation reporting ويعيد عقد void القديم.
--    العميل (Dart) مكتوب الآن ليتعامل مع List؛ ROLLBACK يجعله يفسّر null
--    على أنه "كل النتائج فشلت" ما لم يُتراجَع عن sync_queue_service.dart أيضاً.
--
-- drop function if exists public.rpc_process_sync_queue(jsonb);
--
-- create or replace function public.rpc_process_sync_queue(mutations_json jsonb)
-- returns void
-- language plpgsql
-- security definer
-- set search_path = public, auth
-- as $$
-- declare
--   v_tenant_uuid text;
--   mutation jsonb;
--   v_claim text;
-- begin
--   v_tenant_uuid := public.app_current_tenant_id();
--   if v_tenant_uuid is null or v_tenant_uuid = '' then
--     raise exception 'tenant_unauthenticated' using errcode = 'P0001';
--   end if;
--
--   for mutation in select * from jsonb_array_elements(mutations_json)
--   loop
--     v_claim := nullif(mutation->>'tenant_uuid', '');
--     if v_claim is not null and v_claim is distinct from v_tenant_uuid then
--       raise exception 'tenant_mismatch' using errcode = 'P0001';
--     end if;
--   end loop;
--
--   perform public._rpc_process_sync_queue_legacy(mutations_json);
-- end;
-- $$;
-- =============================================================================
-- نهاية الترحيل.
-- =============================================================================
