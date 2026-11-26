import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';


import '../../theme/design_tokens.dart';
import 'assistant_mark.dart';
import 'assistant_message_view.dart';
import 'assistant_view_models.dart';
import '../../widgets/inputs/arabic_speech_mic_button.dart' show SpeechHoldState;

/// أجزاء الصفحة الثابتة: الرأس، حقل الإدخال، شاشة البداية، السجل، الفقاعة،
/// شريط الرصيد (م2-3، م2-5، م2-7، م2-16، م3).

/// رأس الصفحة: رجوع، الرمز والاسم وحالته، ثم السجل والكتم ومحادثة جديدة.
class AssistantHeader extends StatelessWidget implements PreferredSizeWidget {
  const AssistantHeader({
    super.key,
    this.subtitle = 'جاهز',
    this.muted = true,
    this.markState = AssistantMarkState.idle,
    this.animateMark = true,
    this.showBack = true,
    this.onHistory,
    this.onNew,
    this.onMute,
    this.onClose,
    this.onBack,
  });

  final VoidCallback? onBack;
  final String subtitle;
  final bool muted;
  final AssistantMarkState markState;
  final bool animateMark;
  final bool showBack;
  final VoidCallback? onHistory;
  final VoidCallback? onNew;
  final VoidCallback? onMute;

  /// على الحاسبة: يغلق اللوحة الجانبية بدل الرجوع.
  final VoidCallback? onClose;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fg = t.appBarTheme.foregroundColor ?? t.colorScheme.onPrimary;
    final bg = t.appBarTheme.backgroundColor ?? t.colorScheme.primary;
    final gold = t.colorScheme.secondary;
    // بخط كبير لا يتسع الرأس لسطرين: تُخفى الحالة، وهي ظاهرة في الرمز وفي سطر «أفكّر…» بالمحادثة.
    final bigText = MediaQuery.textScalerOf(context).scale(10) > 13;
    Widget btn(IconData i, String tip, VoidCallback? f) => IconButton(
      tooltip: tip,
      onPressed: f ?? () {},
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      icon: Icon(i, color: fg, size: 22),
    );
    return Material(
      color: bg,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              if (showBack)
                btn(Icons.adaptive.arrow_back, 'رجوع', onBack ?? () => Navigator.of(context).maybePop())
              else
                const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(border: Border.all(color: gold.withValues(alpha: 0.55))),
                child: Theme(
                  data: t.copyWith(colorScheme: t.colorScheme.copyWith(primary: bg)),
                  child: AssistantMark(size: 26, state: markState, animate: animateMark),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'مساعد نابو',
                      maxLines: 1,
                      // بلا التفاف يُقصّ أول الاسم بالخط الكبير في الاتجاه العربي.
                      softWrap: true,
                      overflow: TextOverflow.fade,
                      style: t.appBarTheme.titleTextStyle?.copyWith(color: fg),
                    ),
                    if (!bigText)
                      Text(
                        subtitle,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: t.textTheme.labelSmall?.copyWith(color: fg.withValues(alpha: 0.72)),
                      ),
                  ],
                ),
              ),
              btn(
                muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
                muted ? 'تشغيل الصوت' : 'كتم الصوت',
                onMute,
              ),
              btn(Icons.history, 'المحادثات السابقة', onHistory),
              if (onClose != null)
                btn(Icons.close, 'إغلاق', onClose)
              else
                btn(Icons.add_comment_outlined, 'محادثة جديدة', onNew),
            ],
          ),
        ),
      ),
    );
  }
}

/// حقل الإدخال: صورة، نص، ميكروفون أو إرسال، وإيقاف أثناء البث.
class AssistantComposer extends StatelessWidget {
  const AssistantComposer({
    super.key,
    this.text = '',
    this.streaming = false,
    this.listening = false,
    this.hint = 'اسأل عن المخزون أو أي شاشة…',
    this.controller,
    this.focusNode,
    this.onSend,
    this.onStop,
    this.mic,
    this.onPhoto,
    this.hold,
    this.onHoldFinish,
    this.onHoldCancel,
  });

  /// ط8: التسجيل بالضغط المطوّل، يُرسم شريط التسجيل مكان الحقل ما دام غير null.
  final ValueListenable<SpeechHoldState?>? hold;

  /// أزرار الشريط المقفل.
  final VoidCallback? onHoldFinish;
  final VoidCallback? onHoldCancel;

  final String text;
  final bool streaming;
  final bool listening;
  final String hint;

