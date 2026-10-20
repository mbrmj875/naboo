import 'app_assistant_scope.dart';
import 'guide_controller.dart';
import 'guide_tour.dart';

/// يحلّ المتابعات من ذاكرة المحادثة (افتح لي / نعم / وين الزر)
/// حتى لا يعتمد المستخدم على الاقتراحات الجاهزة وحدها.
class GuideChatFollowUp {
  const GuideChatFollowUp._();

  /// عبارات تأكيد أو طلب فتح الإرشاد على الشاشة.
  static bool looksLikeTourAffirmation(String raw) {
    final q = _normalize(raw);
    if (q.isEmpty || q.length > 90) return false;

    const phrases = <String>[
      'افتح لي',
      'افتحه',
      'افتحها',
      'افتحه لي',
      'افتحها لي',
      'افتح',
      'افتح جوله',
      'افتح لي جوله',
      'افتح الجوله',
      'افتح لي الجوله',
      'افتح ارشاد',
      'افتح الارشاد',
      'افتح لي ارشاد',
      'افتح لي الارشاد',
      'افتح الارشاد لي',
      'ابدأ الجوله',
      'ابدا الجوله',
      'ابدأ الارشاد',
      'ابدا الارشاد',
      'ابدأ',
      'ابدا',
      'يلا افتح',
      'يلا الجوله',
      'يلا الارشاد',
      'يلا ابدأ',
      'خطوة بخطوه',
      'اشرح خطوة',
      'اشرحلي خطوة',
      'اشرح لي خطوة',
      'ارشدني',
      'امشي وياي',
      'امشي معي',
      'هل يمكنك مساعدتي',
      'يمكنك مساعدتي',
      'ممكن تساعدني',
      'ساعدني',
      'ساعديني',
      'اي افتح',
      'نعم افتح',
      'اي اشرح',
      'نعم اشرح',
      'اي',
      'ايي',
      'ايوه',
      'ايوة',
      'نعم',
      'اه',
      'اوك',
      'اوكي',
      'تمام',
      'يلا',
      'تفضل',
      'هسه',
      'هسة',
      'اكيد',
      'موافق',
    ];

    for (final p in phrases) {
      if (q == p ||
          q.startsWith('$p ') ||
          q.endsWith(' $p') ||
          q.contains(' $p ')) {
        return true;
      }
    }
    if (q.contains('افتح') &&
        (q.contains('جوله') ||
            q.contains('ارشاد') ||
            q == 'افتح لي' ||
            q.startsWith('افتح لي'))) {
      return true;
    }
    if (q.contains('ابدأ') || q.contains('ابدا')) {
      if (q.contains('جوله') ||
          q.contains('ارشاد') ||
          q.length <= 12) {
        return true;
      }
    }
    return false;
  }

  /// أسئلة عن زر الإرشاد الذي ذكره المساعد للتو.
  static bool looksLikeWhereIsGuideButton(String raw) {
    final q = _normalize(raw);
    if (q.isEmpty || q.length > 80) return false;
    final asksWhere = q.contains('وين') ||
        q.contains('اين') ||
        q.contains('فين') ||
        q.contains('مكان') ||
        q.contains('شلون الاقي') ||
        q.contains('وينه') ||
        q.contains('وينها');
    final aboutButton = q.contains('زر') ||
        q.contains('الزر') ||
        q.contains('ارشاد') ||
        q.contains('جوله') ||
        q.contains('بدء');
    if (asksWhere && aboutButton) return true;
    if (q == 'اين هو زر' ||
        q == 'وين الزر' ||
        q == 'وين زر' ||
        q == 'اين الزر' ||
        q == 'وينه الزر' ||
        q == 'وين زر الارشاد' ||
        q == 'اين زر الارشاد') {
      return true;
    }
    return false;
  }

  static bool looksLikeMetaAboutReply(String raw) {
    final q = _normalize(raw);
    if (q.isEmpty || q.length > 100) return false;
    return q.contains('ليش') ||
        q.contains('لماذا') ||
        q.contains('قصدك') ||
        q.contains('شنو تقصد') ||
        q.contains('ما فهمت') ||
        q.contains('وضح') ||
        q.contains('وضّح') ||
        (q.contains('زر') && (q.contains('وين') || q.contains('اين')));
  }

