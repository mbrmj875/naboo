import '../verticals/oil_change/models/tenant_whatsapp_gateway_record.dart';
import '../verticals/oil_change/services/oil_change_whatsapp_gateway_repository.dart';
import '../verticals/oil_change/services/oil_change_whatsapp_messages_repository.dart';
import '../verticals/oil_change/services/oil_change_whatsapp_status_store.dart';
import '../utils/app_logger.dart';

/// يجمع حقائق واتساب الحية للمساعد (اتصال + عدّ رسائل حسب الفترة).
abstract final class GuideWhatsappOpsContext {
  /// هل السؤال عن تشغيل واتساب / الرسائل / الاتصال / فترة زمنية؟
  static bool looksLikeOpsQuestion(String question) {
    final q = _normalize(question);
    if (q.isEmpty) return false;

    const waHints = [
      'واتس',
      'واتساب',
      'whatsapp',
      'wa ',
      'الواتس',
      'الواتساب',
    ];
    const opsHints = [
      'رساله',
      'رسائل',
      'ارسال',
      'أرسل',
      'ارسل',
      'يرسل',
      'مايرسل',
      'ما يرسل',
      'مايوصل',
      'ما يوصل',
      'ماتوصل',
      'ما توصل',
      'اتصال',
      'متصل',
      'منفصل',
      'مفصول',
      'انقطع',
      'انقطاع',
      'ربط',
      'فصل',
      'مشكله',
      'مشكلة',
      'عطل',
      'خربان',
      'ما يشتغل',
      'ما يخدم',
      'شلون',
      'كم ',
      'اكد',
      'أكد',
      'فحص',
      'تشخيص',
      'اليوم',
      'هاليوم',
      'هسه',
      'امس',
      'أمس',
      'الشهر',
      'هالشهر',
      'اسبوع',
      'أسبوع',
      'فتره',
      'فترة',
      'من يوم',
      'الى يوم',
      'إلى يوم',
      'لمدة',
      'لمده',
    ];

    final hasWa = waHints.any(q.contains);
    final hasOps = opsHints.any(q.contains);
    if (hasWa && hasOps) return true;
    if (hasWa &&
        (q.contains('حال') ||
            q.contains('وضع') ||
            q.contains('شاكو') ||
            q.contains('شكو') ||
            q.contains('شلونك') ||
            q.contains('ليش') ||
            q.contains('ليش'))) {
      return true;
    }
    // «كم رسالة» بدون كلمة واتساب صريحة
    if ((q.contains('رساله') || q.contains('رسائل')) &&
        (q.contains('كم') ||
            q.contains('عدد') ||
            q.contains('اليوم') ||
            q.contains('الشهر') ||
            q.contains('هالشهر') ||
            q.contains('اسبوع') ||
            q.contains('أسبوع') ||
            q.contains('فتره') ||
            q.contains('فترة') ||
            q.contains('من '))) {
      return true;
    }
    return false;
  }

