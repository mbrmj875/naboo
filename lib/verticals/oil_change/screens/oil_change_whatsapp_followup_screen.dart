import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../navigation/content_navigation.dart';
import '../../../theme/design_tokens.dart';
import '../models/wa_oil_followup_job.dart';
import '../models/wa_oil_followup_rule.dart';
import '../services/wa_oil_followup_copy.dart';
import '../services/wa_oil_followup_service.dart';
import '../widgets/oil_change_form_theme.dart';

/// تذكير واتساب بعد غيار الزيت — مدة + نص + قالب ميتا.
class OilChangeWhatsappFollowupScreen extends StatefulWidget {
  const OilChangeWhatsappFollowupScreen({
    super.key,
    required this.isOfficialTransport,
  });

  final bool isOfficialTransport;

  static Future<void> open(
    BuildContext context, {
    required bool isOfficialTransport,
  }) {
    return Navigator.of(context).push<void>(
      FastContentPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => OilChangeWhatsappFollowupScreen(
          isOfficialTransport: isOfficialTransport,
        ),
      ),
    );
  }

  @override
  State<OilChangeWhatsappFollowupScreen> createState() =>
      _OilChangeWhatsappFollowupScreenState();
}

class _OilChangeWhatsappFollowupScreenState
    extends State<OilChangeWhatsappFollowupScreen> {
  WaOilFollowupSnapshot? _snap;
  Object? _error;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  late WaOilFollowupRule _draft;
  final _messageController = TextEditingController();
  final _dateFmt = DateFormat('EEEE d MMMM', 'ar_SA');

  @override
  void initState() {
    super.initState();
    _draft = WaOilFollowupRule.defaults();
    _messageController.addListener(() {
      _dirty = true;
      if (mounted) setState(() {});
    });
    unawaited(_reload());
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await WaOilFollowupService.instance.load(
        isOfficialTransport: widget.isOfficialTransport,
      );
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _draft = snap.rule.clampDelay();
        _messageController.text = snap.rule.bodyTemplate;
        _loading = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<bool> _onWillPop() async {
    if (!_dirty) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغييرات غير محفوظة'),
        content: const Text('تريد تتجاهل تعديل المدة أو النص؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تجاهل'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  Future<void> _save({bool submitMeta = false}) async {
    if (_saving) return;
    final body = _messageController.text.trim();
    if (body.isEmpty) {
      _showSnack('اكتب نص الرسالة أولاً.');
      return;
    }
    setState(() => _saving = true);
    try {
      final rule = WaOilFollowupRule(
        enabled: _draft.enabled,
        delayValue: _draft.delayValue,
        delayUnit: _draft.delayUnit,
        quietHours: _draft.quietHours,
        bodyTemplate: body,
      ).clampDelay();
      await WaOilFollowupService.instance.saveRule(rule);
      if (submitMeta && widget.isOfficialTransport) {
        final sub = await WaOilFollowupService.instance.submitTemplateToMeta(
          body,
        );
        if (!sub.ok) {
          _showSnack(sub.messageAr ?? 'تعذّر إرسال القالب.');
          await _reload();
          return;
        }
        _showSnack(sub.messageAr ?? 'انرسل القالب لواتساب.');
      } else {
        _showSnack('انحفظ التذكير.');
      }
      await _reload();
    } catch (_) {
      _showSnack('تعذّر حفظ التذكير. أعد المحاولة.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _bumpDelay(int dir) {
    final lim = _draft.delayUnit.limits;
    var v = _draft.delayValue + dir;
    if (v < lim.min) v = lim.min;
    if (v > lim.max) v = lim.max;
    if (v == _draft.delayValue) return;
    HapticFeedback.selectionClick();
    setState(() {
      _draft = WaOilFollowupRule(
        enabled: _draft.enabled,
        delayValue: v,
        delayUnit: _draft.delayUnit,
        quietHours: _draft.quietHours,
        bodyTemplate: _messageController.text,
      );
      _dirty = true;
    });
  }

  void _insertVar(String token) {
    final c = _messageController;
    final text = c.text;
    final sel = c.selection;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final next = text.replaceRange(start, end, token);
    c.text = next;
    c.selection = TextSelection.collapsed(offset: start + token.length);
    _dirty = true;
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: OilChangeFormTheme.wrap(context, base),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          if (await _onWillPop() && context.mounted) {
            Navigator.of(context).pop();
          }
        },
        child: Builder(
          builder: (context) {
            return Scaffold(
              backgroundColor: Theme.of(context).colorScheme.surface,
              appBar: OilChangeFormTheme.appBar(
                context: context,
                title: 'تذكير الزبون بعد الغيار',
                actions: [
                  IconButton(
                    tooltip: 'تحديث',
                    onPressed: _loading ? null : () => unawaited(_reload()),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? _ErrorBody(onRetry: () => unawaited(_reload()))
                      : _buildBody(context),
              bottomNavigationBar: _loading || _error != null
                  ? null
                  : _buildBottomBar(context),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final snap = _snap!;
    final pending = snap.templateStatus == WaFollowupTemplateUiStatus.pending &&
        (snap.templateLastError == null || snap.templateLastError!.trim().isEmpty);
    final needMeta = widget.isOfficialTransport &&
        (snap.templateStatus == WaFollowupTemplateUiStatus.draft ||
            snap.templateStatus == WaFollowupTemplateUiStatus.rejected ||
            _dirty);
    final label = needMeta
        ? 'إرسال القالب للمراجعة'
        : pending
            ? 'القالب قيد المراجعة'
            : 'حفظ التذكير';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton(
              onPressed: _saving || pending
                  ? null
                  : () => unawaited(_save(submitMeta: needMeta)),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppColors.primary,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(
                      label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              'الغيارات القديمة ما تتغيّر. القاعدة تطبق على الغيارات الجديدة.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: OilChangeFormTheme.secondaryText(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final snap = _snap!;
    if (snap.schemaMissing) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'التذكير التلقائي غير مفعّل على هذا الحساب بعد.',
            textAlign: TextAlign.center,
            style: TextStyle(color: OilChangeFormTheme.secondaryText(context)),
          ),
        ),
      );
    }

    final summary =
        'بعد كل غيار، الرسالة تروح بعد ${_draft.delayUnit.labelAr(_draft.delayValue)}.';

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 24),
      children: [
        _HeroCard(
          enabled: _draft.enabled,
          canSend: snap.canSendFollowups,
          templateStatus: snap.templateStatus,
          onToggle: (v) => setState(() {
            _draft = WaOilFollowupRule(
              enabled: v,
              delayValue: _draft.delayValue,
              delayUnit: _draft.delayUnit,
              quietHours: _draft.quietHours,
              bodyTemplate: _messageController.text,
            );
            _dirty = true;
          }),
        ),
        const SizedBox(height: 18),
        const _SectionLabel(text: 'متى نرسل الرسالة؟'),
        const SizedBox(height: 10),
        _DelayCard(
          value: _draft.delayValue,
          unit: _draft.delayUnit,
          summary: summary,
          onMinus: () => _bumpDelay(-1),
          onPlus: () => _bumpDelay(1),
          onUnit: (u) => setState(() {
            _draft = WaOilFollowupRule(
              enabled: _draft.enabled,
              delayValue: _draft.clampDelay().delayValue,
              delayUnit: u,
              quietHours: _draft.quietHours,
              bodyTemplate: _messageController.text,
            ).clampDelay();
            _dirty = true;
          }),
        ),
        const SizedBox(height: 18),
        const _SectionLabel(text: 'ماذا نقول للزبون؟'),
        const SizedBox(height: 10),
        _MessageCard(
          controller: _messageController,
          preview: WaOilFollowupCopy.preview(template: _messageController.text),
          onInsert: _insertVar,
          onRestore: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('نرجع النص المقترح؟'),
                content: const Text('هذا يمسح تعديلك الحالي في الصندوق.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('تراجع'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('نعم، أرجعه'),
                  ),
                ],
              ),
            );
            if (ok == true) {
              setState(() {
                _messageController.text = WaOilFollowupCopy.defaultBodyForUnit(
                  _draft.delayUnit,
                );
                _dirty = true;
              });
            }
          },
        ),
        const SizedBox(height: 16),
        _MetaStatusCard(
          isOfficial: widget.isOfficialTransport,
          status: snap.templateStatus,
          lastError: snap.templateLastError,
        ),
        const SizedBox(height: 18),
        const _SectionLabel(text: 'التذكيرات القادمة'),
        const SizedBox(height: 10),
        if (snap.upcoming.isEmpty)
          const _EmptyUpcoming()
        else
          ...snap.upcoming.map(
            (j) => _UpcomingTile(job: j, dateFmt: _dateFmt),
          ),
      ],
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.enabled,
    required this.canSend,
    required this.templateStatus,
    required this.onToggle,
  });

  final bool enabled;
  final bool canSend;
  final WaFollowupTemplateUiStatus templateStatus;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final accent = !enabled
        ? OilChangeFormTheme.gold
        : canSend
            ? AppSemanticColors.success
            : AppSemanticColors.info;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            accent.withValues(alpha: 0.14),
            AppColors.primary.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.16),
            ),
            child: Icon(Icons.schedule_send_rounded, color: accent, size: 32),
          ),
          const SizedBox(height: 12),
          Text(
            'بعد كل غيار زيت',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: OilChangeFormTheme.emphasisText(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'نرسل للزبون واتساب في الوقت اللي تحدّده أنت.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OilChangeFormTheme.secondaryText(context),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  enabled ? 'التذكير يعمل' : 'التذكير متوقف',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: OilChangeFormTheme.emphasisText(context),
                  ),
                ),
              ),
              Switch.adaptive(value: enabled, onChanged: onToggle),
            ],
          ),
          if (enabled && templateStatus == WaFollowupTemplateUiStatus.pending)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'بانتظار موافقة واتساب على القالب.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: OilChangeFormTheme.secondaryText(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DelayCard extends StatelessWidget {
  const _DelayCard({
    required this.value,
    required this.unit,
    required this.summary,
    required this.onMinus,
    required this.onPlus,
    required this.onUnit,
  });

  final int value;
  final WaOilFollowupDelayUnit unit;
  final String summary;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<WaOilFollowupDelayUnit> onUnit;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: OilChangeFormTheme.gold.withValues(alpha: 0.35),
        ),
        color: OilChangeFormTheme.gold.withValues(alpha: 0.06),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _RoundBtn(icon: Icons.remove, onTap: onMinus),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  '$value',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              _RoundBtn(icon: Icons.add, onTap: onPlus),
            ],
          ),
          const SizedBox(height: 12),
          _UnitRow(selected: unit, onUnit: onUnit),
          const SizedBox(height: 12),
          Text(
            summary,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
          ),
          const SizedBox(height: 6),
          Text(
            'ما نرسل في الليل؛ نأخّرها للصباح.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              color: OilChangeFormTheme.secondaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitRow extends StatelessWidget {
  const _UnitRow({required this.selected, required this.onUnit});

  final WaOilFollowupDelayUnit selected;
  final ValueChanged<WaOilFollowupDelayUnit> onUnit;

  @override
  Widget build(BuildContext context) {
    const units = WaOilFollowupDelayUnit.values;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final u in units) ...[
            _UnitChip(
              label: _label(u),
              selected: u == selected,
              onTap: () => onUnit(u),
            ),
            if (u != units.last) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  String _label(WaOilFollowupDelayUnit u) {
    switch (u) {
      case WaOilFollowupDelayUnit.hour:
        return 'ساعة';
      case WaOilFollowupDelayUnit.day:
        return 'يوم';
      case WaOilFollowupDelayUnit.week:
        return 'أسبوع';
      case WaOilFollowupDelayUnit.month:
        return 'شهر';
      case WaOilFollowupDelayUnit.year:
        return 'سنة';
    }
  }
}

class _UnitChip extends StatelessWidget {
  const _UnitChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: selected
                  ? Colors.white
                  : OilChangeFormTheme.emphasisText(context),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.controller,
    required this.preview,
    required this.onInsert,
    required this.onRestore,
  });

  final TextEditingController controller;
  final String preview;
  final ValueChanged<String> onInsert;
  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: OilChangeFormTheme.gold.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: WaOilFollowupVars.chipLabels.entries
                .map(
                  (e) => ActionChip(
                    label: Text(e.value),
                    onPressed: () => onInsert(e.key),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            minLines: 6,
            maxLines: 12,
            decoration: OilChangeFormTheme.field(
              context: context,
              labelText: 'نص الرسالة',
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${WaOilFollowupCopy.renderedLength(controller.text)} حرف',
            style: TextStyle(
              fontSize: 12,
              color: OilChangeFormTheme.secondaryText(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'هكذا يراها الزبون',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: OilChangeFormTheme.emphasisText(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(preview, textAlign: TextAlign.start),
          ),
          TextButton(
            onPressed: onRestore,
            child: const Text('استعد نص نابو المقترح'),
          ),
        ],
      ),
    );
  }
}

