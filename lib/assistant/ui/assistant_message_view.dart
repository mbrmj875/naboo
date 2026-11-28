import 'package:flutter/material.dart';

import 'assistant_activity_icons.dart';
import 'assistant_mark.dart';
import 'assistant_typewriter_text.dart';
import 'assistant_view_models.dart';
import 'cards/assistant_card_share.dart';

/// رسالة واحدة (م2-3، م2-4، م2-17).
///
/// سؤال المستخدم فقاعة بلون التطبيق في طرف الصفحة. جواب المساعد بلا فقاعة،
/// بعرض الصفحة، يبدأ برمز صغير، ثم البطاقات، ثم سطر المصدر، ثم الأزرار
/// (نسخ، إعادة، «جواب خاطئ»)، ثم اقتراحات المتابعة.
class AssistantMessageView extends StatelessWidget {
  const AssistantMessageView(
    this.m, {
    super.key,
    this.onFollowup,
    this.onWrong,
    this.onCopy,
    this.onRetry,
    this.onRephrase,
    this.showRephrase = false,
    this.markState = AssistantMarkState.idle,
    this.animateMark = true,
    this.onOpenCard,
    this.onOpenRoute,
    this.shareFinancial = false,
    this.showWrong = true,
    this.showRetry = true,
    this.extra,
  });

  final AssistantViewMessage m;
  final ValueChanged<AssistantCardData>? onOpenCard;

  /// «افتح التقرير نفسه» من سطر المصدر.
  final ValueChanged<String>? onOpenRoute;

  /// البطاقات المالية تُشارك للمالك وحده (ق64).
  final bool shareFinancial;
  final bool showWrong;
  final bool showRetry;

  /// عنصر إضافي تحت الرد (مثل زر بدء جولة مقترحة).
  final Widget? extra;
  final ValueChanged<String>? onFollowup;
  final VoidCallback? onWrong;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;

  /// ط4: «أعد الصياغة» بجانب «نسخ».
  final VoidCallback? onRephrase;
  final bool showRephrase;
  final AssistantMarkState markState;
  final bool animateMark;

  @override
  Widget build(BuildContext context) {
    return m.fromUser ? _user(context) : _assistant(context);
  }

  Widget _user(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final dark = cs.brightness == Brightness.dark;
    // ط1: سؤال المستخدم فقاعة ملوّنة في طرفه، تختلف بوضوح عن بطاقة الجواب في الوضعين.
    final bg = dark ? cs.secondaryContainer : cs.primary;
    final fg = dark ? cs.onSecondaryContainer : cs.onPrimary;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (m.imageBytes != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 4),
                child: Semantics(
                  image: true,
                  label: 'صورة مرفقة',
                  child: Image.memory(
                    m.imageBytes!,
                    width: 160,
                    height: 160,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
              )
            else if (m.imageLabel != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 4),
                child: _ImageThumb(label: m.imageLabel!),
              ),
            if (m.text.isNotEmpty)
              Semantics(
                label: 'سؤالك',
                child: Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 9, 14, 10),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: const BorderRadiusDirectional.only(
                      topStart: Radius.circular(16),
                      topEnd: Radius.circular(16),
                      bottomStart: Radius.circular(16),
                      bottomEnd: Radius.circular(4),
                    ),
                  ),
                  child: Text(
                    isolateLtr(m.text),
                    style: t.textTheme.bodyMedium?.copyWith(
                      color: fg,
                      height: 1.45,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _assistant(BuildContext context) {
    return Semantics(
      liveRegion: m.status == null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ط1: الجواب بطاقة بإطار وخط ذهبي في بدايتها واسم المساعد، فلا يختلط بالسؤال.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 2),
                child: AssistantMark(
                  size: 20,
                  state: markState,
                  animate: animateMark,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _AnswerBubble(m: m)),
            ],
          ),
          _RevealAfterText(
            m: m,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in m.cards) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 30),
                    child: AssistantShareableCard(
                      c,
                      financialAllowed: shareFinancial,
                      onOpen: onOpenCard == null || c.routeId == null
                          ? null
                          : () => onOpenCard!(c),
                    ),
                  ),
                ],
                if (m.source != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(30, 8, 0, 0),
                    child: _SourceLine(
                      summary: m.source!,
                      details: m.sourceDetails,
                      onOpen: m.sourceRoute == null || onOpenRoute == null
                          ? null
                          : () => onOpenRoute!(m.sourceRoute!),
                    ),
                  ),
                if (m.actions && m.status == null)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(22, 2, 0, 0),
                    // يلتف لسطر ثانٍ في الشاشة الضيقة والخط الكبير بدل التجاوز.
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _IconAction(
                          icon: Icons.copy_outlined,
                          label: 'نسخ',
                          onTap: onCopy,
                        ),
                        if (showRephrase)
                          _IconAction(
                            icon: Icons.auto_fix_high_outlined,
                            label: 'أعد الصياغة',
                            onTap: onRephrase,
                          ),
                        if (showRetry)
                          _IconAction(
                            icon: Icons.refresh,
                            label: 'أعد الجواب',
                            onTap: onRetry,
                          ),
                        if (showWrong) _WrongButton(onTap: onWrong),
                      ],
                    ),
                  ),
                if (extra != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(30, 6, 0, 0),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: extra,
                    ),
                  ),
                if (m.choices.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(30, 8, 0, 0),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final c in m.choices)
                          AssistantSuggestionChip(
                            c,
                            icon: Icons.radio_button_unchecked,
                            onTap: () => onFollowup?.call(c),
                          ),
                      ],
                    ),
                  ),
                if (m.followups.isNotEmpty)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(30, 4, 0, 0),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in m.followups)
                          AssistantSuggestionChip(
                            f,
                            onTap: () => onFollowup?.call(f),
                          ),
                      ],
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