  /// يبني نص حقائق قصير يُرسل لـ Edge (بدون أسعار).
  static Future<String> buildFacts({
    required String question,
    List<String> recentUserQuestions = const [],
  }) async {
    final buf = StringBuffer();
    buf.writeln('=== حقائق واتساب حية (مصدر موثوق — لا تخترع أرقاماً غيرها) ===');
    buf.writeln('قاعدة: لا تذكر أسعار الرسائل أو التكلفة أبداً.');

    try {
      final cloud = OilChangeWhatsappGatewayRepository.instance.hasCloudSession
          ? await OilChangeWhatsappGatewayRepository.instance
              .fetchForCurrentUser()
          : null;
      final localStatus = await OilChangeWhatsappStatusStore.instance
          .readStatus(refreshFromServer: false);

      if (cloud != null) {
        buf.writeln(
          'الاتصال_سحابة: ${_statusAr(cloud.status)} | جاهزية: ${cloud.readyStateLabelAr}',
        );
        buf.writeln('المزوّد: ${_providerAr(cloud.provider)}');
        final phone = (cloud.whatsappPhone ?? '').trim();
        if (phone.isNotEmpty) {
          buf.writeln('رقم_الجلسة: $phone');
        }
        if (cloud.updatedAt != null) {
          buf.writeln(
            'آخر_تحديث_حالة: ${cloud.updatedAt!.toLocal().toIso8601String()}',
          );
        }
        buf.writeln(_diagnoseHint(cloud));
      } else {
        buf.writeln(
          'الاتصال_محلي: ${_localStatusAr(localStatus)} (لا سجل سحابي حالياً)',
        );
      }
    } catch (e) {
      AppLogger.warn('guide_wa_ops', 'status failed :: $e');
      buf.writeln('الاتصال: تعذّر جلب الحالة الآن');
    }

    final periods = _resolvePeriods(question, recentUserQuestions);
    if (periods.isNotEmpty) {
      buf.writeln('--- عدّ الرسائل (whatsapp_message_logs) ---');
      for (final p in periods) {
        try {
          final stats = await OilChangeWhatsappMessagesRepository.instance
              .countStats(
            fromInclusive: p.from,
            toExclusive: p.to,
          );
          buf.writeln(
            '${p.label}: إجمالي=${stats.total} | وصلت=${stats.deliveredOrRead} | أُرسلت=${stats.sent} | فشلت=${stats.failed} | أخرى=${stats.other}',
          );
        } catch (e) {
          AppLogger.warn('guide_wa_ops', 'count ${p.label} failed :: $e');
          buf.writeln('${p.label}: تعذّر العدّ');
        }
      }
    }

    buf.writeln(
      'إن طلب تشخيصاً: اشرح الحالة بالعربية العامية المفهومة، '
      'واقترح خطوات إصلاح داخل التطبيق (شاشة ربط واتساب / إعادة الربط / فحص الرقم) '
      'بدون أسعار وبدون طلب توكنات.',
    );
    return buf.toString().trim();
  }

  static String _diagnoseHint(TenantWhatsappGatewayRecord cloud) {
    if (cloud.readyState == WhatsappReadyState.ready && cloud.isConnected) {
      return 'تشخيص_مختصر: الجلسة متصلة وجاهزة للإرسال.';
    }
    if (cloud.readyState == WhatsappReadyState.preparing) {
      return 'تشخيص_مختصر: الخدمة تتجهز — انتظر قليلاً ثم أعد الفحص من شاشة الربط.';
    }
    if (cloud.isDisconnected ||
        cloud.readyState == WhatsappReadyState.disconnected) {
      return 'تشخيص_مختصر: غير متصل — افتح ربط واتساب وأعد الربط (رقم نابو / Meta / QR حسب طريقتك).';
    }
    if (cloud.status == TenantWhatsappGatewayStatus.connecting) {
      return 'تشخيص_مختصر: جاري الاتصال — أكمل المسح/التأكيد إن طُلب.';
    }
    return 'تشخيص_مختصر: الحالة غير مؤكدة — افتح شاشة ربط واتساب وحدّث الحالة.';
  }

  static String _statusAr(TenantWhatsappGatewayStatus s) {
    switch (s) {
      case TenantWhatsappGatewayStatus.connected:
        return 'متصل';
      case TenantWhatsappGatewayStatus.disconnected:
        return 'منفصل';
      case TenantWhatsappGatewayStatus.connecting:
        return 'جاري الاتصال';
      case TenantWhatsappGatewayStatus.unknown:
        return 'غير معروفة';
    }
  }

  static String _localStatusAr(OilChangeWhatsappGatewayStatus s) {
    switch (s) {
      case OilChangeWhatsappGatewayStatus.connected:
        return 'متصل';
      case OilChangeWhatsappGatewayStatus.disconnected:
        return 'منفصل';
      case OilChangeWhatsappGatewayStatus.unknown:
        return 'غير معروفة';
    }
  }

  static String _providerAr(TenantWhatsappProvider p) {
    switch (p) {
      case TenantWhatsappProvider.waha:
        return 'QR (WAHA)';
      case TenantWhatsappProvider.evolution:
        return 'QR (Evolution)';
      case TenantWhatsappProvider.cloudApi:
        return 'واتساب رسمي (Cloud API)';
      case TenantWhatsappProvider.whats360:
        return 'واتس360';
      case TenantWhatsappProvider.ycloud:
        return 'رسمي (Ycloud)';
      case TenantWhatsappProvider.dualhook:
        return 'رقم نابو الرسمي';
    }
  }