class _MetaStatusCard extends StatelessWidget {
  const _MetaStatusCard({
    required this.isOfficial,
    required this.status,
    this.lastError,
  });

  final bool isOfficial;
  final WaFollowupTemplateUiStatus status;
  final String? lastError;

  @override
  Widget build(BuildContext context) {
    if (!isOfficial) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: OilChangeFormTheme.gold.withValues(alpha: 0.1),
          border: Border.all(
            color: OilChangeFormTheme.gold.withValues(alpha: 0.35),
          ),
        ),
        child: const Text(
          'الربط بمسح الرمز: الرسالة تُرسل كما كتبتها، من غير مراجعة ميتا. '
          'قد ينقطع الإرسال إن انفصل واتساب قبل الموعد.',
          style: TextStyle(height: 1.35, fontWeight: FontWeight.w600),
        ),
      );
    }

    final (title, body, color) = switch (status) {
      WaFollowupTemplateUiStatus.approved => (
          'تم اعتماد القالب',
          'التذكير يشتغل من الآن على الغيارات الجديدة.',
          AppSemanticColors.success,
        ),
      WaFollowupTemplateUiStatus.pending => (
          'القالب قيد المراجعة عند واتساب',
          'أرسلنا القالب لواتساب. المراجعة تاخذ من دقائق إلى يومين. '
              'ما نقدر نرسل تذكير للزبون قبل الاعتماد.',
          AppSemanticColors.info,
        ),
      WaFollowupTemplateUiStatus.rejected => (
          'ميتا رفضت القالب',
          lastError?.trim().isNotEmpty == true
              ? lastError!
              : 'غالباً لأن النص ترويجي أو فيه رابط. قصّر الجملة وجرّب بدون عرض.',
          Theme.of(context).colorScheme.error,
        ),
      _ => (
          'مسودة — لسه ما انرسل لواتساب',
          'اضغط الزر بالأسفل حتى نرفع النص للمراجعة.',
          OilChangeFormTheme.gold,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        color: color.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(height: 1.35)),
        ],
      ),
    );
  }
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.job, required this.dateFmt});

  final WaOilFollowupJob job;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    final j = job;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${j.customerName} · ${j.carLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  dateFmt.format(j.dueAt),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: OilChangeFormTheme.secondaryText(context),
                  ),
                ),
              ],
            ),
          ),
          Text(
            j.statusAr,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: OilChangeFormTheme.accentText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyUpcoming extends StatelessWidget {
  const _EmptyUpcoming();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Text(
        'ماكو تذكير مجدول بعد. ينحفظ تلقائي بعد أول غيار والقاعدة شغّالة.',
        textAlign: TextAlign.center,
        style: TextStyle(color: OilChangeFormTheme.secondaryText(context)),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: OilChangeFormTheme.gold.withValues(alpha: 0.14),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 52,
          height: 52,
          child: Icon(icon, color: OilChangeFormTheme.gold),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 16,
        color: OilChangeFormTheme.emphasisText(context),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('تعذّر تحميل التذكير'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}
