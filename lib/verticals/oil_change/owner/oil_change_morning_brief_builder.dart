import '../../../owner/models/owner_command_center_snapshot.dart';

/// سطر «ملخص الصباح» — يقرأ أقسام snapshot v3.
///
/// يعدّ كل عمليات محل الزيت (غيار + غسيل + بيع مباشر)، فلا يقول «لا نشاط»
/// والمبيعات ظاهرة في الشاشة نفسها.
abstract final class OilChangeMorningBriefBuilder {
  OilChangeMorningBriefBuilder._();

  static const emptyText = 'لا نشاط مسجّل بعد — اسحب للتحديث';
  static const loadingText = 'جارٍ حساب ملخص الفترة…';
  static const salesOnlyText =
      'توجد مبيعات في الفترة — التفاصيل في الأرقام أدناه';

  static String build(OwnerCommandCenterSnapshot snapshot) {
    final parts = <String>[];

    final ops = snapshot.oilChangesCount;
    final opsData = ops?.data;
    if (opsData != null) {
      if (opsData.oilOperationCount > 0) {
        parts.add('${opsData.oilOperationCount} غيار');
      }
      if (opsData.washCount > 0) {
        parts.add('${opsData.washCount} غسيل');
      }
      if (opsData.directSaleCount > 0) {
        parts.add('${opsData.directSaleCount} بيع مباشر');
      }
    }

    final active = snapshot.oilActiveCars?.data;
    if (active != null && active.activeCount > 0) {
      parts.add('${active.activeCount} سيارات بالانتظار');
    }

    final shortages = snapshot.oilStockShortages?.data;
    if (shortages != null && shortages.shortageCount > 0) {
      parts.add('${shortages.shortageCount} نواقص حرجة');
    }

    if (parts.isNotEmpty) return parts.join(' · ');

    // لا نقول «لا نشاط» قبل أن تكتمل قراءة العمليات.
    if (ops != null && !ops.hasData && ops.isLoading) {
      return loadingText;
    }

    // حماية أخيرة: مبيعات بلا عمليات معدودة (مثلاً فاتورة من نوع آخر).
    final salesFils = snapshot.sales.data?.salesFils ?? 0;
    if (salesFils > 0) return salesOnlyText;

    return emptyText;
  }
}
