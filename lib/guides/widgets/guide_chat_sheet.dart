import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/business_features_provider.dart';
import '../../providers/permissions_provider.dart';
import '../app_assistant_scope.dart';
import '../guide_ai_client.dart';
import '../guide_chat_followup.dart';
import '../guide_controller.dart';
import '../guide_feedback_client.dart';
import '../guide_tour.dart';

Future<void> showGuideChatSheet({
  required BuildContext context,
  required String currentRouteId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: GuideChatSheet(currentRouteId: currentRouteId),
      );
    },
  );
}

class GuideChatSheet extends StatefulWidget {
  const GuideChatSheet({super.key, required this.currentRouteId});

  final String currentRouteId;

  @override
  State<GuideChatSheet> createState() => _GuideChatSheetState();
}

class _GuideChatSheetState extends State<GuideChatSheet> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  final _ai = GuideAiClient();
  late final AppAssistantScope _scope;
  late final List<_ChatLine> _messages;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _scope = AppAssistantScope.fromProviders(
      auth: context.read<AuthProvider>(),
      permissions: context.read<PermissionsProvider>(),
      features: context.read<BusinessFeaturesProvider>(),
    );
    final saved = context.read<GuideController>().chatSession;
    if (saved.isNotEmpty) {
      _messages = [
        for (final t in saved)
          _ChatLine(
            fromUser: t.fromUser,
            text: t.text,
            rateable: !t.fromUser,
          ),
      ];
    } else {
      _messages = [
        _ChatLine(fromUser: false, text: _scope.welcomeMessage()),
      ];
    }
  }

  void _persistSession() {
    final guide = context.read<GuideController>();
    guide.replaceChatSession([
      for (final m in _messages)
        GuideChatTurn(fromUser: m.fromUser, text: m.text),
    ]);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _send(String raw, {String? forcedTourId}) async {
    final q = raw.trim();
    if (q.isEmpty || _loading) return;

    final historyBefore = _messages
        .where((m) => m.text.trim().isNotEmpty)
        .skip(_messages.isNotEmpty && !_messages.first.fromUser ? 1 : 0)
        .map((m) => GuideChatTurn(fromUser: m.fromUser, text: m.text))
        .toList();

    setState(() {
      _messages.add(_ChatLine(fromUser: true, text: q));
      _loading = true;
      _controller.clear();
    });
    _persistSession();
    _scrollToEnd();

    try {
      GuideAssistResult result;
      if (forcedTourId != null &&
          GuideTourIds.allowlist.contains(forcedTourId) &&
          forcedTourId != GuideTourIds.none) {
        if (!_scope.canStartTour(forcedTourId)) {
          result = const GuideAssistResult(
            reply:
                'هذه الخطوة خارج صلاحيتك الحالية. اطلب من صاحب العمل إن احتجت الوصول.',
            tourId: GuideTourIds.none,
            confidence: 1,
            source: 'rbac',
          );
        } else {
          result = GuideAssistResult(
            reply: _prepReplyForTour(forcedTourId),
            tourId: forcedTourId,
            confidence: 1,
            source: 'chip',
          );
        }
      } else {
        result = await _ai.assist(
          question: q,
          currentRouteId: widget.currentRouteId,
          scope: _scope,
          history: historyBefore,
        );
        if (result.tourId != GuideTourIds.none &&
            !_scope.canStartTour(result.tourId)) {
          result = GuideAssistResult(
            reply: result.reply.isEmpty
                ? 'فهمت السؤال، لكن هذه الجولة خارج صلاحيتك.'
                : '${result.reply}\n\nملاحظة: لا يمكن فتح الإرشاد العملي لأن صلاحيتك لا تسمح.',
            tourId: GuideTourIds.none,
            confidence: result.confidence,
            source: result.source,
          );
        } else if (result.tourId != GuideTourIds.none &&
            _scope.canStartTour(result.tourId) &&
            !_replyMentionsGuide(result.reply)) {
          // أبقِ نص النموذج مرتباً وأضف تلميحاً قصيراً فوق زر البدء
          result = GuideAssistResult(
            reply: result.reply.trim(),
            tourId: result.tourId,
            confidence: result.confidence,
            source: result.source,
          );
        }
      }

      if (!mounted) return;
      final offerTour = result.tourId != GuideTourIds.none &&
          _scope.canStartTour(result.tourId);
      final line = _ChatLine(
        fromUser: false,
        text: result.reply,
        rateable: true,
        questionForFeedback: q,
        source: result.source,
        tourId: offerTour ? result.tourId : null,
      );
      setState(() {
        _messages.add(line);
        _loading = false;
      });
      _persistSession();
      context.read<GuideController>().setLastChatReply(result.reply);
      _scrollToEnd();

      // طلب صريح لفتح الجولة / متابعة بعد عرضها → ابدأ فوراً بدون تكرار النص.
      final autoStart = offerTour &&
          (result.source == 'followup' ||
              GuideChatFollowUp.looksLikeTourAffirmation(q));
      if (autoStart) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        await _startTourFromMessage(line);
        return;
      }
      // غير ذلك: يظهر زر «ابدأ الإرشاد» تحت الرد.
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatLine(
            fromUser: false,
            text:
                'تعذّر الاتصال بالمساعد الآن. جرّب الاقتراحات الجاهزة أو أعد المحاولة.',
            rateable: true,
          ),
        );
        _loading = false;
      });
      _persistSession();
      _scrollToEnd();
    }
  }

  bool _replyMentionsGuide(String reply) {
    final t = reply.toLowerCase();
    return t.contains('إرشاد') ||
        t.contains('ارشاد') ||
        t.contains('خطوة بخطوة') ||
        t.contains('أسهم');
  }

  String _prepReplyForTour(String tourId) {
    final title = _titleFor(tourId);
    switch (tourId) {
      case GuideTourIds.oilFirstRun:
        return 'لتسجيل غيار زيت بشكل صحيح:\n'
            '1) افتح بطاقة غيار زيت جديدة من السجل أو الرئيسية.\n'
            '2) عبّئ العميل واللوحة والزيت والعداد.\n'
            '3) راجع الدفع ثم اضغط حفظ وبيع.\n\n'
            'جاهز؟ ابدأ الإرشاد على الشاشة بأسهم خطوة بخطوة لـ«$title».';
      case GuideTourIds.oilWhatsapp:
        return 'ربط واتساب المحل يتم من شاشة الربط (رقم نابو / Meta / QR)، '
            'مع إمكانية إعادة الربط أو الفصل بأمان.\n\n'
            'اضغط زر الإرشاد لأمشي معك خطوة بخطوة على الشاشة.';
      case GuideTourIds.carWashCreate:
        return 'لتسجيل غسيل سيارة:\n'
            '1) من الرئيسية اضغط «غسيل السيارات».\n'
            '2) أدخل اللوحة واختر أنواع الغسيل.\n'
            '3) راجع المبلغ ثم حفظ وبيع.\n\n'
            'اضغط زر الإرشاد لعرض الخطوات على الشاشة.';
      case GuideTourIds.carWashVisibility:
        return 'لإظهار أو إخفاء زر غسيل السيارات:\n'
            'الإعدادات → تخصيص الشاشة الرئيسية → مفتاح «زر غسيل السيارات».\n\n'
            'اضغط زر الإرشاد لأخذك إلى المفتاح مباشرة.';
      case GuideTourIds.usersModuleOverview:
        return 'وحدة «المستخدمين» من الشريط السفلي فيها ثلاثة أبواب:\n'
            '1) إدارة المستخدمين — القائمة والإضافة والتعديل.\n'
            '2) ورديات الموظفين (أسبوع) — حضور الدخول/الخروج.\n'
            '3) هويات الموظفين — بطاقة باركود/QR ورمز الوردية.\n\n'
            'اضغط زر الإرشاد لأمشي معك على الشاشات الثلاث.';
      case GuideTourIds.usersAddStaff:
        return 'فائدة الموظفين: PIN خاص من «من سيبدأ العمل؟»، وربطه بالوردية والصلاحيات دون مشاركة حساب المالك.\n\n'
            'صفحة مستخدم جديد بالتفصيل:\n'
            '1) المستخدمين → إدارة المستخدمين → زر «مستخدم جديد» أعلى الشاشة.\n'
            '2) الاسم الظاهر.\n'
            '3) PIN من 4 أرقام + تأكيد (ليس ضعيفاً).\n'
            '4) الصلاحية: محدود / كامل / تخصيص يدوي.\n'
            '5) حفظ — ثم غالباً بطاقة الهوية.\n\n'
            'اضغط زر الإرشاد لأمشي معك حقلاً حقلاً.';
      case GuideTourIds.usersIdentity:
        return 'هويات الموظفين:\n'
            'المستخدمين → هويات الموظفين، أو ⋮ على بطاقة المستخدم → بطاقة الهوية.\n'
            'تعرض الباركود وQR ورمز الوردية (غير PIN الدخول).\n\n'
            'اضغط زر الإرشاد لفتح الشاشة معك.';
      case GuideTourIds.usersShifts:
        return 'ورديات الموظفين (أسبوع):\n'
            'المستخدمين → ورديات الموظفين.\n'
            'تقويم سبت→جمعة مع أشرطة وقت العمل واسم الموظف.\n'
            'الورديات تُنشأ عند فتح/إغلاق الوردية اليومي.\n\n'
            'اضغط زر الإرشاد لعرض التقويم معك.';
      case GuideTourIds.productAddOverview:
        return 'إضافة منتج جديد:\n'
            '1) المخزون → قائمة المنتجات → «+ منتج جديد».\n'
            '2) الاسم (إلزامي) ثم التصنيف والماركة والمخزن.\n'
            '3) اختر نوع المخزون الأساسي: عدد / حجم / هيدروليك عائلة / زيت عائلة.\n'
            '4) المورد اختياري، ثم التسعير وإدارة المخزون حسب النوع.\n\n'
            'اضغط زر الإرشاد لأمشي معك حقلاً حقلاً.';
      case GuideTourIds.productStockCount:
        return 'منتج بالعدد (قطعة):\n'
            'اختر نوع «عدد» → سمِّ المنتج → أسعار الشراء/البيع → الكمية وتنبيه النفاد → حفظ.\n\n'
            'اضغط زر الإرشاد للتنفيذ على الشاشة.';
      case GuideTourIds.productStockVolume:
        return 'منتج بالحجم (لتر):\n'
            'اختر «حجم لتر» → وحدات إضافية (لتر/علبة) → التسعير → الكمية باللتر → حفظ.\n\n'
            'اضغط زر الإرشاد للتنفيذ على الشاشة.';
      case GuideTourIds.productStockHydraulic:
        return 'عائلة هيدروليك:\n'
            'اختر «هيدروليك عائلة» → الماركة → جدول الدرجات والعبوات والأسعار → حفظ.\n\n'
            'اضغط زر الإرشاد للتنفيذ على الشاشة.';
      case GuideTourIds.productStockOil:
        return 'عائلة زيت:\n'
            'اختر «زيت عائلة» → الماركة → اللزوجات والعبوات والأسعار → حفظ.\n\n'
            'اضغط زر الإرشاد للتنفيذ على الشاشة.';
      case GuideTourIds.productPricingInventory:
        return 'التسعير وإدارة المخزون:\n'
            'سعر شراء/بيع/أقل سعر، ثم تتبع المخزون والكمية وتنبيه النفاد.\n'
            'لعائلات الزيت/الهيدروليك الأسعار على جدول الدرجات.\n\n'
            'اضغط زر الإرشاد لشرح الخانات على الشاشة.';
      default:
        return 'سأشرح لك «$title» على الشاشة بأسهم خطوة بخطوة.\n'
            'اقرأ الملخص أعلاه، ثم اضغط زر بدء الإرشاد عندما تكون جاهزاً.';
    }
  }

  Future<void> _startTourFromMessage(_ChatLine line) async {
    final tourId = line.tourId;
    if (tourId == null ||
        tourId == GuideTourIds.none ||
        !_scope.canStartTour(tourId) ||
        _loading) {
      return;
    }
    final guide = context.read<GuideController>();
    Navigator.of(context).pop();
    await guide.startTour(tourId, fromChat: true);
  }

  Future<void> _rate(_ChatLine line, int rating) async {
    if (line.feedbackRating != null || !line.rateable) return;
    var question = line.questionForFeedback?.trim() ?? '';
    if (question.isEmpty) {
      final idx = _messages.indexOf(line);
      for (var i = idx - 1; i >= 0; i--) {
        if (_messages[i].fromUser) {
          question = _messages[i].text;
          break;
        }
      }
    }
    if (question.isEmpty) return;

    setState(() => line.feedbackRating = rating);
    await GuideFeedbackClient.instance.submit(
      question: question,
      answer: line.text,
      rating: rating,
      routeId: widget.currentRouteId,
      roleKey: _scope.roleKey,
      source: line.source ?? 'ai',
    );
  }

  void _clearMemory() {
    if (_loading) return;
    context.read<GuideController>().clearChatSession();
    setState(() {
      _messages
        ..clear()
        ..add(_ChatLine(fromUser: false, text: _scope.welcomeMessage()));
    });
  }

  String _titleFor(String id) {
    switch (id) {
      case GuideTourIds.oilFirstRun:
        return 'تسجيل غيار زيت';
      case GuideTourIds.oilWhatsapp:
        return 'ربط وفصل واتساب';
      case GuideTourIds.oilPendingTab:
        return 'المعلّقة';
      case GuideTourIds.oilPlateAutofill:
        return 'رقم اللوحة';
      case GuideTourIds.oilHubSettings:
        return 'إعدادات غيار الزيت';
      case GuideTourIds.oilCatalogOil:
        return 'كتالوج الزيت';
      case GuideTourIds.oilCatalogFilter:
        return 'كتالوج الفلاتر';
      case GuideTourIds.oilCatalogHydraulic:
        return 'كتالوج الهيدروليك';
      case GuideTourIds.oilServicesBase:
        return 'الخدمات والأسعار';
      case GuideTourIds.carWashHome:
        return 'زر غسيل السيارات';
      case GuideTourIds.carWashVisibility:
        return 'إظهار أو إخفاء زر الغسيل';
      case GuideTourIds.carWashCreate:
        return 'تسجيل غسيل سيارة';
      case GuideTourIds.usersModuleOverview:
        return 'دليل وحدة المستخدمين';
      case GuideTourIds.usersAddStaff:
        return 'إضافة مستخدم / موظف';
      case GuideTourIds.usersIdentity:
        return 'هويات الموظفين';
      case GuideTourIds.usersShifts:
        return 'ورديات الموظفين';
      case GuideTourIds.productAddOverview:
        return 'إضافة منتج جديد';
      case GuideTourIds.productStockCount:
        return 'منتج بالعدد';
      case GuideTourIds.productStockVolume:
        return 'منتج بالحجم';
      case GuideTourIds.productStockHydraulic:
        return 'عائلة هيدروليك';
      case GuideTourIds.productStockOil:
        return 'عائلة زيت';
      case GuideTourIds.productPricingInventory:
        return 'التسعير وإدارة المخزون';
      default:
        return 'الإرشاد';
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.72;
    final chips = _scope.suggestedChips();

    return SafeArea(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 4, 8, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _scope.titleAr,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: cs.onSurface,
                          ),
                          textAlign: TextAlign.start,
                        ),
                        Text(
                          _scope.subtitleAr,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'مسح ذاكرة المحادثة',
                    onPressed: _loading ? null : _clearMemory,
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final chip in chips) ...[
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: ActionChip(
                          label: Text(chip.label),
                          onPressed: _loading
                              ? null
                              : () => _send(
                                    chip.question,
                                    forcedTourId: chip.tourId,
                                  ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
                itemCount: _messages.length + (_loading ? 1 : 0),
                itemBuilder: (context, i) {
                  if (_loading && i == _messages.length) {
                    return Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(top: 8),
                        child: Text(
                          'جارٍ فهم سؤالك…',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    );
                  }
                  final m = _messages[i];
                  final offerTour = !m.fromUser &&
                      m.tourId != null &&
                      m.tourId != GuideTourIds.none &&
                      _scope.canStartTour(m.tourId!);
                  return Align(
                    alignment: m.fromUser
                        ? AlignmentDirectional.centerEnd
                        : AlignmentDirectional.centerStart,
                    child: Container(
                      margin: const EdgeInsetsDirectional.only(bottom: 8),
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.86,
                      ),
                      decoration: BoxDecoration(
                        color: m.fromUser
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            m.text,
                            textAlign: TextAlign.start,
                            style: TextStyle(
                              height: 1.4,
                              color: m.fromUser
                                  ? cs.onPrimaryContainer
                                  : cs.onSurface,
                            ),
                          ),
                          if (offerTour) ...[
                            const SizedBox(height: 10),
                            Material(
                              color: cs.primary,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: _loading
                                    ? null
                                    : () => _startTourFromMessage(m),
                                child: Padding(
                                  padding: const EdgeInsetsDirectional
                                      .fromSTEB(12, 10, 12, 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: cs.onPrimary
                                              .withValues(alpha: 0.16),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.play_arrow_rounded,
                                          color: cs.onPrimary,
                                          size: 26,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              'ابدأ الإرشاد على الشاشة',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                fontSize: 14,
                                                color: cs.onPrimary,
                                              ),
                                              textAlign: TextAlign.start,
                                            ),
                                            Text(
                                              'خطوة بخطوة بأسهم: ${_titleFor(m.tourId!)}',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                height: 1.25,
                                                color: cs.onPrimary
                                                    .withValues(alpha: 0.88),
                                              ),
                                              textAlign: TextAlign.start,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_back_ios_new_rounded,
                                        size: 16,
                                        color: cs.onPrimary
                                            .withValues(alpha: 0.9),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (m.rateable && !m.fromUser) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  'هل أفادك الرد؟',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'مفيد',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: m.feedbackRating != null
                                      ? null
                                      : () => _rate(m, 1),
                                  icon: Icon(
                                    m.feedbackRating == 1
                                        ? Icons.thumb_up_alt
                                        : Icons.thumb_up_alt_outlined,
                                    size: 18,
                                    color: m.feedbackRating == 1
                                        ? cs.primary
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'غير مفيد',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: m.feedbackRating != null
                                      ? null
                                      : () => _rate(m, -1),
                                  icon: Icon(
                                    m.feedbackRating == -1
                                        ? Icons.thumb_down_alt
                                        : Icons.thumb_down_alt_outlined,
                                    size: 18,
                                    color: m.feedbackRating == -1
                                        ? cs.error
                                        : cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_loading,
                      textInputAction: TextInputAction.send,
                      onSubmitted: _send,
                      decoration: const InputDecoration(
                        hintText: 'اسأل عن أي شيء ضمن صلاحيتك…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _loading
                        ? null
                        : () => _send(_controller.text),
                    icon: const Icon(Icons.send_rounded),
                    tooltip: 'إرسال',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatLine {
  _ChatLine({
    required this.fromUser,
    required this.text,
    this.rateable = false,
    this.questionForFeedback,
    this.source,
    this.tourId,
  });

  final bool fromUser;
  final String text;
  final bool rateable;
  final String? questionForFeedback;
  final String? source;
  final String? tourId;
  int? feedbackRating;
}
