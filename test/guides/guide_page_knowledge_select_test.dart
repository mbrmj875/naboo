import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/guides/knowledge/car_wash_knowledge.dart';
import 'package:naboo/guides/knowledge/guide_page_knowledge.dart';
import 'package:naboo/guides/knowledge/inventory_product_knowledge.dart';
import 'package:naboo/guides/knowledge/oil_catalog_knowledge.dart';
import 'package:naboo/guides/knowledge/oil_settings_knowledge.dart';
import 'package:naboo/guides/knowledge/oil_technician_knowledge.dart';
import 'package:naboo/guides/knowledge/users_staff_knowledge.dart';
import 'package:naboo/navigation/content_navigation.dart';

/// تطبيع مطابق لمنطق `_normalize` داخل `GuidePageKnowledge` (غير مُصدَّر).
String _normalizeLikeSelect(String s) {
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

void main() {
  group('GuidePageKnowledge.select', () {
    test('select_shlon_product_on_home_returns_overview', () {
      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.home,
        question: 'شلون أضيف منتج؟',
      );
      expect(
        out,
        contains('إضافة منتج جديد في نابو — نظرة عامة'),
      );
      expect(
        out,
        isNot(
          contains(
            'غسيل السيارات في نابو (مرتبط بعمودي غيار الزيت على الرئيسية):',
          ),
        ),
      );
    });

    test('select_users_alkaha_returns_staff_pack', () {
      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.home,
        question: 'وين ألكه المستخدمين؟',
      );
      expect(
        out,
        contains('وحدة «المستخدمين» في نابو — دليل كامل:'),
      );
    });

    test('select_abdil_oil_matches_tech_without_route_settings', () {
      const question = 'أريد أبدّل الزيت';
      final normalized = _normalizeLikeSelect(question);
      expect(OilTechnicianKnowledge.matchSnippet(normalized), isNotNull);
      expect(
        OilSettingsKnowledge.matchSnippet(normalized),
        isNull,
        reason: 'السؤال خدمة فنية وليس إعدادات صريحة',
      );

      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.oilChangeHub,
        question: question,
      );
      expect(
        out,
        contains('دور المساعد كفني غيار زيت محترف في العراق:'),
      );
      expect(out, contains('نصائح فني محترف عند الرد:'));
      expect(out, isNot(contains('قراءة اللزوجة باختصار:')));
      expect(out, isNot(contains('معرفة إعدادات غيار الزيت')));
      expect(out, isNot(contains('صرف الزيت من المخزون')));
      expect(out.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
      expect(out, isNot(endsWith('…')));
    });

    test('select_explicit_oil_settings_keeps_settings_pack', () {
      const question = 'إعدادات صرف الزيت من المخزون';
      final normalized = _normalizeLikeSelect(question);
      expect(OilTechnicianKnowledge.matchSnippet(normalized), isNull);
      expect(OilSettingsKnowledge.matchSnippet(normalized), isNotNull);

      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.oilChangeHub,
        question: question,
      );
      expect(out, contains('معرفة إعدادات غيار الزيت'));
      expect(out, contains('صرف الزيت من المخزون'));
      expect(
        out,
        isNot(contains('دور المساعد كفني غيار زيت محترف في العراق:')),
      );
      expect(out.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
    });

    test('select_unsupported_on_unknown_route_is_empty', () {
      const question = 'شلون أفعّل البلوكتشين؟';
      final normalized = _normalizeLikeSelect(question);

      expect(OilTechnicianKnowledge.matchSnippet(normalized), isNull);
      expect(UsersStaffKnowledge.matchSnippet(normalized), isNull);
      expect(InventoryProductKnowledge.matchSnippet(normalized), isNull);
      expect(CarWashKnowledge.matchSnippet(normalized), isNull);

      final out = GuidePageKnowledge.select(
        routeId: 'unknown.route.xyz',
        question: question,
      );
      expect(out, isEmpty);
    });

    test('select_addProduct_shlon_uses_overview_without_detail_stack', () {
      const question = 'شلون أضيف منتج؟';
      final normalized = _normalizeLikeSelect(question);
      expect(
        InventoryProductKnowledge.matchSnippet(normalized)?.trim(),
        InventoryProductKnowledge.overviewPack.trim(),
      );

      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.addProduct,
        question: question,
      );
      expect(
        out,
        contains('إضافة منتج جديد في نابو — نظرة عامة'),
      );
      expect(out, contains('أين؟'));
      expect(
        out,
        isNot(contains('حقول بطاقة «بيانات المنتج»')),
        reason: 'لا تكديس identityPack مع السؤال العام',
      );
      expect(
        out,
        isNot(contains('أنواع المخزون الأساسي — الأربعة العملية')),
        reason: 'لا تكديس stockKindsPack مع السؤال العام',
      );
      expect(out.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
    });

    test('select_addProduct_oil_family_keeps_detail_packs', () {
      const question = 'شلون أضيف منتج زيت عائلة؟';
      final normalized = _normalizeLikeSelect(question);
      final inv = InventoryProductKnowledge.matchSnippet(normalized);
      expect(inv, isNotNull);
      expect(inv, isNot(InventoryProductKnowledge.overviewPack.trim()));
      expect(inv, contains('زيت — عائلة'));

      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.addProduct,
        question: question,
      );
      expect(out, contains('زيت — عائلة'));
      expect(out, contains('أنواع المخزون الأساسي'));
      expect(out.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
    });

    test('select_product_not_prefer_carwash', () {
      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.home,
        question: 'شلون أضيف منتج؟',
      );
      expect(
        out,
        isNot(
          contains(
            'غسيل السيارات في نابو (مرتبط بعمودي غيار الزيت على الرئيسية):',
          ),
        ),
      );
    });

    test('select_iraqi_product_synonyms_share_overview', () {
      final a = GuidePageKnowledge.select(
        routeId: AppContentRoutes.home,
        question: 'شلون أضيف منتج؟',
      );
      final b = GuidePageKnowledge.select(
        routeId: AppContentRoutes.home,
        question: 'كيف اضيف منتج',
      );
      const marker = 'إضافة منتج جديد في نابو — نظرة عامة';
      expect(a, contains(marker));
      expect(b, contains(marker));
    });

    test('select_oilChangeCreate_service_uses_matchSnippet_not_full_pack', () {
      const question = 'أريد أبدّل الزيت';
      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.oilChangeCreate,
        question: question,
      );
      expect(out.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
      expect(out, isNot(endsWith('…')));
      expect(out, contains('دور المساعد كفني غيار زيت محترف في العراق:'));
      expect(out, contains('نصائح فني محترف عند الرد:'));
      expect(out, contains('افتح جولة التطبيق إن طُلبت خطوات الشاشة.'));
      expect(out, isNot(contains('قراءة اللزوجة باختصار:')));
      expect(
        out,
        isNot(contains('اقتراحات عملية شائعة في العراق (إرشادية):')),
      );
    });

    test('select_oilChangeCreate_viscosity_and_interval_keep_sections', () {
      final visc = GuidePageKnowledge.select(
        routeId: AppContentRoutes.oilChangeCreate,
        question: 'شنو لزوجة الزيت المناسبة؟',
      );
      expect(visc.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
      expect(visc, isNot(endsWith('…')));
      expect(visc, contains('قراءة اللزوجة باختصار:'));
      expect(visc, contains('اقتراحات عملية شائعة في العراق (إرشادية):'));
      expect(visc, contains('مع التنبيه لمطابقة الموافقة.'));

      final interval = GuidePageKnowledge.select(
        routeId: AppContentRoutes.oilChangeCreate,
        question: 'متى أغيّر الزيت؟',
      );
      expect(interval.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
      expect(interval, isNot(endsWith('…')));
      expect(
        interval,
        contains('فترات الغيار التقريبية في العراق (ظروف قاسية):'),
      );
      expect(
        interval,
        contains('راجع فلتر الهواء إن كان مسدوداً من الغبار.'),
      );
    });

    test('select_oilChangeCreate_no_tech_match_uses_route_default', () {
      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.oilChangeCreate,
        question: 'شلون أفعّل البلوكتشين؟',
      );
      expect(out, contains('الشاشة: بطاقة غيار زيت'));
      expect(out, contains('كتالوجات غيار الزيت'));
      expect(
        out,
        isNot(contains('دور المساعد كفني غيار زيت محترف في العراق:')),
      );
    });

    test('select_addProduct_unmatched_keeps_split_default_packs', () {
      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.addProduct,
        question: 'شلون أفعّل البلوكتشين؟',
      );
      expect(out, isNotEmpty);
      expect(out.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
      expect(out, isNot(endsWith('…')));
      expect(out, contains('حقول بطاقة «بيانات المنتج»'));
      expect(out, contains('اسم المنتج (مهم إلزامي)'));
      expect(out, contains('أنواع المخزون الأساسي — الأربعة العملية'));
      expect(
        out,
        contains(
          'اختر النوع قبل ملء الكميات والأسعار لأن الحقول تتغيّر حسب الاختيار.',
        ),
      );
      expect(out, contains('بطاقة «التسعير»'));
      expect(
        out,
        contains(
          'لعائلات الزيت/الهيدروليك: لا تسعّر هنا — ضع الأسعار في جدول الدرجات/اللزوجات أعلاه.',
        ),
      );
      // ذيل الميزانية: inventoryPack يُسقط كاملاً لا مبتوراً
      expect(out, isNot(contains('بطاقة «إدارة المخزون»')));
    });

    test('select_oversized_single_pack_dropped_not_sliced', () {
      // السلسلة المدمجة ما زالت أطول من الحد؛ الحلقة لا تستخدم … للقصّ.
      final merged = [
        InventoryProductKnowledge.identityPack.trim(),
        InventoryProductKnowledge.stockKindsPack.trim(),
        InventoryProductKnowledge.pricingPack.trim(),
        InventoryProductKnowledge.inventoryPack.trim(),
      ].join('\n---\n');
      expect(merged.length, greaterThan(GuidePageKnowledge.maxChars));

      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.addProduct,
        question: 'شلون أفعّل البلوكتشين؟',
      );
      expect(out.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
      expect(out, isNot(endsWith('…')));
      // إسقاط مقطع كامل من الذيل (إدارة المخزون) وليس بتر عنوانه
      expect(out, isNot(contains('بطاقة «إدارة المخزون»')));
    });

    test('select_settings_priority_when_tech_also_matches', () {
      const question = 'تفعيل صرف الزيت والعداد وصل 150 ألف';
      final normalized = _normalizeLikeSelect(question);
      expect(OilTechnicianKnowledge.matchSnippet(normalized), isNotNull);
      expect(OilSettingsKnowledge.matchSnippet(normalized), isNotNull);

      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.oilChangeHub,
        question: question,
      );
      expect(out, contains('معرفة إعدادات غيار الزيت'));
      expect(out, contains('صرف الزيت من المخزون'));
      expect(
        out,
        isNot(contains('دور المساعد كفني غيار زيت محترف في العراق:')),
      );
    });

    test('select_odometer_question_keeps_tech_not_settings', () {
      const question = 'عندي عداد 120 ألف كم';
      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.oilChangeCreate,
        question: question,
      );
      expect(out, contains('دور المساعد كفني غيار زيت محترف في العراق:'));
      expect(out, isNot(contains('معرفة إعدادات غيار الزيت')));
      expect(out.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
      expect(out, isNot(endsWith('…')));
    });

    test('select_viscosity_keeps_tech_over_catalog_when_both_match', () {
      const question = 'شنو لزوجة الزيت المناسبة؟';
      final normalized = _normalizeLikeSelect(question);
      final tech = OilTechnicianKnowledge.matchSnippet(normalized);
      final catalog = OilCatalogKnowledge.matchSnippet(normalized);
      expect(tech, isNotNull);
      expect(catalog, isNotNull);

      final out = GuidePageKnowledge.select(
        routeId: AppContentRoutes.oilChangeCreate,
        question: question,
      );
      expect(out, contains('قراءة اللزوجة باختصار:'));
      expect(out, contains('اقتراحات عملية شائعة في العراق (إرشادية):'));
      expect(
        out,
        contains('حماية أسمك في الحر/المحركات المستهلكة).'),
      );
      expect(out, contains('مع التنبيه لمطابقة الموافقة.'));
      expect(out.length, lessThanOrEqualTo(GuidePageKnowledge.maxChars));
      expect(out, isNot(endsWith('…')));

      final joinedWouldExceed =
          '${tech!.trim()}\n---\n${catalog!.trim()}'.length >
              GuidePageKnowledge.maxChars;
      if (joinedWouldExceed) {
        expect(
          out,
          isNot(contains('كتالوجات غيار الزيت (أسعار البطاقة)')),
          reason: 'الكتالوج في الذيل يُسقَط عند تجاوز الميزانية',
        );
      }
    });
  });
}
