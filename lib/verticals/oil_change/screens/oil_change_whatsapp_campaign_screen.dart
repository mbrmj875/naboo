import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/oil_change_whatsapp_config.dart';
import '../../../theme/design_tokens.dart';
import '../../../widgets/inputs/arabic_speech_mic_button.dart';
import '../models/oil_change_campaign_recipient.dart';
import '../models/oil_change_campaign_settings.dart';
import '../services/oil_change_campaign_recipients_repository.dart';
import '../services/oil_change_whatsapp_campaign_queue.dart';
import '../services/oil_change_whatsapp_status_store.dart';
import '../utils/oil_change_campaign_message_renderer.dart';
import '../widgets/oil_change_log_stitch.dart';
import 'oil_change_whatsapp_connect_screen.dart';

/// شاشة إعداد حملة واتساب جماعية — سجل غيارات الزيت.
class OilChangeWhatsappCampaignScreen extends StatefulWidget {
  const OilChangeWhatsappCampaignScreen({
    super.key,
    required this.storeTitle,
    required this.gatewayConnected,
  });

  final String storeTitle;
  final bool gatewayConnected;

  static Future<void> open(
    BuildContext context, {
    required String storeTitle,
    required bool gatewayConnected,
  }) {
    if (!OilChangeWhatsappConfig.campaignUiEnabled) {
      return Future<void>.value();
    }
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => OilChangeWhatsappCampaignScreen(
          storeTitle: storeTitle,
          gatewayConnected: gatewayConnected,
        ),
      ),
    );
  }

  @override
  State<OilChangeWhatsappCampaignScreen> createState() =>
      _OilChangeWhatsappCampaignScreenState();
}