/// بطاقة الجواب (ط1): خلفية وإطار وخط ذهبي في البداية، وفيها سطر الحالة المتحرك (ط3)
/// ونص يُكتب تدريجياً (ط5).
class _AnswerBubble extends StatelessWidget {
  const _AnswerBubble({required this.m});
  final AssistantViewMessage m;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final dark = cs.brightness == Brightness.dark;
    final accent = dark ? cs.secondary : cs.primary;
    final hasText = m.text.isNotEmpty;
    return Semantics(
      label: 'جواب المساعد',
      container: true,
      child: Container(
        decoration: BoxDecoration(
          color: dark ? cs.surfaceContainerHigh : cs.surfaceContainerLow,
          border: BorderDirectional(
            start: BorderSide(color: accent, width: 3),
            top: BorderSide(color: cs.outlineVariant),
            end: BorderSide(color: cs.outlineVariant),
            bottom: BorderSide(color: cs.outlineVariant),
          ),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مساعد نابو',
              style: t.textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            if (m.status != null)
              AssistantActivityLine(
                activity: m.activity ?? AssistantActivity.thinking,
                text: m.status!,
              ),
            if (hasText)
              AssistantTypewriterText(
                key: ValueKey('tw-${m.id}'),
                id: m.id ?? m.text.hashCode.toString(),
                text: isolateLtr(m.text.trimRight()),
                animate: m.animateText && m.id != null,
                complete: m.complete,
                style: t.textTheme.bodyLarge?.copyWith(height: 1.55),
              ),
          ],
        ),
      ),
    );
  }
}

/// البطاقات والأزرار تظهر بعد أن ينتهي نص الجواب من الكتابة (ط5).
class _RevealAfterText extends StatelessWidget {
  const _RevealAfterText({required this.m, required this.child});
  final AssistantViewMessage m;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final id = m.id;
    // أثناء العمل لا بطاقات: كانت تظهر مع الأداة ثم تختفي مع بدء النص ثم تعود،
    // فتومض الشاشة وتقفز. تظهر مرة واحدة بعد اكتمال الجواب.
    if (!m.complete) return const SizedBox(width: double.infinity);
    if (!m.animateText || id == null || m.text.isEmpty) return child;
    return ValueListenableBuilder<bool>(
      valueListenable: AssistantReveal.doneOf(id),
      builder: (context, done, _) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        child: done ? child : const SizedBox(width: double.infinity),
      ),
    );
  }
}

/// سطر الحالة الحي: «أفحص المخزون…».
class AssistantStatusLine extends StatelessWidget {
  const AssistantStatusLine(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              value: 0.7,
              color: cs.secondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            text,
            style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class AssistantSuggestionChip extends StatelessWidget {
  const AssistantSuggestionChip(this.text, {super.key, this.onTap, this.icon});
  final String text;
  final VoidCallback? onTap;
  final IconData? icon;

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
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsetsDirectional.fromSTEB(10, 7, 10, 7),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border.all(color: cs.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? Icons.subdirectory_arrow_left,
                size: 14,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  isolateLtr(text),
                  style: t.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final c = t.colorScheme.onSurfaceVariant;
    // أيقونة مع اسمها: «نسخ» و«أعد الصياغة» في صف واحد مقروء (ط4).
    return TextButton.icon(
      onPressed: onTap ?? () {},
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: c,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
      ),
      icon: Icon(icon, size: 17, color: c),
      label: Text(label, style: t.textTheme.labelMedium?.copyWith(color: c)),
    );
  }
}

/// زر «جواب خاطئ» الوحيد (ق42). لا إعجاب ولا «هل أفادك الرد؟».
class _WrongButton extends StatelessWidget {
  const _WrongButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return TextButton.icon(
      onPressed: onTap ?? () {},
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        foregroundColor: cs.onSurfaceVariant,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 8),
      ),
      icon: const Icon(Icons.flag_outlined, size: 16),
      label: Text(
        'جواب خاطئ',
        style: t.textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border.all(color: cs.outline),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_camera_outlined,
            size: 30,
            color: cs.onSurfaceVariant,
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// سطر «من أين هذا؟» مطوي؛ الضغط يفتح التفاصيل وزر التقرير (ق68).
class _SourceLine extends StatefulWidget {
  const _SourceLine({
    required this.summary,
    required this.details,
    this.onOpen,
  });
  final String summary;
  final List<String> details;
  final VoidCallback? onOpen;

  @override
  State<_SourceLine> createState() => _SourceLineState();
}

class _SourceLineState extends State<_SourceLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final small = t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final canOpen = widget.details.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: canOpen,
          label: 'من أين هذا؟',
          child: InkWell(
            onTap: canOpen ? () => setState(() => _open = !_open) : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(isolateLtr(widget.summary), style: small),
                  ),
                  if (canOpen)
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (_open) ...[
          for (final d in widget.details)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 17, top: 2),
              child: Text('• ${isolateLtr(d)}', style: small),
            ),
          if (widget.onOpen != null)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: widget.onOpen,
                child: const Text('افتح التقرير نفسه'),
              ),
            ),
        ],
      ],
    );
  }
}
