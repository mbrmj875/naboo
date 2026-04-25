---
name: security-supabase-flutter
description: Security-first rules for the Naboo / Basra Store Manager Flutter + Supabase multi-tenant SaaS — Supabase Row Level Security (RLS) as non-negotiable, tenant_id taken from the JWT (never from the client), RBAC with Permission/UserRole, IDOR prevention (always filter by tenant_id from session), parameterized sqflite queries, flutter_secure_storage for tokens, dart-define for keys, audit trail for financial operations, screen-capture protection (FLAG_SECURE) for sensitive screens, input validation, and forbidden practices (no service_role key in Flutter, no disabling RLS, no password/token logging, no raw SQL, no hard deletes for financial records). Use when touching auth, RLS policies, Supabase queries, permissions/roles, multi-tenant data access, secrets/API keys, token storage, sqflite queries with user input, sensitive screens (salaries/reports/payroll), audit logs, or any file under lib/**/*.dart that handles authentication, authorization, tenant isolation, or financial records. Use when the user asks about الأمان، RLS، tenant isolation، صلاحيات، IDOR، SQL injection، audit trail، flutter_secure_storage، أو dart-define.
---

# الأمان — الأولوية الأولى دائماً

## القاعدة الذهبية
فكّر بالأمان قبل كتابة أي سطر كود.
ERP يحتوي بيانات مالية وموظفين وعملاء — خرق واحد يدمر الثقة.

---

## أمان Supabase (أهم نقطة في مشروعك)

### Row Level Security — غير قابل للتفاوض
```sql
-- كل جدول يجب أن يكون RLS مفعّلاً
ALTER TABLE invoices  ENABLE ROW LEVEL SECURITY;
ALTER TABLE products  ENABLE ROW LEVEL SECURITY;
ALTER TABLE employees ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants   ENABLE ROW LEVEL SECURITY;

-- Policy: المستخدم يرى فقط بيانات منشأته
-- tenant_id يأتي من JWT — لا من الكلاينت
CREATE POLICY "tenant_isolation" ON invoices
  FOR ALL USING (
    tenant_id = (auth.jwt() -> 'app_metadata' ->> 'tenant_id')
  );

-- تحقق أن Policy تعمل:
-- SELECT * FROM invoices; -- يجب أن يُعيد فقط بيانات المنشأة الحالية
```

### لا تثق بـ tenant_id من الكلاينت
```dart
// ❌ خطأ قاتل — مستخدم يُرسل tenant_id آخر ويصل لبيانات منشأة غيره
await supabase.from('invoices').select().eq('tenant_id', userProvidedTenantId);

// ✅ صحيح — RLS يتولى العزل تلقائياً من الـ JWT
await supabase.from('invoices').select(); // RLS يُطبَّق تلقائياً
```

### أعمدة حساسة: لا يراها المستخدم العادي
```sql
-- في Supabase: لا تضع أعمداداً حساسة في views عامة
-- استخدم Functions مع SECURITY DEFINER للعمليات المميزة
CREATE OR REPLACE FUNCTION get_salary_report(p_tenant_id UUID)
RETURNS TABLE(...) SECURITY DEFINER AS $$
BEGIN
  -- تحقق من صلاحية المستخدم أولاً
  IF NOT check_permission(auth.uid(), 'view_salaries', p_tenant_id) THEN
    RAISE EXCEPTION 'غير مصرح';
  END IF;
  -- ...
END;
$$ LANGUAGE plpgsql;
```

---

## أمان Flutter

### لا أسرار في الكود
```dart
// ❌ خطأ — يُرى في APK بعد reverse engineering
const supabaseKey = 'eyJhbGci...';
const supabaseUrl = 'https://xxx.supabase.co';

// ✅ صحيح — dart-define عند البناء
// في pubspec.yaml أو build script:
// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
final supabaseUrl = const String.fromEnvironment('SUPABASE_URL');
final supabaseKey = const String.fromEnvironment('SUPABASE_ANON_KEY');
```

**ملاحظة:** المفتاح `anon` في Supabase عام بطبيعته — الحماية الحقيقية هي RLS + Auth.
أما مفاتيح `service_role` فلا تضعها في Flutter أبداً.

### تخزين التوكنز بأمان
```dart
// flutter_secure_storage — لا SharedPreferences للتوكنز
const storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  // Windows: يستخدم DPAPI تلقائياً
  // macOS: Keychain
);

// Supabase يدير الـ session تلقائياً عبر flutter_secure_storage
// تأكد من التهيئة الصحيحة:
await Supabase.initialize(
  url: supabaseUrl,
  anonKey: supabaseKey,
  authOptions: const FlutterAuthClientOptions(
    authFlowType: AuthFlowType.pkce, // أأمن من implicit
  ),
);
```

