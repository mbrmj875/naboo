import 'car_wash_knowledge.dart';
import 'home_knowledge.dart';
import 'inventory_product_knowledge.dart';
import 'oil_catalog_knowledge.dart';
import 'oil_global_settings_knowledge.dart';
import 'oil_services_knowledge.dart';
import 'oil_settings_knowledge.dart';
import 'oil_technician_knowledge.dart';
import 'users_staff_knowledge.dart';
import '../../navigation/content_navigation.dart';

/// يختار مقتطف معرفة ثابت قصير حسب المسار والسؤال (بدون بيانات حية).
abstract final class GuidePageKnowledge {
  static const maxChars = 2200;

  static String select({
    required String routeId,
    required String question,
  }) {
    final q = _normalize(question);
    final matched = <String>[];

    void add(String? s) {
      final t = s?.trim();
      if (t == null || t.isEmpty) return;
      if (matched.contains(t)) return;
      matched.add(t);
    }

    // نتائج المطابقة تُحفظ صراحةً لتوجيه إضافات المسار (بدون فحص عبارة عربية).
    final techHit = OilTechnicianKnowledge.matchSnippet(q);
    final inventoryHit = InventoryProductKnowledge.matchSnippet(q);
    final oilSettingsHit = OilSettingsKnowledge.matchSnippet(q);

    // إعدادات صريحة تتقدّم على حزمة الفني (تجنّب قصّ الإعدادات واصطدام مفاتيح مثل «عداد»⊂«اعدادات»).
    if (oilSettingsHit != null) {
      add(oilSettingsHit);
    } else {
      add(techHit);
    }
    add(UsersStaffKnowledge.matchSnippet(q));
    add(inventoryHit);
    add(CarWashKnowledge.matchSnippet(q));
    add(HomeKnowledge.matchSnippet(q));
    add(OilCatalogKnowledge.matchSnippet(q));
    add(OilServicesKnowledge.matchSnippet(q));
    add(OilGlobalSettingsKnowledge.matchSnippet(q));

    if (matched.isEmpty) {
      if (routeId == AppContentRoutes.addProduct) {
        // مقاطع مستقلة حتى يعمل إسقاط الذيل بدل حذف السلسلة المدمجة (~2344).
        add(InventoryProductKnowledge.identityPack);
        add(InventoryProductKnowledge.stockKindsPack);
        add(InventoryProductKnowledge.pricingPack);
        add(InventoryProductKnowledge.inventoryPack);
      } else {
        add(_routeDefault(routeId));
      }
    } else if (_isOilHubRoute(routeId)) {
      // مطابقة فني (بدون المرور بفرع الإعدادات أعلاه) → لا تكديس إعدادات المسار.
      if (techHit == null) {
        add(OilSettingsKnowledge.packSnippet());
      }
    } else if (routeId == AppContentRoutes.oilChangeServices) {
      add(OilServicesKnowledge.packSnippet);
    } else if (routeId == AppContentRoutes.home) {
      add(HomeKnowledge.packSnippet);
    } else if (routeId == AppContentRoutes.carWashCreate ||
        routeId == AppContentRoutes.carWashServices) {
      add(CarWashKnowledge.packSnippet);
    } else if (routeId == AppContentRoutes.users ||
        routeId == AppContentRoutes.userForm ||
        routeId == AppContentRoutes.staffShiftsWeek ||
        routeId == AppContentRoutes.employeeIdentity) {
      if (routeId == AppContentRoutes.userForm) {
        add(UsersStaffKnowledge.addFormPack);
      } else if (routeId == AppContentRoutes.staffShiftsWeek) {
        add(UsersStaffKnowledge.shiftsPack);
      } else if (routeId == AppContentRoutes.employeeIdentity) {
        add(UsersStaffKnowledge.identityPack);
      } else {
        add(UsersStaffKnowledge.packSnippet);
      }
    } else if (routeId == AppContentRoutes.addProduct ||
        routeId == AppContentRoutes.inventoryProducts) {
      add(InventoryProductKnowledge.overviewPack);
      if (routeId == AppContentRoutes.addProduct) {
        // إن أعاد matchSnippet الـ overview وحدها (سؤال عام): لا تكديس التفاصيل.
        // إن أعاد حزماً تفصيلية (عائلة زيت / نوع مخزون / …): هي أصلاً في matched.
        // إن لم يطابق المخزون وبقيت مطابقة أخرى على الشاشة: أضف تفصيلاً للمسار.
        final inv = inventoryHit?.trim();
        if (inv == null) {
          add(InventoryProductKnowledge.identityPack);
          add(InventoryProductKnowledge.stockKindsPack);
        }
      }
    }
    // oilChangeCreate: معرفة الفني عبر techHit = matchSnippet فقط (أقسام مميّزة ≤2200).
    // لا تُلحق packSnippet الكامل عند غياب المطابقة — عند matched فارغ يُستخدم _routeDefault.

    if (matched.isEmpty) {
      return _routeDefault(routeId) ?? '';
    }

    final packs = List<String>.from(matched);
    while (true) {
      if (packs.isEmpty) return '';
      final out = packs.join('\n---\n');
      if (out.length <= maxChars) return out;
      // أسقط من الذيل؛ المقطع المفرد الأطول من الحد يُحذف كاملاً (لا substring).
      packs.removeLast();
    }
  }