  static List<_Period> _resolvePeriods(
    String question,
    List<String> recentUserQuestions,
  ) {
    final blob = _normalize(
      [question, ...recentUserQuestions.take(3)].join(' '),
    );
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);
    final weekStart = todayStart.subtract(Duration(days: now.weekday % 7));
    // في العراق غالباً الأسبوع يُفهم كآخر 7 أيام عند السؤال العامي
    final last7Start = todayStart.subtract(const Duration(days: 6));
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final out = <_Period>[];
    void add(String label, DateTime from, DateTime to) {
      if (out.any((p) => p.label == label)) return;
      out.add(_Period(label: label, from: from, to: to));
    }

    final wantsToday = blob.contains('اليوم') ||
        blob.contains('هاليوم') ||
        blob.contains('هسه') ||
        blob.contains('هلحين');
    final wantsYesterday = blob.contains('امس') || blob.contains('أمس');
    final wantsWeek = blob.contains('اسبوع') ||
        blob.contains('أسبوع') ||
        blob.contains('هالاسبوع') ||
        blob.contains('هذا الاسبوع');
    final wantsThisMonth = blob.contains('هالشهر') ||
        blob.contains('هذا الشهر') ||
        blob.contains('الشهر الحالي') ||
        blob.contains('الشهر هذا') ||
        (blob.contains('الشهر') &&
            !blob.contains('ماضي') &&
            !blob.contains('الفائت'));
    final wantsLastMonth =
        blob.contains('الشهر الماضي') || blob.contains('الشهر الفائت');
    final wantsCount = blob.contains('كم') ||
        blob.contains('عدد') ||
        blob.contains('رساله') ||
        blob.contains('رسائل') ||
        blob.contains('ارسل') ||
        blob.contains('أرسل');

    final dayRange = _parseDayRangeInMonth(blob, now);
    if (dayRange != null) {
      add(dayRange.label, dayRange.from, dayRange.to);
    }

    if (wantsToday) {
      add('اليوم', todayStart, todayStart.add(const Duration(days: 1)));
    }
    if (wantsYesterday) {
      add('أمس', yesterdayStart, todayStart);
    }
    if (wantsWeek) {
      add('آخر_7_أيام', last7Start, todayStart.add(const Duration(days: 1)));
      add('من_بداية_الأسبوع', weekStart, todayStart.add(const Duration(days: 1)));
    }
    if (wantsThisMonth || (wantsCount && !wantsToday && dayRange == null)) {
      add('هذا_الشهر', monthStart, nextMonth);
    }
    if (wantsLastMonth) {
      final prevMonthStart = DateTime(now.year, now.month - 1, 1);
      add('الشهر_الماضي', prevMonthStart, monthStart);
    }

    // افتراضي عند سؤال اتصال/مشكلة فقط: اليوم + هذا الشهر كمرجع سريع
    if (out.isEmpty && looksLikeOpsQuestion(question)) {
      add('اليوم', todayStart, todayStart.add(const Duration(days: 1)));
      add('هذا_الشهر', monthStart, nextMonth);
    }

    return out;
  }

  /// «من يوم 1 الى يوم 13» أو «من 1 لـ 13 هذا الشهر»
  static _Period? _parseDayRangeInMonth(String blob, DateTime now) {
    final re = RegExp(
      r'(?:من\s*(?:يوم\s*)?)(\d{1,2})\s*(?:الى|إلى|لـ|ل|ـ)\s*(?:يوم\s*)?(\d{1,2})',
    );
    final m = re.firstMatch(blob);
    if (m == null) return null;
    final a = int.tryParse(m.group(1) ?? '');
    final b = int.tryParse(m.group(2) ?? '');
    if (a == null || b == null) return null;
    final startDay = a < b ? a : b;
    final endDay = a < b ? b : a;
    final lastDay = DateTime(now.year, now.month + 1, 0).day;
    if (startDay < 1 || endDay > lastDay) return null;
    final from = DateTime(now.year, now.month, startDay);
    final to = DateTime(now.year, now.month, endDay).add(const Duration(days: 1));
    return _Period(
      label: 'من_يوم_${startDay}_إلى_${endDay}_هذا_الشهر',
      from: from,
      to: to,
    );
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

class _Period {
  const _Period({
    required this.label,
    required this.from,
    required this.to,
  });

  final String label;
  final DateTime from;
  final DateTime to;
}
