import 'dart:async';

import 'package:flutter/material.dart';

import '../../../services/print_settings_repository.dart';
import '../models/oil_change_campaign_recipient.dart';
import '../models/oil_change_wa_notify_status.dart';
import '../services/oil_change_campaign_recipients_repository.dart';
import '../services/oil_change_whatsapp_gateway_repository.dart';
import '../services/oil_change_whatsapp_notify_service.dart';
import '../utils/oil_change_whatsapp_user_messages.dart';
import '../widgets/oil_change_log_stitch.dart';

/// قائمة عملاء من سجل الغيار لإعادة إرسال واتساب فردي (للموظفين والمالك).
/// ليست حملة جماعية.
class OilChangeWhatsappResendScreen extends StatefulWidget {
  const OilChangeWhatsappResendScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const OilChangeWhatsappResendScreen(),
      ),
    );
  }

  @override
  State<OilChangeWhatsappResendScreen> createState() =>
      _OilChangeWhatsappResendScreenState();
}

class _OilChangeWhatsappResendScreenState
    extends State<OilChangeWhatsappResendScreen> {
  final _searchController = TextEditingController();
  bool _loading = true;
  Object? _error;
  List<OilChangeCampaignRecipient> _all = [];
  final Set<String> _sendingKeys = {};
  String _shopPhoneDigits = '';
  OilChangeWaResendFilter _filter = OilChangeWaResendFilter.pendingFirst;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final row = await OilChangeWhatsappGatewayRepository.instance
          .fetchForCurrentUser();
      final shop = OilChangeCampaignRecipient.phoneKey(row?.whatsappPhone ?? '');
      final list =
          await OilChangeCampaignRecipientsRepository.instance.loadRecipients();
      if (!mounted) return;
      setState(() {
        _shopPhoneDigits = shop;
        _all = list;
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

  bool _isShopSelf(OilChangeCampaignRecipient r) {
    if (_shopPhoneDigits.isEmpty) return false;
    return OilChangeCampaignRecipient.phoneKey(r.phone) == _shopPhoneDigits;
  }

  List<OilChangeCampaignRecipient> get _filtered {
    var list = _all;
    switch (_filter) {
      case OilChangeWaResendFilter.pendingOnly:
        list = list
            .where((r) => r.waNotifyStatus == OilChangeWaNotifyStatus.pending)
            .toList();
      case OilChangeWaResendFilter.sentOnly:
        list = list
            .where((r) => r.waNotifyStatus == OilChangeWaNotifyStatus.sent)
            .toList();
      case OilChangeWaResendFilter.all:
        break;
      case OilChangeWaResendFilter.pendingFirst:
        list = List<OilChangeCampaignRecipient>.from(list)
          ..sort((a, b) {
            final ap = a.waNotifyStatus == OilChangeWaNotifyStatus.pending
                ? 0
                : 1;
            final bp = b.waNotifyStatus == OilChangeWaNotifyStatus.pending
                ? 0
                : 1;
            if (ap != bp) return ap.compareTo(bp);
            return b.orderId.compareTo(a.orderId);
          });
    }

    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return list;
    return list.where((r) {
      return r.customerName.toLowerCase().contains(q) ||
          r.phone.contains(q) ||
          r.displayCar.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _resend(OilChangeCampaignRecipient recipient) async {
    if (_isShopSelf(recipient)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'هذا رقم واتساب المحل نفسه — اختر زبوناً برقم مختلف من القائمة',
          ),
          duration: Duration(seconds: 6),
        ),
      );
      return;
    }
    final key = OilChangeCampaignRecipient.phoneKey(recipient.phone);
    if (_sendingKeys.contains(key)) return;
    setState(() => _sendingKeys.add(key));
    try {
      final printSettings = await PrintSettingsRepository.instance.load();
      final outcome =
          await OilChangeWhatsappNotifyService.instance.notifyAfterOilChangeSave(
        customerPhone: recipient.phone,
        order: Map<String, dynamic>.from(recipient.orderRow),
        printSettings: printSettings,
        orderId: recipient.orderId,
      );
      if (!mounted) return;
      final newStatus = waNotifyStatusFromOutcome(outcome);
      setState(() {
        _all = [
          for (final r in _all)
            if (r.orderId == recipient.orderId)
              r.copyWith(waNotifyStatus: newStatus)
            else
              r,
        ];
      });
      final msg = OilChangeWhatsappUserMessages.snackbarForOutcome(outcome);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: Duration(seconds: outcome.isSent ? 3 : 6),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingKeys.remove(key));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final filtered = _filtered;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: OilChangeLogStitchMetrics.background,
        appBar: AppBar(
          title: const Text('إعادة إرسال واتساب'),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              onPressed: _loading ? null : () => unawaited(_load()),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'بحث بالاسم أو الرقم أو السيارة',
                  prefixIcon: const Icon(Icons.search_rounded),
                  filled: true,
                  fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'الأهم أولاً',
                      selected:
                          _filter == OilChangeWaResendFilter.pendingFirst,
                      onTap: () => setState(
                        () => _filter = OilChangeWaResendFilter.pendingFirst,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'لم يُرسل',
                      selected: _filter == OilChangeWaResendFilter.pendingOnly,
                      onTap: () => setState(
                        () => _filter = OilChangeWaResendFilter.pendingOnly,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'تم الإرسال',
                      selected: _filter == OilChangeWaResendFilter.sentOnly,
                      onTap: () => setState(
                        () => _filter = OilChangeWaResendFilter.sentOnly,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _FilterChip(
                      label: 'الكل',
                      selected: _filter == OilChangeWaResendFilter.all,
                      onTap: () => setState(
                        () => _filter = OilChangeWaResendFilter.all,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 8),
              child: Text(
                'اضغط على عميل لإعادة إرسال رسالة واتساب من رقم المحل.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ),
            Expanded(child: _buildBody(cs, filtered)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, List<OilChangeCampaignRecipient> filtered) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('تعذّر تحميل القائمة', style: TextStyle(color: cs.error)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => unawaited(_load()),
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _all.isEmpty
              ? 'لا يوجد عملاء برقم هاتف في سجل الغيارات'
              : 'لا نتائج لهذا الفلتر أو البحث',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 24),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final r = filtered[index];
        final key = OilChangeCampaignRecipient.phoneKey(r.phone);
        final busy = _sendingKeys.contains(key);
        final self = _isShopSelf(r);
        return Material(
          color: self
              ? cs.errorContainer.withValues(alpha: 0.35)
              : OilChangeLogStitchMetrics.surfaceWhite,
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: busy
                ? const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    self ? Icons.warning_amber_rounded : Icons.chat_rounded,
                    color: self ? cs.error : cs.primary,
                  ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    self ? '${r.customerName} (رقم المحل)' : r.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                if (!self) _StatusBadge(status: r.waNotifyStatus),
              ],
            ),
            subtitle: Text(
              self
                  ? '${r.phone}\nلا يُرسل لنفس رقم واتساب المحل — اختر زبوناً آخر'
                  : '${r.phone}\n${r.displayCar} · ${r.lastVisitLabel}',
            ),
            isThreeLine: true,
            trailing: self ? null : const Icon(Icons.send_rounded),
            onTap: busy ? null : () => unawaited(_resend(r)),
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      selectedColor: cs.primary.withValues(alpha: 0.18),
      labelStyle: TextStyle(
        color: selected ? cs.primary : cs.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final OilChangeWaNotifyStatus status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      OilChangeWaNotifyStatus.pending => (
          cs.errorContainer,
          cs.onErrorContainer,
        ),
      OilChangeWaNotifyStatus.sent => (
          const Color(0xFFD1FAE5),
          const Color(0xFF065F46),
        ),
      OilChangeWaNotifyStatus.blocked => (
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
        ),
      OilChangeWaNotifyStatus.notApplicable => (
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant,
        ),
      OilChangeWaNotifyStatus.unknown => (
          cs.surfaceContainerHighest,
          cs.onSurfaceVariant,
        ),
    };
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.labelAr,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