  /// هل عرض المساعد جولة / شرح خطوة بخطوة / زر إرشاد؟
  static bool assistantOfferedTour(
    List<({bool fromUser, String text})> history,
  ) {
    var assistantSeen = 0;
    for (var i = history.length - 1; i >= 0 && assistantSeen < 5; i--) {
      final t = history[i];
      if (t.fromUser) continue;
      assistantSeen++;
      final n = _normalize(t.text);
      if (n.contains('جوله') ||
          n.contains('ارشاد') ||
          n.contains('خطوة بخطوه') ||
          n.contains('قلي وافتح') ||
          n.contains('قلي وانا افتح') ||
          (n.contains('قل لي') && n.contains('افتح')) ||
          n.contains('تبي اشرح') ||
          n.contains('افتح لك') ||
          n.contains('اضغط على زر') ||
          n.contains('زر الارشاد') ||
          n.contains('بدء الارشاد') ||
          (n.contains('هل تريد') && n.contains('خطوة'))) {
        return true;
      }
    }
    return false;
  }

  /// يستنتج أفضل tour_id من سياق المحادثة الأخيرة.
  static String? inferTourIdFromHistory(
    List<({bool fromUser, String text})> history,
  ) {
    final blob = history
        .map((t) => _normalize(t.text))
        .where((t) => t.isNotEmpty)
        .toList()
        .reversed
        .take(10)
        .join(' ');

    if (blob.isEmpty) return null;

    if (_any(blob, [
      'هيدروليك عائله',
      'هيدروليك عائلة',
      'عائله هيدروليك',
      'عائلة هيدروليك',
    ])) {
      return GuideTourIds.productStockHydraulic;
    }
    if (_any(blob, [
      'زيت عائله',
      'زيت عائلة',
      'عائله زيت',
      'عائلة زيت',
      'لزوجات',
    ])) {
      return GuideTourIds.productStockOil;
    }
    if (_any(blob, [
      'منتج بالعدد',
      'مخزون عدد',
      'بالقطعه',
      'بالقطعة',
      'نوع عدد',
    ])) {
      return GuideTourIds.productStockCount;
    }
    if (_any(blob, [
      'منتج بالحجم',
      'حجم لتر',
      'منتج باللتر',
      'وحدات اضافيه',
      'وحدات إضافية',
    ])) {
      return GuideTourIds.productStockVolume;
    }
    if (_any(blob, [
          'تسعير',
          'تنبيه النفاد',
          'تتبع المخزون',
          'اداره المخزون',
          'إدارة المخزون',
        ]) &&
        _any(blob, ['منتج', 'بضاعه', 'بضاعة', 'مخزون'])) {
      return GuideTourIds.productPricingInventory;
    }
    if (_any(blob, [
      'اضيف منتج',
      'أضيف منتج',
      'اضافه منتج',
      'إضافة منتج',
      'منتج جديد',
      'اضيف بضاعه',
      'أضيف بضاعة',
      'كيف اضيف منتج',
      'شلون اضيف',
      'قائمه المنتجات',
      'قائمة المنتجات',
      'نوع المخزون',
      'زر الاضافه',
      'زر الإضافة',
      'اضافه منتج جديد',
    ])) {
      return GuideTourIds.productAddOverview;
    }

    if (_any(blob, ['واتساب', 'واتس', 'whatsapp', 'ربط واتساب', 'فصل واتساب'])) {
      return GuideTourIds.oilWhatsapp;
    }
    if (_any(blob, ['غسيل', 'غسل سياره', 'غسل سيارة'])) {
      return GuideTourIds.carWashCreate;
    }
    if (_any(blob, [
      'مستخدم جديد',
      'اضيف موظف',
      'أضيف موظف',
      'اضافه موظف',
      'إضافة موظف',
      'pin',
    ])) {
      return GuideTourIds.usersAddStaff;
    }
    if (_any(blob, ['هويه', 'هوية', 'باركود موظف', 'رمز الورديه'])) {
      return GuideTourIds.usersIdentity;
    }
    if (_any(blob, ['ورديه', 'وردية', 'حضور'])) {
      return GuideTourIds.usersShifts;
    }
    if (_any(blob, ['المستخدمين', 'الموظفين', 'اداره المستخدمين'])) {
      return GuideTourIds.usersModuleOverview;
    }
    if (_any(blob, ['معلقه', 'معلّقة', 'فواتير معلقه'])) {
      return GuideTourIds.oilPendingTab;
    }
    if (_any(blob, [
      'غيار زيت',
      'تسجيل غيار',
      'بطاقه جديده',
      'بطاقة جديدة',
      'كيف اسجل',
    ])) {
      return GuideTourIds.oilFirstRun;
    }

    return null;
  }

