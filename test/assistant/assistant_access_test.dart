import 'package:naboo/assistant/assistant_access.dart';
import 'package:naboo/services/app_remote_config_service.dart';
import 'package:naboo/services/permission_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('مستوى المساعد (ق48)', () {
    test('المالك دائماً كامل', () {
      expect(
        AssistantAccess.levelFor(isOwner: true, can: (_) => false),
        AssistantLevel.full,
      );
    });

    test('الموظف: المفتاحان كامل، الأول وحده إرشاد، لا شيء بلا مساعد', () {
      AssistantLevel lvl(Set<String> keys) =>
          AssistantAccess.levelFor(isOwner: false, can: keys.contains);
      expect(
        lvl({PermissionKeys.assistantGuide, PermissionKeys.assistantFull}),
        AssistantLevel.full,
      );
      expect(lvl({PermissionKeys.assistantGuide}), AssistantLevel.guideOnly);
      // «كامل» بلا «إرشاد» حالة غير صالحة تُعامل كبلا مساعد.
      expect(lvl({PermissionKeys.assistantFull}), AssistantLevel.none);
      expect(lvl({}), AssistantLevel.none);
    });

    test('applyLevel ثم levelFromMap يعيدان المستوى نفسه', () {
      for (final level in AssistantLevel.values) {
        final map = <String, bool>{};
        AssistantAccess.applyLevel(map, level);
        expect(AssistantAccess.levelFromMap(map), level);
      }
    });

    test('الافتراضي للموظف الجديد: كامل', () {
      final map = PermissionService.instance.defaultStaffPermissionMap();
      expect(AssistantAccess.levelFromMap(map), AssistantLevel.full);
    });

    test('مفاتيح المساعد لا تدخل حساب «كامل التخصيص»', () {
      expect(
        PermissionKeys.coreKeys.toSet().intersection(
          PermissionKeys.assistantKeys,
        ),
        isEmpty,
      );
      expect(
        PermissionKeys.allKeys.toSet().containsAll(
          PermissionKeys.assistantKeys,
        ),
        isTrue,
      );
    });
  });

  group('مفاتيح الإطلاق (م0-7)', () {
    test('بلا إعداد: مطفأ', () {
      final f = AssistantRemoteFlags.fromJson(null);
      expect(f.v2EnabledFor(tenantEnabled: true), isFalse);
    });

    test('tenants: للمحل المفعّل فقط', () {
      final f = AssistantRemoteFlags.fromJson({'v2_rollout': 'tenants'});
      expect(f.v2EnabledFor(tenantEnabled: true), isTrue);
      expect(f.v2EnabledFor(tenantEnabled: false), isFalse);
    });

    test('مفتاح الإيقاف يغلب كل شيء', () {
      final f = AssistantRemoteFlags.fromJson({
        'v2_rollout': 'all',
        'kill': true,
      });
      expect(f.v2EnabledFor(tenantEnabled: true), isFalse);
    });

    test('مفتاح قدرة مطفأ وحده', () {
      final f = AssistantRemoteFlags.fromJson({
        'v2_rollout': 'all',
        'caps': {'web': false},
      });
      expect(f.webEnabled, isFalse);
      expect(f.executeEnabled, isTrue);
      expect(f.imagesEnabled, isTrue);
    });

    test('قيمة إطلاق مجهولة تُعامل كمطفأ', () {
      final f = AssistantRemoteFlags.fromJson({'v2_rollout': 'everyone'});
      expect(f.rollout, 'off');
    });
  });
}