class _OilChangeWhatsappCampaignScreenState
    extends State<OilChangeWhatsappCampaignScreen> {
  final _searchController = TextEditingController();
  final _messageController = TextEditingController(
    text: defaultOilChangeCampaignTemplate(),
  );

  bool _loading = true;
  Object? _error;
  List<OilChangeCampaignRecipient> _all = [];
  final Set<String> _selectedKeys = {};
  OilChangeCampaignSettings _settings = const OilChangeCampaignSettings();
  bool _phonesOnly = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _messageController.addListener(() => setState(() {}));
    unawaited(_loadRecipients());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadRecipients() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows =
          await OilChangeCampaignRecipientsRepository.instance.loadRecipients();
      if (!mounted) return;
      setState(() {
        _all = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  List<OilChangeCampaignRecipient> get _filtered {
    final q = _searchController.text.trim();
    return _all.where((r) {
      if (_phonesOnly && r.phone.trim().isEmpty) return false;
      return oilChangeCampaignMessageMatchesSearch(r, q);
    }).toList();
  }

  int get _selectedCount => _selectedKeys.length;

  String _formatEta(int seconds) {
    if (seconds <= 0) return '—';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m >= 60) {
      final h = m ~/ 60;
      final rm = m % 60;
      return '~$h س ${rm > 0 ? '$rm د' : ''}';
    }
    if (m > 0) return '~$m د ${s > 0 ? '$s ث' : ''}';
    return '~$s ث';
  }

  void _toggleAll(bool? value) {
    final list = _filtered;
    setState(() {
      if (value == true) {
        for (final r in list) {
          _selectedKeys.add(OilChangeCampaignRecipient.phoneKey(r.phone));
        }
      } else {
        for (final r in list) {
          _selectedKeys.remove(OilChangeCampaignRecipient.phoneKey(r.phone));
        }
      }
    });
  }

  void _toggleOne(OilChangeCampaignRecipient r, bool selected) {
    final key = OilChangeCampaignRecipient.phoneKey(r.phone);
    setState(() {
      if (selected) {
        _selectedKeys.add(key);
      } else {
        _selectedKeys.remove(key);
      }
    });
  }

  List<OilChangeCampaignRecipient> _selectedRecipients() {
    final out = <OilChangeCampaignRecipient>[];
    for (final r in _all) {
      final key = OilChangeCampaignRecipient.phoneKey(r.phone);
      if (_selectedKeys.contains(key)) out.add(r);
    }
    out.sort((a, b) => b.orderId.compareTo(a.orderId));
    return out.take(_settings.maxMessages).toList();
  }

  Future<void> _showPreview() async {
    final selected = _selectedRecipients();
    if (selected.isEmpty) {
      _snack('حدّد عميلاً واحداً على الأقل');
      return;
    }
    final sample = selected.first;
    final rendered = renderOilChangeCampaignMessage(
      template: _messageController.text,
      recipient: sample,
      storeTitle: widget.storeTitle,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('معاينة الرسالة'),
        content: SingleChildScrollView(
          child: Text(rendered, textAlign: TextAlign.start),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Future<void> _startCampaign() async {
    if (!widget.gatewayConnected) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('واتساب المحل غير متصل'),
          content: const Text(
            'يجب ربط واتساب المحل قبل إرسال حملة جماعية.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ربط واتساب'),
            ),
          ],
        ),
      );
      if (go == true && mounted) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const OilChangeWhatsappConnectScreen(),
          ),
        );
        await OilChangeWhatsappStatusStore.instance.syncFromCloudIfPossible();
      }
      return;
    }

    final template = _messageController.text.trim();
    if (template.isEmpty) {
      _snack('اكتب نص الرسالة');
      return;
    }
    if (template.length > _settings.maxMessageLength) {
      _snack('الرسالة أطول من ${_settings.maxMessageLength} حرف');
      return;
    }

    final recipients = _selectedRecipients();
    if (recipients.isEmpty) {
      _snack('حدّد عميلاً واحداً على الأقل');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بدء الحملة'),
        content: Text(
          'سيتم تسليم ${recipients.length} رسالة إلى السيرفر، '
          'ثم يُرسلها تلقائياً بفاصل ${_settings.intervalSeconds} ثانية.\n\n'
          'يمكنك إغلاق التطبيق بعد التسليم — الإرسال يكمل على السيرفر.\n'
          'الوقت التقريبي: ${_formatEta(_settings.estimatedSecondsForCount(recipients.length))}',
          textAlign: TextAlign.start,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('إرسال (${recipients.length})'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    HapticFeedback.mediumImpact();
    if (!mounted) return;
    Navigator.of(context).pop();
    unawaited(
      OilChangeWhatsappCampaignQueue.instance.start(
        recipients: recipients,
        messageTemplate: template,
        storeTitle: widget.storeTitle,
        settings: _settings,
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _insertVar(String token) {
    final ctrl = _messageController;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.start >= 0 ? sel.start : text.length;
    final end = sel.end >= 0 ? sel.end : text.length;
    final next = text.replaceRange(start, end, token);
    ctrl.text = next;
    ctrl.selection = TextSelection.collapsed(offset: start + token.length);
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final allFilteredSelected = filtered.isNotEmpty &&
        filtered.every(
          (r) => _selectedKeys.contains(
            OilChangeCampaignRecipient.phoneKey(r.phone),
          ),
        );
    final msgLen = _messageController.text.length;
    final eta = _formatEta(
      _settings.estimatedSecondsForCount(_selectedCount),
    );

    return Scaffold(
      backgroundColor: OilChangeLogStitchMetrics.background,
      appBar: AppBar(
        backgroundColor: OilChangeLogStitchMetrics.primaryContainer,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'حملة واتساب — سجل الغيارات',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 8,
                  color: widget.gatewayConnected
                      ? OilChangeLogStitchMetrics.success
                      : OilChangeLogStitchMetrics.error,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.gatewayConnected
                      ? 'واتساب المحل متصل'
                      : 'واتساب المحل غير متصل',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorBody(onRetry: _loadRecipients)
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          16,
                          8,
                          16,
                          120,
                        ),
                        children: [
                          TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText:
                                  'ابحث بالاسم، الموديل، أو حجم المحرك...',
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: OilChangeLogStitchMetrics
                                    .secondaryContainer
                                    .withValues(alpha: 0.92),
                              ),
                              suffixIcon: _searchController.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear_rounded),
                                      onPressed: _searchController.clear,
                                    )
                                  : null,
                              filled: true,
                              fillColor:
                                  OilChangeLogStitchMetrics.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(999),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              FilterChip(
                                label: const Text('لديه هاتف فقط'),
                                selected: _phonesOnly,
                                onSelected: (v) =>
                                    setState(() => _phonesOnly = v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _SelectionBar(
                            total: filtered.length,
                            selected: _selectedCount,
                            allSelected: allFilteredSelected,
                            onToggleAll: _toggleAll,
                            onClear: () =>
                                setState(_selectedKeys.clear),
                          ),
                          ...filtered.map(
                            (r) => _RecipientTile(
                              recipient: r,
                              selected: _selectedKeys.contains(
                                OilChangeCampaignRecipient.phoneKey(r.phone),
                              ),
                              onChanged: (v) => _toggleOne(r, v),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _MessageCard(
                            controller: _messageController,
                            maxLength: _settings.maxMessageLength,
                            currentLength: msgLen,
                            onInsertVar: _insertVar,
                            onPreview: _showPreview,
                            onSpeechUpdated: () => setState(() {}),
                          ),
                          const SizedBox(height: 12),
                          _SettingsCard(
                            settings: _settings,
                            etaLabel: eta,
                            selectedCount: _selectedCount,
                            onChanged: (s) => setState(() => _settings = s),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'رسالة واحدة لكل عميل — بدون تكرار',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: OilChangeLogStitchMetrics.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _selectedCount > 0 ? _startCampaign : null,
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        OilChangeLogStitchMetrics.secondaryContainer,
                    foregroundColor:
                        OilChangeLogStitchMetrics.onSecondaryContainer,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.chat_rounded, size: 20),
                  label: Text(
                    'إرسال إلى $_selectedCount ${_selectedCount == 1 ? 'عميل' : 'عملاء'}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40),
            const SizedBox(height: 12),
            const Text('تعذّر تحميل قائمة العملاء'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.total,
    required this.selected,
    required this.allSelected,
    required this.onToggleAll,
    required this.onClear,
  });

  final int total;
  final int selected;
  final bool allSelected;
  final ValueChanged<bool?> onToggleAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: OilChangeLogStitchMetrics.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Checkbox(value: allSelected, onChanged: onToggleAll),
          Expanded(
            child: Text(
              'تحديد الكل ($total)',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (selected > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: OilChangeLogStitchMetrics.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'تم $selected',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          if (selected > 0) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onClear, child: const Text('إلغاء')),
          ],
        ],
      ),
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    required this.recipient,
    required this.selected,
    required this.onChanged,
  });

  final OilChangeCampaignRecipient recipient;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? OilChangeLogStitchMetrics.secondaryContainer.withValues(alpha: 0.12)
          : OilChangeLogStitchMetrics.surfaceWhite,
      child: CheckboxListTile(
        value: selected,
        onChanged: (v) => onChanged(v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          recipient.customerName,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${recipient.displayCar} · ${recipient.phone}',
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.start,
        ),
        secondary: Text(
          recipient.lastVisitLabel,
          style: TextStyle(
            fontSize: 10,
            color: OilChangeLogStitchMetrics.textMuted,
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.controller,
    required this.maxLength,
    required this.currentLength,
    required this.onInsertVar,
    required this.onPreview,
    required this.onSpeechUpdated,
  });

  final TextEditingController controller;
  final int maxLength;
  final int currentLength;
  final ValueChanged<String> onInsertVar;
  final VoidCallback onPreview;
  final VoidCallback onSpeechUpdated;

  @override
  Widget build(BuildContext context) {
    final nearLimit = currentLength > maxLength * 0.9;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: OilChangeLogStitchMetrics.panelDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'نص الرسالة',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onPreview,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(
                color: OilChangeLogStitchMetrics.outlineVariant,
              ),
              foregroundColor: OilChangeLogStitchMetrics.primaryContainer,
            ),
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text(
              'معاينة الرسالة قبل الإرسال',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines: 5,
            maxLength: maxLength,
            textAlign: TextAlign.start,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              counterText: '',
              alignLabelWithHint: true,
              suffixIcon: ArabicSpeechMicButton(
                controller: controller,
                onTextUpdated: onSpeechUpdated,
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '$currentLength / $maxLength حرف',
              style: TextStyle(
                fontSize: 11,
                color: nearLimit
                    ? AppColors.accentGold
                    : OilChangeLogStitchMetrics.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: OilChangeCampaignTemplateVars.all
                .map(
                  (v) => ActionChip(
                    label: Text(v, style: const TextStyle(fontSize: 11)),
                    onPressed: () => onInsertVar(v),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.settings,
    required this.etaLabel,
    required this.selectedCount,
    required this.onChanged,
  });

  final OilChangeCampaignSettings settings;
  final String etaLabel;
  final int selectedCount;
  final ValueChanged<OilChangeCampaignSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OilChangeLogStitchMetrics.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'إعدادات الحملة',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          _SettingRow(
            label: 'الحد الأقصى للرسائل',
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: settings.maxMessages > 10
                      ? () => onChanged(
                            settings.copyWith(
                              maxMessages: settings.maxMessages - 10,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.remove, color: Colors.white70),
                ),
                Text(
                  '${settings.maxMessages}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                IconButton(
                  onPressed: settings.maxMessages < 100
                      ? () => onChanged(
                            settings.copyWith(
                              maxMessages: settings.maxMessages + 10,
                            ),
                          )
                      : null,
                  icon: const Icon(Icons.add, color: Colors.white70),
                ),
              ],
            ),
          ),
          _SettingRow(
            label: 'فاصل بين كل رسالة',
            child: Text(
              '${settings.intervalSeconds} ثانية',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          _SettingRow(
            label: 'استراحة تلقائية',
            child: Text(
              '${settings.restMinutes} د بعد كل ${settings.restEveryMessages} رسالة',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: OilChangeLogStitchMetrics.secondaryContainer,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'الوقت التقريبي ($selectedCount): $etaLabel',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
