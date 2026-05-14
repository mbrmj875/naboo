## قائمة تحقق تطبيق Supabase — خدمات/صيانة (Service Orders)

### قبل التشغيل (Prerequisites)
- [ ] **تم تشغيل** `migrations/20260507_rls_tenant.sql` وتأكد وجود:
  - `public.app_current_tenant_id()`
  - `public.set_tenant_uuid_from_jwt()`
- [ ] **تم تشغيل** `migrations/20260508_rpc_per_mutation.sql` وتأكد وجود:
  - `public.rpc_process_sync_queue(jsonb)` (returns `jsonb`)
- [ ] **يوجد legacy base** قبل توسيع الـ RPC:
  - إما تشغيل `migrations/20260514_rpc_product_variants_sync.sql`
  - أو التأكد أن `public._rpc_process_sync_queue_legacy_base(jsonb)` موجودة بالفعل.

### التشغيل (Supabase Studio)
- [ ] افتح Supabase Studio → SQL Editor.
- [ ] الصق وشغّل الملف الموحد:
  - `migrations/20260516_service_orders_full_supabase.sql`

### بعد التشغيل (Verification)
- [ ] **وجود الجداول**:
  - `public.service_orders`
  - `public.service_order_items`
- [ ] **RLS مفعّل** على الجدولين + سياسات select/insert/update/delete موجودة.
- [ ] **Trigger موجود**:
  - `trg_service_orders_set_tenant`
  - `trg_service_order_items_set_tenant`
- [ ] **اختبار العزل (RLS)**:
  - سجّل دخول بحساب Tenant (A) ثم نفّذ `select * from service_orders limit 1;`
  - سجّل دخول بحساب Tenant (B) وتأكد أنك لا ترى سجلات Tenant (A).
- [ ] **اختبار RPC mapping**:
  - أرسل mutation `service_order` يستخدم مفاتيح camelCase (مثل `customerNameSnapshot`) وتأكد يمر.
  - أرسل mutation يستخدم snake_case (مثل `customer_name_snapshot`) وتأكد يمر أيضاً.

