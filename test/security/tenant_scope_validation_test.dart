import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/tenant_context_service.dart';

void main() {
  group('ensureTenantScopeForQueries', () {
    final t1 = const TenantInfo(id: 1, code: 'a', name: 'أ', isActive: true);

    test('يرمي إذا لم يُحمّل السياق بعد', () {
      expect(
        () => ensureTenantScopeForQueries(
          loaded: false,
          tenants: [t1],
          activeTenantId: 1,
        ),
        throwsStateError,
      );
    });

    test('يرمي إذا قائمة المستأجرين فارغة', () {
      expect(
        () => ensureTenantScopeForQueries(
          loaded: true,
          tenants: const [],
          activeTenantId: 1,
        ),
        throwsStateError,
      );
    });

    test('يرمي إذا المعرّف النشط لا يطابق مستأجراً نشطاً', () {
      expect(
        () => ensureTenantScopeForQueries(
          loaded: true,
          tenants: [t1],
          activeTenantId: 99,
        ),
        throwsStateError,
      );
    });

    test('يرمي إذا المستأجر المحدد غير نشط', () {
      final inactive = const TenantInfo(
        id: 2,
        code: 'b',
        name: 'ب',
        isActive: false,
      );
      expect(
        () => ensureTenantScopeForQueries(
          loaded: true,
          tenants: [t1, inactive],
          activeTenantId: 2,
        ),
        throwsStateError,
      );
    });

    test('يعيد معرّف المستأجر عند صحة البيانات', () {
      expect(
        ensureTenantScopeForQueries(
          loaded: true,
          tenants: [t1],
          activeTenantId: 1,
        ),
        1,
      );
    });
  });
}
