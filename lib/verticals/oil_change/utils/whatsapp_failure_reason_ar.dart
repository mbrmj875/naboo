import 'dart:convert';

/// نتيجة تحليل سبب فشل رسالة واتساب للعرض في الواجهة.
class WhatsappFailureReason {
  const WhatsappFailureReason({
    required this.messageAr,
    required this.retryable,
    this.fixAr = '',
    this.source = '',
    this.code = '',
    this.sourceBadgeAr = '',
  });

  /// نص عربي للموظف — بلا رسالة Meta الخام الطويلة.
  final String messageAr;

  /// ماذا يفعل الموظف تحت الرسالة التي لم تُرسل.
  final String fixAr;

  /// من تصنيف الخادم (JSON) أو استنتاج محلي للـ outbox/legacy فقط.
  final bool retryable;

  final String source;
  final String code;

  /// شارة المصدر: معلّقة على الجهاز / فشل في خادم نابو / فشل من Meta
  final String sourceBadgeAr;
}

/// محلل موحّد لأسباب فشل واتساب (JSON منظم أو نص قديم أو رموز outbox).
abstract class WhatsappFailureReasonAr {
  WhatsappFailureReasonAr._();

  static const unknownAr = 'تعذّر الإرسال — سبب غير معروف من واتساب';

  static const paymentAr =
      'مشكلة دفع واتساب للأعمال عند ميتا — أصلح الدفع في Meta ثم أعد الإرسال';