  /// متابعة تأكيد / وين الزر / افتح لي.
  static GuideAssistResult? tryResolve({
    required String question,
    required List<({bool fromUser, String text})> history,
    required AppAssistantScope scope,
  }) {
    if (history.isEmpty) return null;

    final whereButton = looksLikeWhereIsGuideButton(question);
    final affirmation = looksLikeTourAffirmation(question);
    if (!whereButton && !affirmation) return null;

    final offered = assistantOfferedTour(history);
    final q = _normalize(question);
    final explicitOpen = q.contains('افتح') ||
        q.contains('ابدأ') ||
        q.contains('ابدا') ||
        q.contains('ارشد') ||
        q.contains('خطوة') ||
        q == 'افتح لي' ||
        q.startsWith('افتح لي');

    if (!whereButton && !explicitOpen && !offered) return null;
    if (whereButton && !offered && !explicitOpen) {
      // حتى لو ما ذُكرت كلمة جولة، آخر رد ذكر زراً
      final lastAssistant = _lastAssistantText(history);
      if (lastAssistant == null ||
          (!_normalize(lastAssistant).contains('زر') &&
              !_normalize(lastAssistant).contains('ارشاد'))) {
        return null;
      }
    }

    final inferred = inferTourIdFromHistory(history);
    if (inferred == null || inferred == GuideTourIds.none) {
      if (whereButton) {
        return const GuideAssistResult(
          reply:
              'الزر المقصود هو «ابدأ الإرشاد على الشاشة» يظهر تحت آخر رسالة مني داخل هذه المحادثة — مو في الشاشة الرئيسية. إن ما ظهر، معناها ما عندك صلاحية لهذه الجولة أو لازم تطلب فتح الإرشاد من جديد بجملة أوضح.',
          tourId: GuideTourIds.none,
          confidence: 1,
          source: 'followup',
        );
      }
      return null;
    }

    if (!scope.canStartTour(inferred)) {
      return GuideAssistResult(
        reply: whereButton
            ? 'ما في زر إرشاد على الشاشة لهالموضوع لأن صلاحيتك الحالية ما تسمح بفتح جولة المنتجات. '
                'تقدر تطلب من صاحب العمل صلاحية إدارة المنتجات، وأنا أشرح لك الخطوات بالنص من داخل المحادثة.'
            : 'فهمت إنك تريد الإرشاد على الشاشة، لكن جولة المنتجات خارج صلاحيتك الحالية. '
                'اطلب من صاحب العمل تفعيل صلاحية المنتجات، وأقدر أكمّل معك بالشرح النصي خطوة بخطوة.',
        tourId: GuideTourIds.none,
        confidence: 1,
        source: 'followup',
      );
    }

    return GuideAssistResult(
      reply: whereButton
          ? 'الزر تحت آخر رسالة داخل المحادثة: «ابدأ الإرشاد على الشاشة». راح أفتح لك الإرشاد هسه مباشرة.'
          : 'تمام — راح أفتح لك الإرشاد على الشاشة خطوة بخطوة الآن.',
      tourId: inferred,
      confidence: 1,
      source: 'followup',
    );
  }

  static String? _lastAssistantText(
    List<({bool fromUser, String text})> history,
  ) {
    for (var i = history.length - 1; i >= 0; i--) {
      if (!history[i].fromUser) return history[i].text;
    }
    return null;
  }

  static bool _any(String blob, List<String> keys) {
    for (final k in keys) {
      if (blob.contains(_normalize(k))) return true;
    }
    return false;
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
