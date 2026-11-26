import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../guides/guide_controller.dart';
import '../../guides/guide_narrator.dart';
import '../../guides/widgets/guide_chat_sheet.dart';
import '../../navigation/content_navigation.dart';
import '../../widgets/raw_keyboard_inset.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permissions_provider.dart';
import '../../services/permission_service.dart';
import '../../widgets/inputs/arabic_speech_mic_button.dart';
import '../assistant_access.dart';
import '../assistant_rollout.dart';
import '../assistant_thread_store.dart';
import '../course/assistant_course_screen.dart';
import '../../widgets/barcode_input_launcher.dart';
import '../data/assistant_image.dart';
import 'assistant_card_mapper_b4.dart';
import 'assistant_context_scope.dart';
import 'assistant_memory_screen.dart';
import 'assistant_reminders_screen.dart';
import 'assistant_car_photo_screen.dart';
import 'assistant_source_line.dart';
import '../screen_map/screen_map.dart';
import '../tools/setup_status_tool.dart';
import 'assistant_card_mapper.dart';
import 'assistant_chrome.dart';
import 'assistant_controller.dart';
import 'assistant_return_chip.dart';
import 'assistant_activity_icons.dart';
import 'assistant_message_view.dart';
import 'assistant_session.dart';
import 'assistant_suggestions.dart';
import 'assistant_view_models.dart';

/// عرض الشاشة الذي تصبح عنده الصفحة لوحة جانبية (م2-8، ق44).
const double kAssistantPanelBreakpoint = 900;
const double kAssistantPanelWidth = 420;

/// يفتح مساعد نابو من أي أيقونة (م2-10).
///
/// المفتاح `assistant_v2` مطفأ: الشات القديم كما هو. مشغَّل: الصفحة الجديدة،
/// صفحة كاملة على الهاتف، ولوحة بجانب المحتوى على الشاشات العريضة.
Future<void> openNabooAssistant(BuildContext context, {required String currentRouteId}) async {
  final rollout = AssistantRollout.instance;
  // يُحدَّث في الخلفية؛ الفتح لا ينتظر الشبكة.
  unawaited(() async {
    try {
      await rollout.refresh();
    } catch (_) {}
  }());
  if (!rollout.v2Enabled) {
    return showGuideChatSheet(context: context, currentRouteId: currentRouteId);
  }
  final s = AssistantSession.instance;
  s.currentRouteId = currentRouteId;
  s.currentRouteTitle = breadcrumbFallbackTitleForRouteId(currentRouteId);
  if (MediaQuery.sizeOf(context).width >= kAssistantPanelBreakpoint) {
    _AssistantPanel.show(context, currentRouteId);
    return;
  }
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'assistant'),
      builder: (_) => AssistantScreen(currentRouteId: currentRouteId),
    ),
  );
}

/// اللوحة الجانبية: طبقة بعرض ثابت في طرف الشاشة، والمحتوى خلفها يبقى يعمل.
abstract final class _AssistantPanel {
  static OverlayEntry? _entry;

