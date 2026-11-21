import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/cash_ledger_audit.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import '../../verticals/oil_change/widgets/oil_change_owner_pin_confirm_dialog.dart';

final _numFmt = NumberFormat('#,##0', 'en');
final _dateFmt = DateFormat('dd/MM/yyyy', 'en');

String _iqd(int fils) => '${_numFmt.format(fils / 1000.0)} د.ع';

/// فحص قيود الصندوق الزائدة (المرحلة 5 — الشريحة 5). الفحص لا يغيّر شيئاً؛
/// التصحيح قيد سالب لكل حالة بقرار المالك وبرمزه.
class CashLedgerAuditScreen extends StatefulWidget {
  const CashLedgerAuditScreen({super.key});

  @override
  State<CashLedgerAuditScreen> createState() => _CashLedgerAuditScreenState();
}

class _CashLedgerAuditScreenState extends State<CashLedgerAuditScreen> {
  CashAuditReport? _report;
  String? _error;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _report = null;
      _error = null;
    });
    try {
      final r = await DatabaseHelper().auditCashLedgerExcess();
      if (mounted) setState(() => _report = r);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _apply() async {
    final r = _report;
    if (r == null || r.isClean || _applying) return;
    final ok = await confirmOwnerPinForSensitiveAction(
      context,
      title: 'تصحيح الصندوق',
      message:
          'سيُضاف ${r.findings.length} قيد سالب مجموعها ${_iqd(r.totalExcessFils)}، '
          'فينقص رصيد الصندوق بهذا المبلغ. القيود الأصلية تبقى كما هي.',
      confirmLabel: 'إضافة قيود التصحيح',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _applying = true);
    try {
      var user = '';
      try {
        user = context.read<AuthProvider>().username;
      } catch (_) {}
      final n = await DatabaseHelper().applyCashAuditCorrections(
        r.findings,
        byUserName: user,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('أُضيف $n قيد تصحيح.')),
      );
      await _load();
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _report;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('فحص قيود الصندوق')),
        body: _error != null
            ? Center(child: Text('تعذّر الفحص: $_error'))
            : r == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'يبحث عن قيود زادت رصيد الصندوق بغير حق بسبب خللين قديمين '
                    'أُصلحا: عكس دفعة المورد القديم، وتسديد دين على فاتورة آجلة '
                    'بلا عربون كان يُحسب مرتين. الفحص لا يغيّر شيئاً.',
                    style: TextStyle(color: cs.onSurfaceVariant, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  if (r.isClean)
                    Container(
                      key: const Key('cashAuditClean'),
                      padding: const EdgeInsets.all(16),
                      color: AppSemanticColors.success.withValues(alpha: 0.12),
                      child: const Text(
                        'لا قيود زائدة. الصندوق سليم من هذين الخللين.',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    )
                  else ...[
                    Text(
                      'زيادة غير حقيقية: ${_iqd(r.totalExcessFils)} '
                      'في ${r.findings.length} قيد',
                      key: const Key('cashAuditTotal'),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: cs.error,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final f in r.findings)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            '${_iqd(f.excessFils)} · ${f.kindLabel}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text('${_dateFmt.format(f.date)} · ${f.label}'),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('cashAuditApply'),
                      onPressed: _applying ? null : _apply,
                      icon: const Icon(Icons.rule_rounded),
                      label: Text(
                        'إضافة قيود التصحيح (${_iqd(r.totalExcessFils)})',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'قبل التصحيح: عُدّ النقد الفعلي في الدرج. إن كان رصيد التطبيق '
                      'أعلى منه بقريب من هذا المبلغ فالتصحيح صحيح.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
