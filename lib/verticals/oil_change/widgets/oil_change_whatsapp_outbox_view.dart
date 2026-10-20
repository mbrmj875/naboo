import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/oil_change_whatsapp_notify_outcome.dart';
import '../services/oil_change_whatsapp_outbox.dart';
import '../utils/whatsapp_failure_reason_ar.dart';

/// البطاقات التي حُفظت وفشلت رسالتها — تُعاد بضغطة بعد عودة الإنترنت.
class OilChangeWhatsappOutboxView extends StatefulWidget {
  const OilChangeWhatsappOutboxView({
    super.key,
    this.onChanged,
    this.embedInParentScroll = false,
  });

  /// يُستدعى بعد كل نجاح أو إسقاط لتحديث العدّاد في الشاشة الأم.
  final VoidCallback? onChanged;

  /// عند true: قائمة مدمجة بلا Expanded/RefreshIndicator داخلي (قسم داخل تبويب).
  final bool embedInParentScroll;

  @override
  State<OilChangeWhatsappOutboxView> createState() =>
      OilChangeWhatsappOutboxViewState();
}

class OilChangeWhatsappOutboxViewState
    extends State<OilChangeWhatsappOutboxView> {
  final _outbox = OilChangeWhatsappOutbox.instance;
  final _dateFormat = DateFormat('d MMMM · h:mm a', 'ar_SA');

  List<OilChangeOutboxEntry> _entries = const [];
  bool _loading = true;
  bool _sendingAll = false;
  Object? _error;
  int? _busyId;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  Future<void> reload() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final rows = await _outbox.loadPending();
      if (!mounted) return;
      setState(() {
        _entries = rows;
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

  Future<void> _retryOne(OilChangeOutboxEntry entry) async {
    setState(() => _busyId = entry.id);
    // يدوي يتجاوز nextAttemptAt عن قصد؛ المفتاح يبقى عند timeout/noInternet
    // (وبعد فشل مؤكد يُدوَّر المفتاح داخل Outbox عند _markAttempt).
    final reason = await _outbox.retry(entry);
    if (!mounted) return;
    setState(() => _busyId = null);
    _showResult(entry, reason);
    await reload();
    widget.onChanged?.call();
  }

  Future<void> _retryAll() async {
    if (_entries.isEmpty) return;
    setState(() => _sendingAll = true);
    var sent = 0;
    var failed = 0;
    for (final entry in List.of(_entries)) {
      // إرسال الكل = إعادة آمنة لنفس العملية (ليس forceNewAttempt).
      final reason = await _outbox.retry(entry);
      if (reason == OilChangeWhatsappNotifyReason.sent) {
        sent++;
      } else {
        failed++;
      }
    }
    if (!mounted) return;
    setState(() => _sendingAll = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? 'أُرسلت $sent رسالة'
              : 'أُرسلت $sent، وبقيت $failed لم تُرسل',
        ),
      ),
    );
    await reload();
    widget.onChanged?.call();
  }

  Future<void> _discard(OilChangeOutboxEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إسقاط الرسالة'),
        content: Text(
          'لن تُرسل رسالة بطاقة ${entry.customerName.isEmpty ? entry.customerPhone : entry.customerName}. '
          'البطاقة نفسها تبقى محفوظة في السجل.',
          textAlign: TextAlign.start,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إسقاط'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _outbox.discard(entry.id);
    await reload();
    widget.onChanged?.call();
  }

  void _showResult(
    OilChangeOutboxEntry entry,
    OilChangeWhatsappNotifyReason reason,
  ) {
    final ok = reason == OilChangeWhatsappNotifyReason.sent;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'وصلت الرسالة إلى ${entry.customerPhone}'
              : 'ما زالت لم تُرسل: ${_reasonAr(reason)}',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  String _reasonAr(OilChangeWhatsappNotifyReason reason) {
    return WhatsappFailureReasonAr.parse(
      reason.name,
      fromLocalOutbox: true,
    ).messageAr;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'تعذّر قراءة الرسائل المعلّقة',
                style: TextStyle(fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => unawaited(reload()),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return const _OutboxEmptyState(compact: true);
    }

    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_entries.length} رسالة معلّقة على الجهاز',
              style: const TextStyle(fontWeight: FontWeight.w700),
              textAlign: TextAlign.start,
            ),
          ),
          FilledButton.icon(
            onPressed: _sendingAll ? null : () => unawaited(_retryAll()),
            icon: _sendingAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: const Text('إرسال الكل'),
          ),
        ],
      ),
    );

    if (widget.embedInParentScroll) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          for (var i = 0; i < _entries.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 0),
              child: _buildTile(_entries[i]),
            ),
          ],
          const SizedBox(height: 8),
        ],
      );
    }

    return Column(
      children: [
        header,
        Expanded(
          child: RefreshIndicator(
            onRefresh: reload,
            child: ListView.separated(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 28),
              itemCount: _entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => _buildTile(_entries[index]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTile(OilChangeOutboxEntry entry) {
    final theme = Theme.of(context);
    final busy = _busyId == entry.id || _sendingAll;
    final name = entry.customerName.trim();
    final failure = WhatsappFailureReasonAr.parse(
      entry.reason,
      fromLocalOutbox: true,
    );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.error.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.isNotEmpty ? '$name · ${entry.customerPhone}' : entry.customerPhone,
              style: const TextStyle(fontWeight: FontWeight.w700),
              textAlign: TextAlign.start,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '${failure.messageAr} · ${_dateFormat.format(entry.createdAt)}'
              '${entry.attempts > 1 ? ' · ${entry.attempts} محاولات' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              textAlign: TextAlign.start,
            ),
            if (failure.fixAr.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'الحل: ${failure.fixAr}',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.start,
              ),
            ],
            if (entry.employeeName.isNotEmpty)
              Text(
                'الفني: ${entry.employeeName}',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.start,
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: busy ? null : () => unawaited(_discard(entry)),
                  child: const Text('إسقاط'),
                ),
                TextButton.icon(
                  onPressed: busy ? null : () => unawaited(_retryOne(entry)),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('إعادة الإرسال'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OutboxEmptyState extends StatelessWidget {
  const _OutboxEmptyState({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(compact ? 16 : 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) const SizedBox(height: 40),
          Icon(
            Icons.mark_email_read_outlined,
            size: compact ? 40 : 56,
            color: Theme.of(context).hintColor,
          ),
          const SizedBox(height: 12),
          const Text(
            'لا توجد رسائل معلّقة على الجهاز',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'إذا انقطع الإنترنت أثناء الحفظ تُحفظ الرسالة هنا لترسلها عند عودة الاتصال.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