  static void show(BuildContext context, String routeId) {
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => PositionedDirectional(
        top: 0,
        bottom: 0,
        end: 0,
        width: kAssistantPanelWidth,
        child: Material(
          elevation: 12,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: BorderDirectional(start: BorderSide(color: Theme.of(ctx).colorScheme.outline)),
            ),
            child: AssistantScreen(
              currentRouteId: AssistantSession.instance.currentRouteId ?? routeId,
              panel: true,
              onClose: close,
            ),
          ),
        ),
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void close() {
    _entry?.remove();
    _entry = null;
  }
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key, required this.currentRouteId, this.panel = false, this.onClose});

  final String currentRouteId;
  final bool panel;
  final VoidCallback? onClose;

  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  static const _mutePrefKey = AssistantSession.mutePrefKey;

  late final AssistantController _c;
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _listening = false;
  bool _speaking = false;

  /// السؤال الحالي جاء من الميكروفون.
  bool _voiceQuestion = false;

  /// null: الافتراضي (صامت، إلا إذا جاء السؤال بالصوت). true: مكتوم. false: ينطق دائماً.
  bool? _muted;

  bool _showThreads = false;
  List<StoredThread> _threads = const [];
  String _search = '';
  Timer? _searchDebounce;
  final _hold = ValueNotifier<SpeechHoldState?>(null);
  final _holdCtl = SpeechHoldController();

  /// رسائل كانت قبل فتح الصفحة: تظهر كاملة بلا كتابة تدريجية (ط5).
  Set<String> _oldIds = const {};
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    final s = AssistantSession.instance;
    _c = s.controllerFor(context);
    s.uiHandler = _onUiAction;
    s.beforeGuide = _beforeGuide;
    s.rootOverlay = Overlay.maybeOf(context, rootOverlay: true);
    // الشات ظاهر: الفقاعة لا تلزم.
    AssistantReturnChip.hide();
    _c.addListener(_onChange);
    _lastCount = _c.messages.length;
    _oldIds = {for (final m in _c.messages) m.id};
    unawaited(_loadMute());
    unawaited(_checkSetup());
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  @override
  void dispose() {
    _hold.dispose();
    _c.removeListener(_onChange);
    final s = AssistantSession.instance;
    if (s.uiHandler == _onUiAction) s.uiHandler = null;
    if (s.beforeGuide == _beforeGuide) s.beforeGuide = null;
    _c.signals.closed();
    unawaited(_c.flushSignals());
    if (_speaking) GuideNarrator.instance.unawaitedStop();
    _searchDebounce?.cancel();
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// «جهّز محلي معي» يظهر للمالك ما دام التجهيز ناقصاً (ق30).
  Future<void> _checkSetup() async {
    final s = AssistantSession.instance;
    if (!context.read<AuthProvider>().isOwner) return;
    try {
      final items = await readSetupStatus(s.setupSource);
      s.setupIncomplete = items.any((i) => !i.done);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _loadMute() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _muted = p.getBool(_mutePrefKey));
      AssistantSession.instance.ttsMuted = _muted;
    } catch (_) {}
  }

  Future<void> _toggleMute() async {
    final speaksNow = _muted == false;
    final next = speaksNow; // ينطق الآن ← يُكتم، وإلا يُشغَّل.
    setState(() => _muted = next);
    AssistantSession.instance.ttsMuted = next;
    if (next && _speaking) {
      await GuideNarrator.instance.stop();
      if (mounted) setState(() => _speaking = false);
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_mutePrefKey, next);
    } catch (_) {}
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (_c.messages.length != _lastCount) {
      _lastCount = _c.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd(animate: true));
    } else if (_c.busy) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
    }
  }

  void _jumpToEnd({bool animate = false}) {
    if (!_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    if (animate && !MediaQuery.disableAnimationsOf(context)) {
      unawaited(_scroll.animateTo(end, duration: const Duration(milliseconds: 220), curve: Curves.easeOut));
    } else {
      _scroll.jumpTo(end);
    }
  }

  // ---------------------------------------------------------------- الصورة (م2-13)
  Uint8List? _pendingImage;
  bool _pickingImage = false;

  Future<void> _pickImage() async {
    final canImage = _canAttachImage;
    // ط9: لوحة سفلية واضحة: الكاميرا والصور كبيرتان في الأعلى، والباقي تحتهما.
    final source = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => AssistantAttachSheet(
        canImage: canImage,
        canCarPhoto: canImage && _canCarPhoto,
        canScan: _canScan,
      ),
    );
    if (source == null || !mounted) return;
    if (source == 'barcode') {
      final code = await BarcodeInputLauncher.captureBarcode(context, title: 'امسح باركود المنتج');
      if (code != null && code.trim().isNotEmpty && mounted) await _c.askBarcode(code);
      return;
    }
    if (source == 'car_photo') {
      await _openCarPhoto();
      return;
    }
    if (source is! ImageSourceChoice) return;
    final picker = source == ImageSourceChoice.camera ? ImageSource.camera : ImageSource.gallery;
    setState(() => _pickingImage = true);
    try {
      final file = await ImagePicker().pickImage(source: picker, maxWidth: 2048, maxHeight: 2048, imageQuality: 90);
      if (file == null) return;
      final jpeg = await AssistantImage.compress(await file.readAsBytes());
      if (!mounted) return;
      if (jpeg == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ما گدرت أقرأ الصورة. جرّب صورة ثانية.')));
        return;
      }
      setState(() => _pendingImage = jpeg);
      _focus.requestFocus();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ما گدرت أفتح الكاميرا أو المعرض.')));
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Widget? _imagePreview() {
    final img = _pendingImage;
    if (img == null && !_pickingImage) return null;
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 14, 0),
      color: cs.surface,
      alignment: AlignmentDirectional.centerStart,
      child: img == null
          ? const SizedBox(width: 64, height: 64, child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          : Stack(
              children: [
                Semantics(
                  image: true,
                  label: 'الصورة المرفقة',
                  child: Image.memory(img, width: 64, height: 64, fit: BoxFit.cover),
                ),
                PositionedDirectional(
                  top: 0,
                  end: 0,
                  child: Material(
                    color: cs.surface.withValues(alpha: 0.85),
                    child: InkWell(
                      onTap: () => setState(() => _pendingImage = null),
                      child: Tooltip(
                        message: 'شيل الصورة',
                        child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close, size: 18, color: cs.onSurface)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------------- الإرسال
  Future<void> _send(String raw) async {
    final q = raw.trim();
    final image = _pendingImage;
    if ((q.isEmpty && image == null) || _c.busy) return;
    setState(() => _pendingImage = null);
    final byVoice = _voiceQuestion;
    _voiceQuestion = false;
    _input.clear();
    if (_speaking) {
      await GuideNarrator.instance.stop();
      _speaking = false;
    }
    await _c.ask(q, image: image);
    if (!mounted) return;
    final speak = _muted == false || (_muted == null && byVoice);
    if (speak && _c.messages.isNotEmpty && !_c.messages.last.fromUser) {
      unawaited(_speak(_c.messages.last));
    }
  }

  /// يُقرأ الجواب القصير فقط، لا البطاقات (4.8). بلا صوت عربي: يبقى النص بلا خطأ.
  Future<void> _speak(AssistantChatMessage m) async {
    var text = _c.display(m).trim();
    if (text.isEmpty || m.status != AssistantMessageStatus.done) return;
    if (text.length > 320) {
      final cut = text.lastIndexOf(RegExp(r'[.؟!\n]'), 320);
      text = text.substring(0, cut > 80 ? cut + 1 : 320);
    }
    setState(() => _speaking = true);
    try {
      await GuideNarrator.instance.speak(text, force: true);
    } finally {
      // speak يعود قبل انتهاء النطق؛ الحالة تُطفأ بعد مدة تقديرية.
      final ms = (text.length * 70).clamp(1200, 20000);
      Future<void>.delayed(Duration(milliseconds: ms), () {
        if (mounted) setState(() => _speaking = false);
      });
    }
  }

  // ---------------------------------------------------------------- أفعال الواجهة
  void _onUiAction(AssistantUiAction a) {
    switch (a) {
      case AssistantOpenRoute(:final routeId):
        unawaited(_openRoute(routeId));
      case AssistantStartTour(:final tourId):
        unawaited(_startTour(tourId));
    }
  }

  /// قبل أن تأخذ أداة إرشاد المستخدم لشاشة: الصفحة الكاملة تنطوي إلى الفقاعة،
  /// واللوحة الجانبية تبقى مفتوحة بجانب المحتوى.
  void _beforeGuide() {
    if (widget.panel || !mounted) return;
    unawaited(Navigator.of(context).maybePop());
  }

  Future<void> _openVideo(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  Future<void> _openRoute(String routeId) async {
    final guide = context.read<GuideController>();
    if (!widget.panel && mounted) unawaited(Navigator.of(context).maybePop());
    await guide.openRoute(routeId);
  }

  Future<void> _startTour(String tourId) async {
    final guide = context.read<GuideController>();
    if (widget.panel) {
      widget.onClose?.call();
    } else if (mounted) {
      unawaited(Navigator.of(context).maybePop());
    }
    await guide.startTour(tourId, fromChat: true);
  }

  Future<void> _reportWrong(AssistantChatMessage m) async {
    final correction = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _WrongAnswerSheet(),
    );
    if (correction == null || !mounted) return;
    await _c.reportWrong(m, correction: correction);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(const SnackBar(content: Text('وصلت ملاحظتك، شكراً. تساعدنا نصلّح الجواب.')));
  }

  // ---------------------------------------------------------------- السجل
  Future<void> _openThreads() async {
    await _reloadThreads();
    if (!mounted) return;
    if (widget.panel) {
      setState(() => _showThreads = true);
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  void _closeThreads() {
    if (widget.panel) {
      setState(() => _showThreads = false);
    } else {
      _scaffoldKey.currentState?.closeDrawer();
    }
  }

  Future<void> _reloadThreads() async {
    final guide = context.read<GuideController>();
    try {
      final list = await AssistantSession.instance.store.listThreads(
        tenantId: guide.tenantId,
        userKey: guide.userKey,
        search: _search,
      );
      if (mounted) setState(() => _threads = list);
    } catch (_) {}
  }

  void _onSearch(String q) {
    _search = q;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () => unawaited(_reloadThreads()));
  }

  Future<void> _openThread(String id) async {
    _closeThreads();
    if (id == _c.threadId) return;
    await _c.openThread(id);
    _lastCount = _c.messages.length;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToEnd());
  }

  Future<void> _deleteThread(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المحادثة؟'),
        content: const Text('تنحذف من هذا الجهاز ولا ترجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('احذف')),
        ],
      ),
    );
    if (ok != true) return;
    await AssistantSession.instance.store.deleteThread(id);
    if (id == _c.threadId) _c.newThread();
    await _reloadThreads();
  }

  void _newThread() {
    _closeThreads();
    if (_speaking) GuideNarrator.instance.unawaitedStop();
    _c.newThread();
    _lastCount = 0;
  }

  List<AssistantThreadGroup> _groups() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final buckets = <String, List<AssistantThreadItem>>{};
    for (final t in _threads) {
      final d = DateTime(t.updatedAt.year, t.updatedAt.month, t.updatedAt.day);
      final days = today.difference(d).inDays;
      final label = days <= 0
          ? 'اليوم'
          : days == 1
          ? 'أمس'
          : days < 7
          ? 'هذا الأسبوع'
          : 'أقدم';
      final when = days <= 0
          ? '${t.updatedAt.hour.toString().padLeft(2, '0')}:${t.updatedAt.minute.toString().padLeft(2, '0')}'
          : '${t.updatedAt.day}/${t.updatedAt.month}';
      buckets
          .putIfAbsent(label, () => [])
          .add(
            AssistantThreadItem(
              t.title,
              _c.moneyRefs.render(t.preview).replaceAll(RegExp(r'⟦m\d+⟧'), '—'),
              when,
              id: t.id,
            ),
          );
    }
    return [for (final e in buckets.entries) AssistantThreadGroup(e.key, e.value)];
  }

  // ---------------------------------------------------------------- العرض
  AssistantMarkState get _markState {
    if (_listening) return AssistantMarkState.listening;
    if (_c.busy) return AssistantMarkState.thinking;
    if (_speaking) return AssistantMarkState.speaking;
    return AssistantMarkState.idle;
  }

  String get _subtitle => switch (_markState) {
    AssistantMarkState.listening => 'يستمع…',
    AssistantMarkState.thinking => 'يفكّر…',
    AssistantMarkState.speaking => 'يتكلم…',
    AssistantMarkState.idle => 'جاهز',
  };

  static String _toolStatus(String? tool) => switch (tool) {
    'stock_search' || 'stock_low' || 'product_detail' => 'أفحص المخزون…',
    'oil_card_find' || 'car_history' => 'أراجع البطاقات…',
    'sales_summary' => 'أحسب المبيعات…',
    'cash_summary' => 'أراجع الصندوق…',
    'debts_summary' => 'أراجع الديون…',
    'staff_status' => 'أشوف الوردية…',
    'car_spec' => 'أدوّر مواصفة السيارة…',
    'ui_navigate' => 'أفتح الشاشة…',
    String t when t.startsWith('prepare_') => 'أجهّز البيانات…',
    _ => 'أفحص البيانات…',
  };

  AssistantViewMessage _view(AssistantChatMessage m) {
    if (m.fromUser) {
      return AssistantViewMessage(
        fromUser: true,
        text: m.text,
        imageBytes: m.image,
        imageLabel: m.image == null && m.text.startsWith('[صورة]') ? 'صورة' : null,
      );
    }
    final status = switch (m.status) {
      AssistantMessageStatus.thinking => 'أفكّر…',
      AssistantMessageStatus.runningTools => _toolStatus(m.runningTool),
      AssistantMessageStatus.streaming when _c.display(m).trim().isEmpty => 'أكتب الجواب…',
      _ => null,
    };
    final activity = switch (m.status) {
      AssistantMessageStatus.runningTools => AssistantActivity.searching,
      AssistantMessageStatus.streaming => AssistantActivity.writing,
      _ => AssistantActivity.thinking,
    };
    final cards = AssistantCardMapper.fromResults(m.results);
    final src = AssistantSourceLine.of(m.results, knowledge: m.knowledge);
    var text = _c.display(m);
    if (m.status == AssistantMessageStatus.cancelled) {
      text = text.trim().isEmpty ? 'وقّفت الجواب.' : '$text\n(وقّفت الجواب)';
    }
    return AssistantViewMessage(
      fromUser: false,
      id: m.id,
      text: text,
      status: status,
      activity: activity,
      // ط5: الجواب الآتي من الخادم في هذه الجلسة يُكتب تدريجياً، والمحلي والقديم يظهر كاملاً.
      animateText: !m.local && !_oldIds.contains(m.id),
      complete: m.status != AssistantMessageStatus.streaming &&
          m.status != AssistantMessageStatus.thinking &&
          m.status != AssistantMessageStatus.runningTools,
      cards: cards,
      followups: m.status == AssistantMessageStatus.done ? m.followups.take(3).toList() : const [],
      choices: m.status == AssistantMessageStatus.done ? AssistantCardMapperB4.choicesFrom(m.results) : const [],
      source: src?.summary,
      sourceDetails: src?.details ?? const [],
      sourceRoute: cards.map((c) => c.routeId).whereType<String>().firstOrNull,
      actions:
          m.status == AssistantMessageStatus.done ||
          m.status == AssistantMessageStatus.error ||
          m.status == AssistantMessageStatus.cancelled,
    );
  }

  Widget _messages() {
    // ط4: طلب «أعد الصياغة» داخلي ولا يظهر.
    final ms = _c.messages.where((m) => !m.hidden).toList();
    final lastAssistant = ms.lastIndexWhere((m) => !m.fromUser);
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsetsDirectional.fromSTEB(14, 16, 14, 16),
      itemCount: ms.length,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (_, i) {
        final m = ms[i];
        final v = _view(m);
        final live = i == ms.length - 1 && !m.fromUser;
        return AssistantMessageView(
          v,
          markState: live ? _markState : AssistantMarkState.idle,
          onFollowup: (f) => unawaited(_send(f)),
          onCopy: () async {
            await Clipboard.setData(ClipboardData(text: v.text));
            if (!mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('نُسخ الجواب')));
          },
          showRetry: i == lastAssistant && !_c.busy && !m.local && m.status == AssistantMessageStatus.error,
          onRetry: () => unawaited(_c.retryLast()),
          showRephrase:
              i == lastAssistant && !_c.busy && !m.local && m.status == AssistantMessageStatus.done && m.text.trim().isNotEmpty,
          onRephrase: () => unawaited(_c.rephraseLast()),
          showWrong: m.turnId != null,
          onWrong: () => unawaited(_reportWrong(m)),
          onOpenCard: (card) {
            final r = card.routeId;
            if (r != null) unawaited(_openRoute(r));
          },
          onOpenRoute: (r) => unawaited(_openRoute(r)),
          shareFinancial: context.read<AuthProvider>().isOwner,
          extra: m.suggestedTourId == null && m.videoUrl == null
              ? null
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (m.videoUrl != null)
                      AssistantSuggestionChip(
                        'شاهد الشرح',
                        icon: Icons.ondemand_video_rounded,
                        onTap: () => unawaited(_openVideo(m.videoUrl!)),
                      ),
                    if (m.suggestedTourId != null)
                      AssistantSuggestionChip(
                        'ابدأ الجولة',
                        icon: Icons.play_arrow_rounded,
                        onTap: () => unawaited(_startTour(m.suggestedTourId!)),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _start() {
    final auth = context.read<AuthProvider>();
    final perms = context.read<PermissionsProvider>();
    final level = AssistantAccess.levelFor(isOwner: auth.isOwner, can: perms.can);
    // ق35، م2-19: الاسم يُعرض هنا فقط ولا يُرسل للخادم.
    final parts = auth.displayName.trim().split(RegExp(r'\s+'));
    // «أبو حسن» و«أم علي» اسم واحد.
    final kunya = parts.length > 1 && const {'أبو', 'ابو', 'أم', 'ام'}.contains(parts.first);
    final name = kunya ? '${parts[0]} ${parts[1]}' : parts.first;
    return AssistantStartView(
      name: name,
      fromScreen: breadcrumbFallbackTitleForRouteId(widget.currentRouteId),
      suggestions: AssistantSuggestions.forScreen(
        routeId: widget.currentRouteId,
        level: level,
        isOwner: auth.isOwner,
        offerSetup: AssistantSession.instance.setupIncomplete == true,
        canExplain: AppScreenMap.byRoute(widget.currentRouteId) != null,
      ),
      showPhotoHint: false,
      guideOnly: level == AssistantLevel.guideOnly,
      footer: Column(
        children: [
          _courseEntry(auth.isOwner),
          const SizedBox(height: 8),
          _memoryEntry(canDelete: auth.isOwner || perms.can(PermissionKeys.settingsApp)),
          const SizedBox(height: 8),
          _remindersEntry(),
        ],
      ),
      onSuggestion: (s) {
        // سؤال بنقاط يحتاج إكمالاً: يُوضع في الحقل بدل إرساله.
        if (s.endsWith('…')) {
          _input.text = s.substring(0, s.length - 1);
          _focus.requestFocus();
        } else {
          unawaited(_send(s));
        }
      },
    );
  }

  /// مدخل دورة الموظف (م3-14): للموظف مساره، وللمالك تقدّم موظفيه.
  Widget _courseEntry(bool owner) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.school_outlined, color: cs.secondary),
        title: Text(owner ? 'دورة الموظفين وتقدّمهم' : 'دورة الموظف الجديد'),
        subtitle: Text(owner ? 'شوف وين وصل كل موظف' : 'تعلّم شغلك خطوة خطوة'),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: () => unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: AssistantCourseScreen.routeName),
              builder: (_) => AssistantCourseScreen(canOpen: AssistantSession.instance.canOpenRoute),
            ),
          ),
        ),
      ),
    );
  }

  /// صفحة «ما أعرفه عنك» (م2-15).
  Widget _memoryEntry({required bool canDelete}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.bookmarks_outlined, color: cs.secondary),
        title: const Text('ما أعرفه عنك'),
        subtitle: const Text('الأشياء اللي طلبت مني أتذكرها'),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: () => unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: AssistantMemoryScreen.routeName),
              builder: (_) => AssistantMemoryScreen(canDelete: canDelete),
            ),
          ),
        ),
      ),
    );
  }

  /// م4-13: لمن يفتح بطاقة الغيار، والمساعد الجديد مفعّل.
  bool get _canCarPhoto =>
      AssistantRollout.instance.v2Enabled &&
      AssistantSession.instance.execPort != null &&
      AssistantSession.instance.canOpenRoute(AppContentRoutes.oilChangeCreate);

  Future<void> _openCarPhoto() async {
    final session = AssistantSession.instance;
    final exec = session.execPort;
    final api = session.api;
    if (exec == null || api == null) return;
    final username = context.read<AuthProvider>().displayName;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AssistantCarPhotoScreen.routeName),
        builder: (ctx) => AssistantCarPhotoScreen(
          pick: () => _pickCarPhoto(ctx),
          read: (imgs) async => AssistantCarPhotoRead.fromJson(await api.readCarPhoto(imgs)),
          lookup: exec.lookupPlate,
          open: (values) async {
            Navigator.of(ctx).pop();
            await exec.openCarPhotoCard(values, username: username);
          },
        ),
      ),
    );
  }

  Future<Uint8List?> _pickCarPhoto(BuildContext ctx) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: ctx,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('صوّر بالكاميرا'),
              onTap: () => Navigator.pop(c, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('اختر من المعرض'),
              onTap: () => Navigator.pop(c, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return null;
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 2048, maxHeight: 2048, imageQuality: 90);
      if (file == null) return null;
      return AssistantImage.compress(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  /// «تذكيراتي» (م4-11).
  Widget _remindersEntry() {
    final cs = Theme.of(context).colorScheme;
    final guide = context.read<GuideController>();
    final session = AssistantSession.instance;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(Icons.alarm_outlined, color: cs.secondary),
        title: const Text('تذكيراتي'),
        subtitle: const Text('اللي طلبت مني أذكّرك بيه'),
        trailing: const Icon(Icons.chevron_left_rounded),
        onTap: () => unawaited(
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: AssistantRemindersScreen.routeName),
              builder: (_) => AssistantRemindersScreen(
                store: session.reminders,
                tenantId: '${guide.tenantId}',
                userKey: guide.userKey,
                onCancel: session.cancelReminder,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// الباركود يقرأ المخزون من الجهاز (م1-24).
  bool get _canScan {
    final auth = context.read<AuthProvider>();
    return auth.isOwner || context.read<PermissionsProvider>().can(PermissionKeys.inventoryView);
  }

  /// الصور لمستوى «كامل» فقط، وتتوقف بوضع التوفير (الخادم يرفضها أصلاً).
  bool get _canAttachImage {
    if (_c.busy || _c.budget?.economy == true || _c.budget?.exhausted == true) return false;
    final auth = context.read<AuthProvider>();
    final perms = context.read<PermissionsProvider>();
    return AssistantAccess.levelFor(isOwner: auth.isOwner, can: perms.can) == AssistantLevel.full;
  }

  Widget? _budget() {
    final b = _c.budget;
    if (b == null) return null;
    if (b.exhausted || b.pct >= 100) {
      return AssistantBudgetStrip(pct: 100, renewsOn: b.renewsOn ?? '', exhausted: true);
    }
    if (b.pct >= 70) return AssistantBudgetStrip(pct: b.pct.round(), renewsOn: b.renewsOn ?? '');
    return null;
  }

  Widget _threadsPanel() => AssistantThreadsPanel(
    groups: _groups(),
    count: _threads.length,
    selectedId: _c.threadId,
    onOpen: (id) => unawaited(_openThread(id)),
    onDelete: (id) => unawaited(_deleteThread(id)),
    onNew: _newThread,
    onClose: _closeThreads,
    onSearch: _onSearch,
  );

  @override
  Widget build(BuildContext context) {
    final header = AssistantHeader(
      subtitle: _subtitle,
      muted: _muted != false,
      markState: _markState,
      showBack: !widget.panel,
      onMute: () => unawaited(_toggleMute()),
      onHistory: () => unawaited(_openThreads()),
      onNew: _newThread,
      onClose: widget.panel ? widget.onClose : null,
    );
    final composer = AssistantComposer(
      controller: _input,
      focusNode: _focus,
      streaming: _c.busy,
      listening: _listening,
      onSend: (v) => unawaited(_send(v)),
      onStop: _c.stop,
      onPhoto: (_canAttachImage || _canScan) && !_c.busy ? () => unawaited(_pickImage()) : null,
      hold: _hold,
      onHoldFinish: _holdCtl.finish,
      onHoldCancel: _holdCtl.cancel,
      mic: ArabicSpeechMicButton(
        controller: _input,
        size: 44,
        tooltip: 'اسأل بالصوت',
        // ط8: اضغط مطوّلاً وتكلّم، ارفع إصبعك فيُرسل.
        holdState: _hold,
        holdController: _holdCtl,
        onHoldSend: (text) {
          _voiceQuestion = true;
          unawaited(_send(text));
        },
        onTextUpdated: () => _voiceQuestion = true,
        onListeningChanged: (v) {
          if (mounted) setState(() => _listening = v);
        },
      ),
    );
    final budget = _budget();
    final body = Column(
      children: [
        ?budget,
        Expanded(
          // أي لمس أو تمرير بعد الجواب يعني أنه قرأه (إشارة «أُغلق بسرعة» لا تُحسب).
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _c.signals.interacted(),
            child: _c.messages.isEmpty ? _start() : _messages(),
          ),
        ),
        ?_imagePreview(),
        const _ContextStrip(),
        composer,
      ],
    );
    // ط2: التطبيق يصفّر ارتفاع الكيبورد عن Flutter في أندرويد عمداً (adjustNothing)
    // ويرسله بقناة naboo/ime_insets، فـ Scaffold لا يرفع الحقل وحده. نرفعه نحن
    // بالارتفاع الحقيقي على كل الأنظمة، ونطفئ الرفع التلقائي حتى لا يتضاعف في iOS.
    return Scaffold(
      key: _scaffoldKey,
      appBar: header,
      resizeToAvoidBottomInset: false,
      drawer: widget.panel ? null : Drawer(width: 320, shape: const RoundedRectangleBorder(), child: _threadsPanel()),
      body: widget.panel && _showThreads
          ? _threadsPanel()
          : RawKeyboardInsetBuilder(
              builder: (context, keyboard) => AnimatedPadding(
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                padding: EdgeInsets.only(bottom: keyboard),
                child: body,
              ),
            ),
    );
  }
}

/// حقل التصحيح الاختياري لزر «جواب خاطئ» (م2-17).
class _WrongAnswerSheet extends StatefulWidget {
  const _WrongAnswerSheet();

  @override
  State<_WrongAnswerSheet> createState() => _WrongAnswerSheetState();
}

class _WrongAnswerSheetState extends State<_WrongAnswerSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return RawKeyboardInsetBuilder(
      builder: (context, keyboard) => Padding(
      padding: EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16 + keyboard),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('الجواب غلط؟', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            'إذا تعرف الصحيح اكتبه (اختياري). لا تكتب أرقام هواتف.',
            style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              hintText: 'الصحيح هو…',
              border: OutlineInputBorder(borderRadius: BorderRadius.zero),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.pop(context, _text.text),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('أرسل'),
          ),
        ],
      ),
      ),
    );
  }
}

/// شريط «عن: …» فوق حقل الإدخال (ق67): العنصر المفتوح الذي تعنيه «هذا» و«هنا».
class _ContextStrip extends StatelessWidget {
  const _ContextStrip();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AssistantContextItem?>(
      valueListenable: AssistantScreenContext.current,
      builder: (context, item, _) {
        if (item == null) return const SizedBox.shrink();
        final t = Theme.of(context);
        final cs = t.colorScheme;
        final icon = switch (item.kind) {
          'product' => Icons.inventory_2_outlined,
          'customer' => Icons.person_outline_rounded,
          'invoice' => Icons.receipt_long_outlined,
          _ => Icons.oil_barrel_outlined,
        };
        return Container(
          color: cs.surface,
          padding: const EdgeInsetsDirectional.fromSTEB(14, 6, 4, 0),
          child: Row(
            children: [
              Icon(icon, size: 16, color: cs.secondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'عن: ${item.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'لا تربط السؤال بهذا',
                onPressed: AssistantScreenContext.dismiss,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        );
      },
    );
  }
}