### التحقق من المدخلات
```dart
// lib/core/validators/app_validators.dart
class AppValidators {
  static String? required(String? v) =>
    (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

  static String? positiveAmount(String? v) {
    final n = double.tryParse(v?.replaceAll(',', '') ?? '');
    if (n == null || n <= 0) return 'أدخل مبلغاً صحيحاً';
    if (n > 1000000000)      return 'المبلغ كبير جداً';
    return null;
  }

  static String? noSqlInjection(String? v) {
    // sqflite يستخدم parameterized queries — هذا للطمأنينة الإضافية
    final dangerous = RegExp(r"[;'\"\\]|--|\b(DROP|DELETE|INSERT|UPDATE|SELECT)\b",
      caseSensitive: false);
    return dangerous.hasMatch(v ?? '') ? 'مدخل غير صالح' : null;
  }

  // لا تُظهر أخطاء تقنية للمستخدم
  static String friendlyError(Object error) {
    if (error is AuthException)      return 'انتهت جلستك، سجّل دخولك مجدداً';
    if (error.toString().contains('network')) return 'تحقق من اتصالك بالإنترنت';
    return 'حدث خطأ، حاول مجدداً'; // لا stack trace للمستخدم
  }
}
```

### حماية الشاشات الحساسة
```dart
// كشف الرواتب / الأرباح / البيانات السرية
@override
void initState() {
  super.initState();
  if (Platform.isAndroid) {
    FlutterWindowManager.addFlags(FlutterWindowManager.FLAG_SECURE);
  }
}
@override
void dispose() {
  if (Platform.isAndroid) {
    FlutterWindowManager.clearFlags(FlutterWindowManager.FLAG_SECURE);
  }
  super.dispose();
}
```

---

## RBAC — التحكم بالصلاحيات

```dart
// lib/core/auth/permissions.dart
enum Permission {
  viewInvoices, createInvoice, approveInvoice, voidInvoice,
  viewReports, exportData,
  viewSalaries, manageSalaries,
  manageUsers, manageSettings, manageSubscription,
}

enum UserRole { viewer, accountant, manager, admin, superAdmin }

const rolePermissions = <UserRole, Set<Permission>>{
  UserRole.viewer:     {Permission.viewInvoices, Permission.viewReports},
  UserRole.accountant: {Permission.viewInvoices, Permission.createInvoice, Permission.viewReports},
  UserRole.manager:    {Permission.viewInvoices, Permission.createInvoice,
                        Permission.approveInvoice, Permission.viewReports, Permission.exportData},
  UserRole.admin:      Permission.values.toSet(),
};

extension UserCan on AppUser {
  bool can(Permission p) => rolePermissions[role]?.contains(p) ?? false;
}
```

```dart
// في كل شاشة حساسة
if (!currentUser.can(Permission.viewSalaries)) {
  return const UnauthorizedWidget(); // لا تُخفي الشاشة — أظهر رسالة واضحة
}

// في كل عملية حساسة (الجانب الخلفي Supabase Function أيضاً)
if (!currentUser.can(Permission.approveInvoice)) {
  throw PermissionException('ليس لديك صلاحية اعتماد الفواتير');
}
```

---

## IDOR — المستخدم يصل لسجل منشأة أخرى

```dart
// ❌ خطأ — لا تثق بـ ID يأتي من أي مكان بدون تحقق
final invoice = await localDb.getById(invoiceId);

// ✅ صحيح — دائماً فلتر بـ tenantId
final invoice = await localDb.rawQuery(
  'SELECT * FROM invoices WHERE id = ? AND tenant_id = ? AND deleted_at IS NULL',
  [invoiceId, tenantContextService.currentTenantId], // tenantId من الـ session لا من params
);
if (invoice.isEmpty) throw NotFoundException('الفاتورة غير موجودة');
```

---

## SQLite — استعلامات آمنة

```dart
// ❌ خطر SQL Injection
final query = "SELECT * FROM invoices WHERE customer_name = '$userInput'";

// ✅ Parameterized queries دائماً
final results = await db.query(
  'invoices',
  where: 'customer_name = ? AND tenant_id = ?',
  whereArgs: [userInput.trim(), currentTenantId],
);
```

---

## Audit Trail — إلزامي للعمليات المالية

```dart
// بعد كل CREATE/UPDATE/DELETE على سجلات مالية
await auditDao.insert({
  'id':           Uuid().v4(),
  'tenant_id':    currentTenantId,
  'entity_type':  'invoice',
  'entity_id':    invoice.id,
  'action':       'approved',
  'performed_by': currentUser.id,
  'before_data':  jsonEncode(invoiceBefore.toMap()),
  'after_data':   jsonEncode(invoiceAfter.toMap()),
  'timestamp':    DateTime.now().millisecondsSinceEpoch,
});
```

---

## ما لا تفعله أبداً

- ❌ لا `service_role` key في Flutter — هذا المفتاح يتجاوز RLS كاملاً
- ❌ لا تُعطّل RLS حتى للتطوير — استخدم user مختلف للاختبار
- ❌ لا تُرسل كلمات مرور أو tokens في الـ logs
- ❌ لا تثق بـ tenant_id القادم من المستخدم — خذه من auth session
- ❌ لا raw SQL بمتغيرات مُدمجة — parameterized دائماً
- ❌ لا تحذف سجلات مالية — `deleted_at` (soft delete)
- ❌ لا تتحقق من الصلاحيات في الـ UI فقط — تحقق في الـ Supabase Functions أيضاً