  static WhatsappFailureReason parse(
    String? raw, {
    bool fromLocalOutbox = false,
  }) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) {
      final code = fromLocalOutbox ? 'no_internet' : 'unknown';
      return WhatsappFailureReason(
        messageAr: fromLocalOutbox
            ? 'لا يوجد اتصال بالإنترنت — لم تُرسل'
            : unknownAr,
        fixAr: _fixForCode(code, source: fromLocalOutbox ? 'device' : ''),
        retryable: fromLocalOutbox,
        source: fromLocalOutbox ? 'device' : '',
        code: fromLocalOutbox ? code : '',
        sourceBadgeAr: fromLocalOutbox ? 'معلّقة على الجهاز' : '',
      );
    }

    if (fromLocalOutbox || _looksLikeOutboxReason(text)) {
      return _fromOutboxOrLegacyCode(text, fromLocalOutbox: true);
    }

    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) {
          return _fromJsonMap(decoded);
        }
      } catch (_) {
        return WhatsappFailureReason(
          messageAr: unknownAr,
          fixAr: _fixForCode('unknown', source: ''),
          retryable: false,
        );
      }
      return WhatsappFailureReason(
        messageAr: unknownAr,
        fixAr: _fixForCode('unknown', source: ''),
        retryable: false,
      );
    }

    return _fromOutboxOrLegacyCode(text, fromLocalOutbox: false);
  }

  static bool _looksLikeOutboxReason(String text) {
    const known = {
      'noInternet',
      'timeout',
      'invalidPhone',
      'whatsappDisconnected',
      'evolutionError',
      'serverError',
      'unauthorized',
      'rateLimited',
      'insufficientWallet',
      'unknown',
    };
    return known.contains(text);
  }

  static WhatsappFailureReason _fromJsonMap(Map<dynamic, dynamic> map) {
    final source = (map['source'] ?? '').toString().trim().toLowerCase();
    final rawCode = (map['code'] ?? '').toString().trim();
    final title = (map['title'] ?? '').toString().trim();
    final message = (map['message'] ?? '').toString().trim();
    final code = normalizeFailureCode(
      rawCode,
      title: title,
      message: message,
    );
    // JSON صالح: اعتمد retryable من الخادم فقط — لا توسّع بالإعادة لكود مجهول.
    final hasRetryableKey = map.containsKey('retryable');
    final retryableStored = map['retryable'] == true;
    return WhatsappFailureReason(
      messageAr: _messageForCode(code, source: source, title: title),
      fixAr: _fixForCode(code, source: source),
      retryable: hasRetryableKey ? retryableStored : false,
      source: source,
      code: code,
      sourceBadgeAr: _badgeForSource(source),
    );
  }

  /// يوحّد أكواد ميتا/البوابة بما فيها الدفع 131042.
  static String normalizeFailureCode(
    String rawCode, {
    String title = '',
    String message = '',
  }) {
    final c = rawCode.trim().toLowerCase();
    final blob = '$c $title $message'.toLowerCase();

    if (blob.contains('131042') ||
        blob.contains('141006') ||
        blob.contains('141010') ||
        blob.contains('eligibility payment') ||
        blob.contains('payment issue') ||
        (blob.contains('payment') && blob.contains('eligib'))) {
      return '131042';
    }
    if (blob.contains('131026') || blob.contains('undeliverable')) {
      return '131026';
    }
    if (blob.contains('invalid_phone') || blob.contains('invalid phone')) {
      return 'invalid_phone';
    }
    if (c.isNotEmpty && c != 'unknown') return rawCode.trim();
    if (blob.contains('timeout')) return 'timeout';
    if (blob.contains('not_ready') || blob.contains('preparing')) {
      return 'preparing';
    }
    if (blob.contains('disconnect')) return 'disconnected';
    return c.isEmpty ? 'unknown' : rawCode.trim();
  }

  /// أخطاء يمكن إعادة المحاولة بعد إصلاح خارجي (دفع ميتا، مؤقت، …).
  /// أخطاء الرقم النهائي تبقى بلا زر إعادة بنفس الرقم.
  static bool isManuallyRetryableCode(String code) {
    final c = code.trim().toLowerCase();
    if (c == 'invalid_phone' || c == '131026') return false;
    return true;
  }

  static bool isPermanentPhoneFailure(String code) {
    final c = code.trim().toLowerCase();
    return c == 'invalid_phone' || c == '131026';
  }

  static bool isPaymentFailure(String code) {
    final c = code.trim().toLowerCase();
    return c == '131042' ||
        c == '141006' ||
        c == '141010' ||
        c == 'payment';
  }

  static WhatsappFailureReason _fromOutboxOrLegacyCode(
    String raw, {
    required bool fromLocalOutbox,
  }) {
    final lower = raw.toLowerCase();
    String code = normalizeFailureCode(raw, title: '', message: raw);
    if (code == raw || code == 'unknown') {
      if (lower.contains('invalid_phone') || raw == 'invalidPhone') {
        code = 'invalid_phone';
      } else if (raw == 'noInternet' || lower.contains('no_internet')) {
        code = 'no_internet';
      } else if (raw == 'timeout' || lower.contains('timeout')) {
        code = 'timeout';
      } else if (raw == 'whatsappDisconnected' ||
          lower.contains('disconnected') ||
          lower.contains('not_connected')) {
        code = 'disconnected';
      } else if (lower.contains('preparing') || lower.contains('not_ready')) {
        code = lower.contains('preparing') ? 'preparing' : 'not_ready';
      } else if (raw == 'insufficientWallet' || lower.contains('wallet')) {
        code = 'wallet_blocked';
      }
    }

    final source = fromLocalOutbox
        ? 'device'
        : (lower.contains('meta') ? 'meta' : 'gateway');
    return WhatsappFailureReason(
      messageAr: _messageForCode(code, source: source),
      fixAr: _fixForCode(code, source: source),
      retryable: fromLocalOutbox
          ? !isPermanentPhoneFailure(code) && !isPaymentFailure(code)
          : isManuallyRetryableCode(code),
      source: source,
      code: code,
      sourceBadgeAr: fromLocalOutbox
          ? 'معلّقة على الجهاز'
          : _badgeForSource(source),
    );
  }

  static String _badgeForSource(String source) {
    switch (source) {
      case 'meta':
        return 'فشل من Meta';
      case 'gateway':
        return 'فشل في خادم نابو';
      case 'device':
        return 'معلّقة على الجهاز';
      default:
        return '';
    }
  }

  static String _messageForCode(
    String code, {
    required String source,
    String title = '',
  }) {
    final c = code.trim().toLowerCase();
    if (c == 'no_internet' || c == 'nointernet') {
      return 'لا يوجد اتصال بالإنترنت — لم تُرسل';
    }
    if (c == 'timeout') return 'تعذّر الوصول لسيرفر الإرسال';
    if (c == 'gateway_unreachable') return 'تعذّر الوصول لسيرفر الإرسال';
    if (c == 'not_ready' || c == 'preparing') {
      return 'خدمة الرسائل قيد التجهيز';
    }
    if (c == 'disconnected' || c == 'not_connected') {
      return 'واتساب المحل غير مربوط';
    }
    if (c == 'invalid_phone' || c == 'invalidphone') {
      return 'رقم الزبون غير صالح — صحّح الرقم';
    }
    if (c == '131026' || c.contains('undeliverable')) {
      return 'الرقم غير موجود على واتساب أو لا يستقبل الرسائل';
    }
    if (isPaymentFailure(c)) {
      return paymentAr;
    }
    if (c == 'wallet_blocked' || c.contains('wallet')) {
      return 'رصيد الرسائل غير كافٍ أو انتهت فاتورة الباقة';
    }
    if (c == 'unauthorized') {
      return 'انتهت جلسة البرنامج أو فشل التحقق من الحساب';
    }
    if (c == 'rate_limit' || c == 'ratelimited') {
      return 'تم إرسال رسائل كثيرة — انتظر قليلاً';
    }
    if (c == 'evolutionerror' || c == 'evolution') {
      return 'تعذّر الإرسال من رقم المحل';
    }
    if (c == 'servererror' || c == 'server_error') {
      return 'سيرفر الإرسال رفض الطلب';
    }
    if (c == '131047') {
      return 'مرّ أكثر من يوم منذ آخر رسالة من الزبون، وواتساب رفض الرسالة الحرة';
    }
    if (c == '131048') {
      return 'واتساب أوقف الإرسال لأن معدل الرسائل يُعد مزعجاً';
    }
    if (c == '131049') {
      return 'ميتا حدّت رسائل التسويق لهذا الزبون مؤقتاً';
    }
    if (c == '131050') {
      return 'الزبون أوقف استقبال رسائل التسويق من هذا المحل';
    }
    if (c == '131031') {
      return 'حساب واتساب الأعمال مقفول عند ميتا';
    }
    if (c == '131037') {
      return 'اسم العرض على واتساب غير معتمد بعد';
    }
    if (c == '130429' || c == '80007' || c == '131056') {
      return 'تجاوزت حد الإرسال المسموح عند ميتا';
    }
    if (c == '132000' || c == '132001' || c == '132005' || c == '132012') {
      return 'قالب الرسالة غير مقبول عند ميتا';
    }
    if (c == '132015') {
      return 'ميتا أوقفت قالب الرسالة لأن جودته منخفضة';
    }
    if (c == '132016') {
      return 'ميتا عطّلت قالب الرسالة نهائياً';
    }
    if (c == '131021') {
      return 'لا يمكن إرسال الرسالة إلى رقم المحل نفسه';
    }
    if (c == '131000') {
      return 'خطأ مؤقت داخل سيرفرات ميتا';
    }
    if (c == '131008' || c == '131009') {
      return 'بيانات الرسالة المرسلة إلى ميتا ناقصة أو غير صالحة';
    }
    if (c.isEmpty || c == 'unknown') {
      final t = title.toLowerCase();
      if (t.contains('payment') || t.contains('eligib')) return paymentAr;
      return unknownAr;
    }
    // كود ميتا غير مجدول: أظهر الرمز للدعم بدل «غير معروف» فقط.
    if (source == 'meta' || RegExp(r'^\d{5,6}$').hasMatch(c)) {
      return 'رفضت Meta تسليم الرسالة (رمز $code)';
    }
    return unknownAr;
  }

  /// إجراء واحد يُعرض تحت الرسالة في «لم يتم الإرسال».
  static String _fixForCode(String code, {required String source}) {
    final c = code.trim().toLowerCase();
    if (c == 'no_internet' || c == 'nointernet') {
      return 'تأكد أن الجهاز متصل بالإنترنت، ثم اضغط «إعادة الإرسال».';
    }
    if (c == 'timeout' || c == 'gateway_unreachable') {
      return 'انتظر دقيقة ثم اضغط «إعادة الإرسال». إن تكرر، أعد تشغيل الشبكة.';
    }
    if (c == 'not_ready' || c == 'preparing') {
      return 'انتظر حتى يكتمل ربط واتساب، ثم اضغط «إعادة الإرسال».';
    }
    if (c == 'disconnected' ||
        c == 'not_connected' ||
        c == 'evolutionerror' ||
        c == 'evolution') {
      return 'من الإعدادات أعد ربط واتساب المحل بمسح رمز QR، ثم اضغط «إعادة الإرسال».';
    }
    if (c == 'invalid_phone' || c == 'invalidphone') {
      return 'افتح بطاقة الزبون وصحّح الرقم ليبدأ بـ 07 ومن 11 رقماً، ثم احفظ البطاقة من جديد.';
    }
    if (c == '131026' || c.contains('undeliverable')) {
      return 'اطلب من الزبون رقماً فيه واتساب ويستقبل الرسائل، ثم صحّحه في البطاقة.';
    }
    if (isPaymentFailure(c)) {
      return 'ادخل إلى Meta Business وأصلح طريقة الدفع أو حد الفاتورة، ثم اضغط «إعادة الإرسال».';
    }
    if (c == 'wallet_blocked' || c.contains('wallet')) {
      return 'عدد الرسائل المتبقي قليل أو فاتورة الباقة انتهت. جدّد الباقة من محفظة واتساب، ثم اضغط «إعادة الإرسال».';
    }
    if (c == 'unauthorized') {
      return 'اخرج من الحساب ثم سجّل الدخول من جديد، وبعدها اضغط «إعادة الإرسال».';
    }
    if (c == 'rate_limit' ||
        c == 'ratelimited' ||
        c == '130429' ||
        c == '80007' ||
        c == '131056') {
      return 'انتظر دقيقتين ولا ترسل عدة رسائل دفعة واحدة، ثم اضغط «إعادة الإرسال».';
    }
    if (c == '131047') {
      return 'انتظر حتى يرد الزبون، أو أرسل قالباً معتمداً بدل رسالة حرة.';
    }
    if (c == '131048' || c == '131049') {
      return 'لا تُعد الإرسال الآن. خفّف الرسائل وأعد المحاولة في وقت لاحق.';
    }
    if (c == '131050') {
      return 'لا ترسل لهذا الزبون رسالة تسويق حتى يطلب ذلك بنفسه.';
    }
    if (c == '131031') {
      return 'راجع حساب Meta Business. الإرسال يبقى متوقفاً حتى يُفتح الحساب.';
    }
    if (c == '131037') {
      return 'أكمل اعتماد اسم النشاط في Meta، ثم اضغط «إعادة الإرسال».';
    }
    if (c == '132015' || c == '132016' || c == '132000' || c == '132001' ||
        c == '132005' || c == '132012') {
      return 'القالب مرفوض عند ميتا. أبلغ دعم نابو برمز الخطأ، ولا تُعد نفس الرسالة كما هي.';
    }
    if (c == '131021') {
      return 'ضع رقم الزبون، لا رقم واتساب المحل نفسه.';
    }
    if (c == '131000' || c == 'servererror' || c == 'server_error') {
      return 'انتظر دقائق ثم اضغط «إعادة الإرسال». إن استمر، أبلغ دعم نابو.';
    }
    if (c == '131008' || c == '131009') {
      return 'أبلغ دعم نابو برمز الخطأ. البيانات المرسلة إلى ميتا تحتاج تصحيحاً.';
    }
    if (source == 'meta' || RegExp(r'^\d{5,6}$').hasMatch(c)) {
      return 'هذا رفض من سيرفرات Meta. انتظر دقائق ثم أعد الإرسال، أو أرسل رمز الخطأ لدعم نابو إن تكرر.';
    }
    return 'اضغط «إعادة الإرسال» مرة واحدة. إن بقيت الرسالة، اخرج من الحساب وادخل من جديد ثم أعد المحاولة.';
  }

  /// زر إعادة الإرسال للسجل السحابي (يدوي فقط — ليس تلقائياً).
  static bool cloudCanShowResend({
    required bool statusFailed,
    required bool hasContent,
    required String code,
    required bool retryableFromServer,
  }) {
    if (!statusFailed || !hasContent) return false;
    if (isPermanentPhoneFailure(code)) return false;
    // دفع ميتا: زر يدوي بعد إصلاح الحساب حتى لو retryable:false من الخادم.
    if (isPaymentFailure(code)) return true;
    // غير ذلك: التزم بتصنيف الخادم فقط.
    return retryableFromServer;
  }
}