  static bool _isOilHubRoute(String routeId) =>
      routeId == AppContentRoutes.oilServicesLog ||
      routeId == AppContentRoutes.oilChangeHub;

  static String? _routeDefault(String routeId) {
    switch (routeId) {
      case AppContentRoutes.home:
        return '${HomeKnowledge.packSnippet}\n---\n${CarWashKnowledge.packSnippet}';
      case AppContentRoutes.ownerDashboard:
        return 'الشاشة: لوحة صاحب العمل — مؤشرات، اختصارات، وإدارة المستخدمين.\n'
            '${UsersStaffKnowledge.menuPack}\n---\n${UsersStaffKnowledge.packSnippet}';
      case AppContentRoutes.carWashCreate:
        return 'الشاشة: بطاقة غسيل سيارة — لوحة وعميل وأنواع الغسيل ثم حفظ وبيع.\n'
            '${CarWashKnowledge.packSnippet}';
      case AppContentRoutes.carWashServices:
        return 'الشاشة: أنواع الغسيل وأسعارها — كتالوج يُختار داخل بطاقة الغسيل.\n'
            '${CarWashKnowledge.packSnippet}';
      case AppContentRoutes.settingsDashboardLayout:
        return 'الشاشة: تخصيص الشاشة الرئيسية — إظهار/إخفاء الأقسام و«زر غسيل السيارات».\n'
            '${HomeKnowledge.packSnippet}\n---\n${CarWashKnowledge.packSnippet}';
      case AppContentRoutes.oilServicesLog:
      case AppContentRoutes.oilChangeHub:
        return 'الشاشة: سجل غيارات الزيت. منها بطاقة جديدة، المعلّقة، ربط واتساب، وإعدادات غيار الزيت. '
            'ومن القائمة الفرعية: «أنواع الغسيل وأسعارها».\n'
            '${OilSettingsKnowledge.packSnippet()}';
      case AppContentRoutes.oilChangeCreate:
        return 'الشاشة: بطاقة غيار زيت. سجّل العميل واللوحة والزيت والدفع ثم حفظ وبيع. '
            'كتالوجات الأسعار من أزرار الإضافة بجانب الحقول. '
            '${OilCatalogKnowledge.packSnippet}';
      case AppContentRoutes.oilChangeServices:
        return OilServicesKnowledge.packSnippet;
      case AppContentRoutes.oilWhatsappConnect:
        return 'الشاشة: ربط واتساب المحل — ثلاث طرق (رقم نابو / Meta / QR) مع إعادة وفصل الربط.';
      case AppContentRoutes.settings:
        return OilGlobalSettingsKnowledge.packSnippet;
      case AppContentRoutes.users:
        return '${UsersStaffKnowledge.menuPack}\n---\n${UsersStaffKnowledge.packSnippet}';
      case AppContentRoutes.userForm:
        return UsersStaffKnowledge.addFormPack;
      case AppContentRoutes.staffShiftsWeek:
        return UsersStaffKnowledge.shiftsPack;
      case AppContentRoutes.employeeIdentity:
        return UsersStaffKnowledge.identityPack;
      case AppContentRoutes.inventoryProducts:
        return InventoryProductKnowledge.overviewPack;
      case AppContentRoutes.addProduct:
        return '${InventoryProductKnowledge.identityPack}\n---\n${InventoryProductKnowledge.stockKindsPack}\n---\n${InventoryProductKnowledge.pricingPack}\n---\n${InventoryProductKnowledge.inventoryPack}';
      default:
        if (routeId.startsWith(AppContentRoutes.oilChangeEditPrefix)) {
          return 'الشاشة: تعديل بطاقة غيار زيت موجودة.';
        }
        return null;
    }
  }

  static String _normalize(String s) {
    return s
        .trim()
        .toLowerCase()
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ');
  }
}