  /// الوضع الحي: حقل حقيقي. بدونه يُرسم شكل ثابت (للإطارات).
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSend;
  final VoidCallback? onStop;

  /// زر الميكروفون الحي (يكتب في [controller]).
  final Widget? mic;

  /// الصور تأتي في ب4 (م2-13). بلا دالة لا يظهر الزر في الوضع الحي.
  final VoidCallback? onPhoto;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) return _build(context, text, null);
    final h = hold;
    Widget withText(SpeechHoldState? hs) => ValueListenableBuilder<TextEditingValue>(
      valueListenable: c,
      builder: (context, v, _) => _build(context, v.text, hs),
    );
    if (h == null) return withText(null);
    return ValueListenableBuilder<SpeechHoldState?>(valueListenable: h, builder: (context, hs, _) => withText(hs));
  }

  Widget _build(BuildContext context, String text, SpeechHoldState? holdState) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final live = controller != null;
    final holding = holdState != null;
    // أثناء الضغط المطوّل يبقى الميكروفون حتى لو ظهر نص، وإلا انقطع الضغط.
    final hasText = text.trim().isNotEmpty && !holding;
    final (IconData mainIcon, String mainTip) = streaming
        ? (Icons.stop, 'إيقاف')
        : hasText
        ? (Icons.arrow_upward, 'إرسال')
        : (listening ? Icons.graphic_eq : Icons.mic_none, listening ? 'أستمع…' : 'اسأل بالصوت');
    return Material(
      color: cs.surface,
      child: Container(
        decoration: BoxDecoration(
          border: BorderDirectional(top: BorderSide(color: cs.outline)),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(6, 8, 8, 8),
        child: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!live || onPhoto != null)
                IconButton(
                  tooltip: 'صورة',
                  onPressed: onPhoto ?? () {},
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: Icon(Icons.add_a_photo_outlined, color: cs.onSurfaceVariant),
                )
              else
                const SizedBox(width: 6),
              Expanded(
                child: holding
                    ? AssistantRecordingBar(
                        state: holdState,
                        text: text,
                        onSend: onHoldFinish,
                        onCancel: onHoldCancel,
                      )
                    : live
                    ? TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (v) => onSend?.call(v),
                        style: t.textTheme.bodyMedium,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: listening ? 'تكلّم… النص يظهر هنا لتراجعه قبل الإرسال' : hint,
                          filled: true,
                          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                          contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.7)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: listening ? cs.secondary : cs.outline.withValues(alpha: 0.7)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.zero,
                            borderSide: BorderSide(color: cs.secondary, width: 1.5),
                          ),
                        ),
                      )
                    : Container(
                        constraints: const BoxConstraints(minHeight: 44),
                        alignment: AlignmentDirectional.centerStart,
                        padding: const EdgeInsetsDirectional.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                          border: Border.all(color: listening ? cs.secondary : cs.outline.withValues(alpha: 0.7)),
                        ),
                        child: Text(
                          hasText ? text : (listening ? 'تكلّم… النص يظهر هنا لتراجعه قبل الإرسال' : hint),
                          style: t.textTheme.bodyMedium?.copyWith(color: hasText ? cs.onSurface : cs.onSurfaceVariant),
                        ),
                      ),
              ),
              const SizedBox(width: 6),
              if (live && (holding || (!streaming && !hasText)) && mic != null)
                SizedBox.square(
                  dimension: 44,
                  child: ColoredBox(
                    color: listening ? cs.secondary.withValues(alpha: 0.18) : cs.surfaceContainerHighest,
                    child: Center(child: mic),
                  ),
                )
              else if (live)
                Semantics(
                  button: true,
                  label: mainTip,
                  child: Material(
                    color: cs.primary,
                    child: InkWell(
                      onTap: streaming ? onStop : (hasText ? () => onSend?.call(controller!.text) : null),
                      child: SizedBox.square(
                        dimension: 44,
                        child: Tooltip(
                          message: mainTip,
                          child: Icon(mainIcon, color: cs.onPrimary),
                        ),
                      ),
                    ),
                  ),
                )
              else
                Semantics(
                  button: true,
                  label: mainTip,
                  child: Container(
                    width: 44,
                    height: 44,
                    color: streaming || hasText ? cs.primary : (listening ? cs.secondary : cs.surfaceContainerHighest),
                    child: Icon(mainIcon, color: streaming || hasText || listening ? cs.onPrimary : cs.onSurface),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شاشة البداية (م2-5، ق11، ق35، ق47): الرمز، تحية بالاسم محلياً، و4 أسئلة
/// مقترحة حسب الشاشة. لا بيانات ولا تنبيهات تلقائية.
class AssistantStartView extends StatelessWidget {
  const AssistantStartView({
    super.key,
    required this.name,
    required this.fromScreen,
    required this.suggestions,
    this.animateMark = true,
    this.onSuggestion,
    this.showPhotoHint = true,
    this.footer,
    this.guideOnly = false,
  });

  final String name;
  final String fromScreen;
  final List<String> suggestions;
  final bool animateMark;
  final ValueChanged<String>? onSuggestion;
  final bool showPhotoHint;

  /// بطاقة تحت الاقتراحات (دورة الموظف).
  final Widget? footer;

  /// «إرشاد فقط»: لا يُدعى للسؤال عن أرقام المحل لأنه لا يراها.
  final bool guideOnly;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 40, 20, 20),
      children: [
        Center(child: AssistantMark(size: 64, animate: animateMark)),
        const SizedBox(height: 18),
        Text(
          name.trim().isEmpty ? 'هلا بيك' : 'هلا ${name.trim()}',
          textAlign: TextAlign.center,
          style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          guideOnly
              ? 'اسألني وين تلگى أي شي بالتطبيق،\nوشلون تسوي شغلك خطوة خطوة.'
              : 'اسألني عن المخزون والبطاقات والمبيعات،\nأو وين تلگى أي شي بالتطبيق.',
          textAlign: TextAlign.center,
          style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.5),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Icon(Icons.place_outlined, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('من شاشة $fromScreen', style: t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 8),
        for (final s in suggestions)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 8),
            child: _StartSuggestion(s, onTap: onSuggestion == null ? null : () => onSuggestion!(s)),
          ),
        if (footer != null) ...[const SizedBox(height: 6), footer!],
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.mic_none, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text('تگدر تسأل بالصوت', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            if (showPhotoHint) ...[
              const SizedBox(width: 14),
              Icon(Icons.add_a_photo_outlined, size: 15, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('أو بصورة', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ],
    );
  }
}

class _StartSuggestion extends StatelessWidget {
  const _StartSuggestion(this.text, {this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Semantics(
      button: true,
      label: text,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 10, 10),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(isolateLtr(text), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              Icon(Icons.adaptive.arrow_forward, size: 18, color: cs.secondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط الرصيد (م2-16): يظهر من 70%.
class AssistantBudgetStrip extends StatelessWidget {
  const AssistantBudgetStrip({super.key, required this.pct, required this.renewsOn, this.exhausted = false});
  final int pct;
  final String renewsOn;

  /// 100%: النموذج موقوف حتى التجدد، والجولات والأسئلة الشائعة تبقى.
  final bool exhausted;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final c = exhausted ? AppSemanticColors.danger : AppSemanticColors.warning;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        border: BorderDirectional(bottom: BorderSide(color: c.withValues(alpha: 0.4))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(exhausted ? Icons.block : Icons.speed, size: 15, color: c),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  exhausted
                      ? 'خلص رصيد المساعد لهذا الشهر${renewsOn.isEmpty ? '' : '، يتجدد $renewsOn'}. الجولات والأسئلة الشائعة تبقى شغالة.'
                      : 'استعملت $pct% من رصيد المساعد هذا الشهر. الأجوبة صارت أقصر.${renewsOn.isEmpty ? '' : ' يتجدد $renewsOn.'}',
                  style: t.textTheme.bodySmall?.copyWith(color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (pct / 100).clamp(0, 1).toDouble(),
            minHeight: 3,
            color: c,
            backgroundColor: c.withValues(alpha: 0.18),
          ),
        ],
      ),
    );
  }
}

/// درج المحادثات السابقة (م2-7): جديدة، بحث، آخر 50، حذف.
class AssistantThreadsPanel extends StatelessWidget {
  const AssistantThreadsPanel({
    super.key,
    required this.groups,
    required this.count,
    this.selectedId,
    this.onOpen,
    this.onDelete,
    this.onNew,
    this.onClose,
    this.onSearch,
  });
  final List<AssistantThreadGroup> groups;
  final int count;
  final String? selectedId;
  final ValueChanged<String>? onOpen;
  final ValueChanged<String>? onDelete;
  final VoidCallback? onNew;
  final VoidCallback? onClose;

  /// الوضع الحي: حقل بحث حقيقي.
  final ValueChanged<String>? onSearch;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text('المحادثات', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Text('$count من 50', style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: onClose ?? () {},
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
            child: Material(
              color: cs.primary,
              child: InkWell(
                onTap: onNew,
                child: SizedBox(
                  height: 44,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, color: cs.onPrimary, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'محادثة جديدة',
                        style: t.textTheme.labelLarge?.copyWith(color: cs.onPrimary, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 16, 6),
            child: onSearch != null
                ? TextField(
                    onChanged: onSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'ابحث بالمحادثات',
                      prefixIcon: Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
                      border: const OutlineInputBorder(borderRadius: BorderRadius.zero),
                    ),
                  )
                : Container(
                    height: 44,
                    padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
                    decoration: BoxDecoration(border: Border.all(color: cs.outline)),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 18, color: cs.onSurfaceVariant),
                        const SizedBox(width: 8),
                        Text('ابحث بالمحادثات', style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsetsDirectional.only(bottom: 12),
              children: [
                for (final g in groups) ...[
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 4),
                    child: Text(
                      g.label,
                      style: t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700),
                    ),
                  ),
                  for (var i = 0; i < g.items.length; i++)
                    _ThreadTile(
                      g.items[i],
                      selected: selectedId == null ? identical(g, groups.first) && i == 0 : g.items[i].id == selectedId,
                      onOpen: onOpen == null ? null : () => onOpen!(g.items[i].id),
                      onDelete: onDelete == null ? null : () => onDelete!(g.items[i].id),
                    ),
                ],
                if (groups.isEmpty && onSearch != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 24, 16, 0),
                    child: Text('ماكو محادثات.', style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                  ),
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 0),
                  child: Text(
                    'تبقى آخر 50 محادثة على هذا الجهاز فقط، والأقدم تنحذف تلقائياً.',
                    style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  const _ThreadTile(this.item, {this.selected = false, this.onOpen, this.onDelete});
  final AssistantThreadItem item;
  final bool selected;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return InkWell(
      onTap: onOpen,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? cs.secondary.withValues(alpha: 0.10) : null,
          border: BorderDirectional(start: BorderSide(color: selected ? cs.secondary : Colors.transparent, width: 3)),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(13, 9, 8, 9),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isolateLtr(item.title),
                    maxLines: 1,
                    style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isolateLtr(item.preview),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(item.when, style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            IconButton(
              tooltip: 'حذف',
              onPressed: onDelete ?? () {},
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(Icons.delete_outline, size: 18, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// الفقاعة العائمة أثناء الإرشاد (ق23، م3-8): تشير لعنصر في الشاشة الحقيقية.
///
/// تُرسم في طبقة الجولة بدل بطاقة الجولة القديمة حين يبدأ الإرشادَ المساعد.
/// [offRouteTitle] غير الفارغ يحوّلها لسؤال «نكمل من هنا أم نرجع؟» (م3-9).
class AssistantGuideBubble extends StatelessWidget {
  const AssistantGuideBubble({
    super.key,
    required this.step,
    required this.of,
    required this.text,
    this.title,
    this.animateMark = true,
    this.awaitTap = false,
    this.isLast = false,
    this.muted = true,
    this.preparing = false,
    this.offRouteTitle,
    this.onNext,
    this.onEnd,
    this.onToggleMute,
    this.onChat,
    this.onReturn,
    this.onContinueHere,
  });

  final int step;
  final int of;
  final String text;
  final String? title;
  final bool animateMark;
  final bool awaitTap;
  final bool isLast;
  final bool muted;
  final bool preparing;
  final String? offRouteTitle;
  final VoidCallback? onNext;
  final VoidCallback? onEnd;
  final VoidCallback? onToggleMute;
  final VoidCallback? onChat;
  final VoidCallback? onReturn;
  final VoidCallback? onContinueHere;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final off = offRouteTitle;
    final line = off != null
        ? 'فتحت شاشة «$off». نكمل من هنا أم نرجع للخطوة؟'
        : (title == null || title!.isEmpty ? text : '$title\n$text');
    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6)),
          ],
          border: BorderDirectional(
            top: BorderSide(color: cs.secondary, width: 3),
            start: BorderSide(color: cs.outline),
            end: BorderSide(color: cs.outline),
            bottom: BorderSide(color: cs.outline),
          ),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AssistantMark(size: 22, state: AssistantMarkState.speaking, animate: animateMark),
                const SizedBox(width: 10),
                Expanded(child: Text(isolateLtr(line), style: t.textTheme.bodyMedium?.copyWith(height: 1.5))),
                if (onChat != null)
                  IconButton(
                    tooltip: 'رجوع للمحادثة',
                    onPressed: onChat,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    icon: Icon(Icons.chat_bubble_outline_rounded, size: 18, color: cs.onSurfaceVariant),
                  ),
                IconButton(
                  tooltip: muted ? 'تشغيل صوت الإرشاد' : 'كتم صوت الإرشاد',
                  onPressed: onToggleMute ?? () {},
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  icon: Icon(
                    muted ? Icons.volume_off_outlined : Icons.volume_up_outlined,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (off != null)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                children: [
                  TextButton(onPressed: onContinueHere, child: const Text('نكمل من هنا')),
                  FilledButton(onPressed: onReturn, child: const Text('نرجع')),
                ],
              )
            else
              Row(
                children: [
                  Text('خطوة $step من $of', style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: of == 0 ? 0 : step / of,
                      minHeight: 3,
                      color: cs.secondary,
                      backgroundColor: cs.outline.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: onEnd ?? () {}, child: const Text('إنهاء')),
                  if (awaitTap)
                    Flexible(
                      child: Text(
                        'اضغط المظلّل',
                        style: t.textTheme.labelMedium?.copyWith(color: cs.primary, fontWeight: FontWeight.w700),
                      ),
                    )
                  else
                    FilledButton(
                      onPressed: preparing ? null : (onNext ?? () {}),
                      style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
                      child: Text(isLast ? 'تمّ' : 'التالي'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// قائمة رسائل جاهزة للعرض.
class AssistantMessageList extends StatelessWidget {
  const AssistantMessageList({super.key, required this.messages, this.animateMark = true});
  final List<AssistantViewMessage> messages;
  final bool animateMark;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsetsDirectional.fromSTEB(14, 16, 14, 16),
      itemCount: messages.length,
      separatorBuilder: (_, _) => const SizedBox(height: 18),
      itemBuilder: (_, i) => AssistantMessageView(
        messages[i],
        animateMark: animateMark,
        markState: messages[i].status != null ? AssistantMarkState.thinking : AssistantMarkState.idle,
      ),
    );
  }
}

/// شريط التسجيل مكان الحقل أثناء الضغط المطوّل (ط8): نقطة حمراء تنبض، عدّاد، موجة صوت
/// حية، والنص المسموع. «اسحب للإلغاء» و«للأعلى للقفل»، وفي القفل زرّا إلغاء وإرسال.
class AssistantRecordingBar extends StatefulWidget {
  const AssistantRecordingBar({super.key, required this.state, this.text = '', this.onSend, this.onCancel});

  final SpeechHoldState state;
  final String text;
  final VoidCallback? onSend;
  final VoidCallback? onCancel;

  @override
  State<AssistantRecordingBar> createState() => _AssistantRecordingBarState();
}

class _AssistantRecordingBarState extends State<AssistantRecordingBar> with SingleTickerProviderStateMixin {
  static const _bars = 22;
  final _levels = List<double>.filled(_bars, 0.08, growable: true);
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(milliseconds: 110), (_) {
      if (!mounted) return;
      setState(() {
        _levels.removeAt(0);
        _levels.add(math.max(0.08, widget.state.level));
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  String _elapsed() {
    final d = DateTime.now().difference(widget.state.startedAt);
    final m = d.inMinutes.remainder(60).toString();
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final st = widget.state;
    final cancelling = st.cancelProgress;
    final heard = widget.text.trim();
    return Semantics(
      liveRegion: true,
      label: st.locked ? 'يسجّل، مقفل' : 'يسجّل، ارفع إصبعك للإرسال',
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsetsDirectional.fromSTEB(10, 6, 6, 6),
        decoration: BoxDecoration(
          color: Color.lerp(cs.surfaceContainerHighest, cs.errorContainer, cancelling * 0.7),
          border: Border.all(color: cs.error.withValues(alpha: 0.5 + 0.5 * cancelling)),
        ),
        child: Row(
          children: [
            FadeTransition(
              opacity: Tween(begin: 0.35, end: 1.0).animate(_pulse),
              child: Icon(Icons.fiber_manual_record, size: 14, color: cs.error),
            ),
            const SizedBox(width: 6),
            Text(_elapsed(), style: t.textTheme.labelLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 18,
                    child: ExcludeSemantics(
                      child: CustomPaint(
                        size: const Size(double.infinity, 18),
                        painter: _WavePainter(List.of(_levels), cs.brightness == Brightness.dark ? cs.secondary : cs.primary),
                      ),
                    ),
                  ),
                  Text(
                    heard.isNotEmpty
                        ? heard
                        : (st.locked ? 'مقفل — تكلّم براحتك' : (cancelling > 0.5 ? 'اترك للإلغاء' : '‹ اسحب للإلغاء · ⇡ للقفل')),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    textDirection: TextDirection.rtl,
                    style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (st.locked) ...[
              IconButton(
                tooltip: 'إلغاء',
                onPressed: widget.onCancel,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: Icon(Icons.delete_outline_rounded, color: cs.error),
              ),
              IconButton.filled(
                tooltip: 'إرسال',
                onPressed: widget.onSend,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                icon: const Icon(Icons.arrow_upward),
              ),
            ] else
              Opacity(
                opacity: 0.4 + 0.6 * st.lockProgress,
                child: Icon(Icons.lock_outline_rounded, size: 18, color: cs.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.color);
  final List<double> levels;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (levels.isEmpty) return;
    final gap = size.width / levels.length;
    final w = math.max(2.0, gap * 0.55);
    final p = Paint()
      ..color = color
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < levels.length; i++) {
      final h = math.max(2.0, levels[i].clamp(0.0, 1.0) * size.height);
      final x = i * gap + gap / 2;
      canvas.drawLine(Offset(x, (size.height - h) / 2), Offset(x, (size.height + h) / 2), p);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

/// لوحة «أضف صورة» (ط9): صوّر أو اختر من الصور، ثم اختصارات اللوحة والباركود.
/// تُرجع [ImageSourceChoice] أو 'car_photo' أو 'barcode'.
class AssistantAttachSheet extends StatelessWidget {
  const AssistantAttachSheet({super.key, required this.canImage, this.canCarPhoto = false, this.canScan = false});

  final bool canImage;
  final bool canCarPhoto;
  final bool canScan;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    // يمرّر إن قصرت الشاشة أو كبر الخط، فلا يُقص شيء.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('أرسل صورة للمساعد', style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              'صورة منتج أو فاتورة أو لوحة سيارة، وأقرأها لك.',
              style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            if (canImage)
              Row(
                children: [
                  Expanded(
                    child: _BigChoice(
                      icon: Icons.photo_camera_rounded,
                      label: 'صوّر الآن',
                      color: cs.brightness == Brightness.dark ? cs.secondary : cs.primary,
                      onTap: () => Navigator.pop(context, ImageSourceChoice.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BigChoice(
                      icon: Icons.photo_library_rounded,
                      label: 'من الصور',
                      color: cs.tertiary,
                      onTap: () => Navigator.pop(context, ImageSourceChoice.gallery),
                    ),
                  ),
                ],
              ),
            if (canCarPhoto || canScan) const SizedBox(height: 10),
            if (canCarPhoto)
              _SmallChoice(
                icon: Icons.directions_car_outlined,
                title: 'بطاقة غيار من صورة اللوحة',
                subtitle: 'أقرأ اللوحة والعدّاد وتراجعهما أنت',
                onTap: () => Navigator.pop(context, 'car_photo'),
              ),
            if (canScan)
              _SmallChoice(
                icon: Icons.qr_code_scanner_rounded,
                title: 'امسح باركود منتج',
                subtitle: 'يشتغل بدون إنترنت',
                onTap: () => Navigator.pop(context, 'barcode'),
              ),
          ],
        ),
      ),
    );
  }
}

/// مصدر الصورة في [AssistantAttachSheet]، بلا ربط الواجهة بحزمة الكاميرا.
enum ImageSourceChoice { camera, gallery }

class _BigChoice extends StatelessWidget {
  const _BigChoice({required this.icon, required this.label, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: color.withValues(alpha: 0.12),
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 108),
            decoration: BoxDecoration(border: Border.all(color: color.withValues(alpha: 0.55))),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Icon(icon, color: ThemeData.estimateBrightnessForColor(color) == Brightness.dark ? Colors.white : Colors.black, size: 28),
                ),
                const SizedBox(height: 10),
                Text(label, textAlign: TextAlign.center, style: t.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallChoice extends StatelessWidget {
  const _SmallChoice({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
      leading: CircleAvatar(backgroundColor: cs.surfaceContainerHighest, child: Icon(icon, color: cs.onSurface)),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
