-- المرحلة 0، البندان 0.5 و0.10: سحب صلاحية من لا يسجّل الدخول (anon) من دوال
-- لا يحتاجها إلا الخادم أو المستخدم المسجّل. لا يُطبَّق إلا بموافقة المالك،
-- بين 6 و9 صباحاً بتوقيت بغداد.
--
-- الدراسة (10 نوفمبر 2026، قراءة فقط):
-- * الصلاحية تأتي لـ anon عبر PUBLIC، فيجب سحبها من PUBLIC أيضاً.
-- * دوال المطاعم الثلاث لا يستدعيها إلا restaurant-create-order (النسخة 39)
--   وrestaurant-auto-accept-tick، وكلاهما بمفتاح الخادم (adminClient = service_role).
--   اليوم يستطيع أي شخص دون حساب قبول أي طلب مطعم برقمه.
-- * rpc_process_sync_queue: التطبيق يستدعيها وهو مسجّل فقط، وفيها حارس يرفض
--   من لا حساب له. السحب يغلق الباب قبل الدالة. الدالتان legacy تُستدعيان من
--   داخلها فقط.
-- * increment_coupon_uses: لا مستدعي لها في التطبيق ولا لوحة الإدارة ولا تاريخ git.
--   اليوم يستطيع أي شخص رفع عداد استخدام أي كوبون.
-- * marketplace_enqueue_classification: التطبيق يستدعيها بعد التحقق من وجود مستخدم
--   (marketplace_catalog_sync_service.dart:66).
-- * app_login_method_hint: لا مستدعي لها في أي نسخة (git log -S). تكشف لأي شخص
--   هل البريد مسجّل وبأي طريقة.
-- * restaurant_order_invoice_matches_session: دالة مشغّل (trigger)، لا تتأثر بالسحب.

-------------------------------------------------------------------------------
-- (أ) دوال المطاعم: للخادم فقط.
-- الرجوع: grant execute on function ... to anon, authenticated;
revoke execute on function public.restaurant_claim_order_accepted(bigint) from public, anon, authenticated;
revoke execute on function public.restaurant_rate_limit_hit(text, integer, integer) from public, anon, authenticated;
revoke execute on function public.restaurant_reserve_ingredients(text, bigint, bigint, jsonb) from public, anon, authenticated;
grant execute on function public.restaurant_claim_order_accepted(bigint) to service_role;
grant execute on function public.restaurant_rate_limit_hit(text, integer, integer) to service_role;
grant execute on function public.restaurant_reserve_ingredients(text, bigint, bigint, jsonb) to service_role;

-------------------------------------------------------------------------------
-- (ب) طابور المزامنة: للمستخدم المسجّل فقط (كما يستدعيها التطبيق).
-- الرجوع: grant execute on function ... to anon;
revoke execute on function public.rpc_process_sync_queue(jsonb) from public, anon;
revoke execute on function public._rpc_process_sync_queue_legacy(jsonb) from public, anon;
revoke execute on function public._rpc_process_sync_queue_legacy_base(jsonb) from public, anon;
grant execute on function public.rpc_process_sync_queue(jsonb) to authenticated;
grant execute on function public._rpc_process_sync_queue_legacy(jsonb) to authenticated;
grant execute on function public._rpc_process_sync_queue_legacy_base(jsonb) to authenticated;

-------------------------------------------------------------------------------
-- (ج) البند 0.10.
-- الرجوع: grant execute on function ... to anon;
revoke execute on function public.increment_coupon_uses(text) from public, anon, authenticated;
grant execute on function public.increment_coupon_uses(text) to service_role;
revoke execute on function public.marketplace_enqueue_classification(text) from public, anon;
grant execute on function public.marketplace_enqueue_classification(text) to authenticated;
revoke execute on function public.app_login_method_hint(text) from public, anon, authenticated;
grant execute on function public.app_login_method_hint(text) to service_role;

-------------------------------------------------------------------------------
-- التحقق بعد التطبيق: يجب أن ترجع anon_exec = false للتسع كلها.
-- select p.proname, has_function_privilege('anon', p.oid, 'execute') anon_exec,
--        has_function_privilege('authenticated', p.oid, 'execute') auth_exec
--   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--  where n.nspname = 'public' and p.proname in (
--    'restaurant_claim_order_accepted','restaurant_rate_limit_hit',
--    'restaurant_reserve_ingredients','rpc_process_sync_queue',
--    '_rpc_process_sync_queue_legacy','_rpc_process_sync_queue_legacy_base',
--    'increment_coupon_uses','marketplace_enqueue_classification',
--    'app_login_method_hint');
