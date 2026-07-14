import 'package:intl/intl.dart' hide TextDirection;

import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import 'oil_change_filter_format.dart';

/// بناء نص رسالة واتساب بعد إتمام بطاقة غيار الزيت.
///
/// [priorOpenDebtFils]: دين مفتوح كان موجوداً قبل هذه الزيارة (تذكير للعميل).
/// المبلغ المدفوع يُقرأ من [advancePaymentFils] على البطاقة؛ الإجمالي من [agreedPriceFils].
String buildOilServiceWhatsAppMessage({
  required Map<String, dynamic> order,
  required String storeTitle,
  required String storeFooter,
  int priorOpenDebtFils = 0,
}) {
  final shop = storeTitle.trim().isEmpty ? 'المحل' : storeTitle.trim();
  final customer =
      (order['customerNameSnapshot'] ?? '').toString().trim().isEmpty
          ? 'عميلنا الكريم'
          : (order['customerNameSnapshot'] ?? '').toString().trim();

  final car = (order['deviceName'] ?? '').toString().trim();
  final model = (order['carModel'] ?? '').toString().trim();
  final plate = (order['deviceSerial'] ?? '').toString().trim();
  final odomCur = (order['odometerCurrent'] ?? '').toString().trim();
  final odomNext = (order['odometerNext'] ?? '').toString().trim();
  final oilType = (order['oilType'] ?? '').toString().trim();
  final viscosity = (order['oilViscosity'] ?? '').toString().trim();
  final size = (order['oilSize'] ?? '').toString().trim();
  final filterLines = oilFilterLinesFromRow(order);
  final tech = (order['technicianName'] ?? '').toString().trim();
  final notes = (order['issueDescription'] ?? '').toString().trim();

  final agreedF = (order['agreedPriceFils'] as num?)?.toInt();
  final estF = (order['estimatedPriceFils'] as num?)?.toInt() ?? 0;
  final totalF = agreedF ?? estF;
  final paidF = (order['advancePaymentFils'] as num?)?.toInt() ?? 0;
  final remainderF = totalF > 0 ? (totalF - paidF).clamp(0, totalF) : 0;
  const minMeaningfulFils = 500;

  String? fmtFils(int fils) {
    if (fils <= 0) return null;
    return IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
  }

  final created = DateTime.tryParse((order['createdAt'] ?? '').toString());
  final dateLine = created != null
      ? DateFormat('d/M/y', 'ar').format(created.toLocal())
      : null;

  final reqRaw = (order['requestedServices'] ?? '').toString().trim();
  final services = reqRaw.isEmpty
      ? <String>[]
      : reqRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  final buf = StringBuffer()
    ..writeln('مرحباً $customer،')
    ..writeln('شكراً لزيارتكم *$shop* لغيار الزيت 🙏')
    ..writeln();

  if (car.isNotEmpty || model.isNotEmpty) {
    final vehicle = [
      if (car.isNotEmpty) car,
      if (model.isNotEmpty) 'موديل $model',
    ].join(' — ');
    buf.writeln('🚗 *المركبة:* $vehicle');
  }
  if (plate.isNotEmpty) {
    buf.writeln('🔖 *اللوحة:* $plate');
  }
  if (odomCur.isNotEmpty) {
    buf.writeln('🔢 *قراءة العداد:* $odomCur كم');
  }
  if (odomNext.isNotEmpty) {
    buf.writeln('📅 *موعد الصيانة القادمة:* عند $odomNext كم');
  }
  buf.writeln();

  if (oilType.isNotEmpty || viscosity.isNotEmpty) {
    final oil = [
      if (oilType.isNotEmpty) oilType,
      if (viscosity.isNotEmpty) viscosity,
    ].join(' — ');
    buf.writeln('🛢️ *الزيت:* $oil');
  }
  if (size.isNotEmpty) {
    buf.writeln('📦 *الحجم:* $size');
  }
  if (filterLines.isNotEmpty) {
    buf.writeln('🔧 *الفلاتر:*');
    for (final line in filterLines) {
      buf.writeln('• $line');
    }
  }

  if (services.isNotEmpty) {
    buf.writeln();
    buf.writeln('✅ *خدمات إضافية:*');
    for (final s in services) {
      buf.writeln('• $s');
    }
  }

  buf.writeln();
  if (totalF > minMeaningfulFils) {
    final totalLine = fmtFils(totalF);
    final paidLine = paidF > minMeaningfulFils ? fmtFils(paidF) : null;
    final remLine = remainderF > minMeaningfulFils ? fmtFils(remainderF) : null;

    buf.writeln('💰 *ملخص الحساب (هذه الزيارة):*');
    if (totalLine != null) {
      buf.writeln('• *الإجمالي:* $totalLine');
    }
    if (paidLine != null) {
      buf.writeln('• *ما دفعته:* $paidLine');
    } else {
      buf.writeln('• *ما دفعته:* لم يُسجَّل دفع');
    }
    if (remLine != null) {
      if (paidF > minMeaningfulFils) {
        buf.writeln(
          '• *المتبقي عليك:* $remLine — دفعت أقل من الإجمالي، '
          'وهذا المبلغ يُسجَّل كدين على هذه الزيارة.',
        );
      } else {
        buf.writeln(
          '• *المتبقي عليك:* $remLine — لم يُسجَّل دفع، '
          'المبلغ كاملاً متبقٍ على هذه الزيارة.',
        );
      }
    } else if (paidF > minMeaningfulFils) {
      buf.writeln('• *الحالة:* تم دفع إجمالي هذه الزيارة بالكامل ✅');
    }
  }
  if (priorOpenDebtFils > minMeaningfulFils) {
    final priorLine = fmtFils(priorOpenDebtFils);
    if (priorLine != null) {
      buf.writeln();
      buf.writeln(
        '📌 *دين سابق على حسابك (قبل هذه الزيارة):* $priorLine',
      );
      if (remainderF > minMeaningfulFils) {
        final remLine = fmtFils(remainderF);
        final approx = fmtFils(remainderF + priorOpenDebtFils);
        if (remLine != null && approx != null) {
          buf.writeln(
            '• *تذكير:* متبقي هذه الزيارة $remLine + الدين السابق $priorLine '
            '≈ *$approx* إجمالاً تقريباً.',
          );
        }
      } else {
        buf.writeln(
          '• هذا المبلغ كان موجوداً قبل زيارتك اليوم (بالإضافة لحساب هذه الزيارة).',
        );
      }
    }
  }
  if (dateLine != null) {
    buf.writeln('📆 *التاريخ:* $dateLine');
  }
  if (tech.isNotEmpty) {
    buf.writeln('👨‍🔧 *الفني:* $tech');
  }
  if (notes.isNotEmpty) {
    buf.writeln('📝 *ملاحظات:* $notes');
  }

  final footer = storeFooter.trim();
  if (footer.isNotEmpty) {
    buf.writeln();
    buf.writeln(footer);
  } else {
    buf.writeln();
    buf.writeln('نراكم عند موعد الصيانة القادمة ✨');
  }

  return buf.toString().trim();
}
