import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';

import '../../models/debt_settings_data.dart';
import '../../providers/notification_provider.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import '../../utils/screen_layout.dart';

final _numFmt = NumberFormat('#,##0', 'en');

/// حدود بيع «دين / آجل» — هوية بصرية موحّدة مع باقي التطبيق.
class DebtSettingsScreen extends StatefulWidget {
  const DebtSettingsScreen({super.key});

  @override
  State<DebtSettingsScreen> createState() => _DebtSettingsScreenState();
}

class _DebtSettingsScreenState extends State<DebtSettingsScreen> {
  final _db = DatabaseHelper();
  bool _loading = true;
  DebtSettingsData _data = DebtSettingsData.defaults();

  final _maxPerCustomer = TextEditingController();
  final _maxPerInvoice = TextEditingController();
  final _warnDays = TextEditingController();

  Color get _pageBg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _primary => Theme.of(context).colorScheme.primary;
  Color get _onPrimary => Theme.of(context).colorScheme.onPrimary;
  Color get _filterBg => Theme.of(context).colorScheme.surfaceContainerHighest;
  Color get _textPrimary => Theme.of(context).colorScheme.onSurface;
  Color get _textSecondary => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _outline => Theme.of(context).colorScheme.outline;

  InputDecoration _fieldDecoration({
    required String label,
    String? helper,
    int? helperMaxLines,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: helperMaxLines ?? 2,
      filled: true,
      fillColor: _filterBg,
      isDense: true,
      prefixIcon: prefixIcon,
      border: OutlineInputBorder(
        borderRadius: AppShape.none,
        borderSide: BorderSide(color: _outline.withValues(alpha: 0.55)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppShape.none,
        borderSide: BorderSide(color: _outline.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppShape.none,
        borderSide: BorderSide(color: _primary, width: 1.5),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _maxPerCustomer.dispose();
    _maxPerInvoice.dispose();
    _warnDays.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await _db.getDebtSettings();
    if (!mounted) return;
    setState(() {
      _data = s;
      _maxPerCustomer.text = s.maxTotalOpenDebtPerCustomer <= 0
          ? ''
          : _numFmt.format(s.maxTotalOpenDebtPerCustomer);
      _maxPerInvoice.text = s.maxOpenRemainingPerInvoice <= 0
          ? ''
          : _numFmt.format(s.maxOpenRemainingPerInvoice);
      _warnDays.text = s.warnDebtAgeDays <= 0 ? '' : '${s.warnDebtAgeDays}';
      _loading = false;
    });
  }

  double _parseMoney(String raw) {
    final v = double.tryParse(raw.replaceAll(',', '').trim());
    if (v == null || v.isNaN || v < 0) return 0;
    return v;
  }

  Future<void> _save() async {
    final capC = _parseMoney(_maxPerCustomer.text);
    final capI = _parseMoney(_maxPerInvoice.text);
    final days = int.tryParse(_warnDays.text.trim()) ?? 0;
    if (days < 0 || days > 36500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أيام التحذير: بين 0 و 36500')),
      );
      return;
    }
    final next = _data.copyWith(
      maxTotalOpenDebtPerCustomer: capC,
      maxOpenRemainingPerInvoice: capI,
      warnDebtAgeDays: days,
    );
    await _db.saveDebtSettings(next);
    CloudSyncService.instance.scheduleSyncSoon();
    if (!mounted) return;
    try {
      unawaited(context.read<NotificationProvider>().refresh());
    } catch (_) {}
    setState(() => _data = next);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم حفظ إعدادات الدين')));
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _primary,
      foregroundColor: _onPrimary,
      elevation: 0,
      centerTitle: false,
      title: const Text(
        'إعدادات الدين',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'إعادة التحميل من القاعدة',
          onPressed: _loading ? null : _load,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _introBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _primary.withValues(alpha: 0.1),
        borderRadius: AppShape.none,
        border: Border.all(color: _primary.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: _primary, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'تُطبَّق هذه الحدود عند حفظ فاتورة نوعها «دين / آجل». اترك الحقل فارغاً أو 0 لتعطيل السقف.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    String? subtitle,
    IconData? icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: AppShape.none,
        border: Border.all(color: _outline.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: ScreenLayout.of(context).pageHorizontalGap,
              end: ScreenLayout.of(context).pageHorizontalGap,
              top: 14,
              bottom: 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: _primary, size: 24),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _outline.withValues(alpha: 0.28)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _switchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          subtitle,
          style: TextStyle(fontSize: 12.5, height: 1.4, color: _textSecondary),
        ),
      ),
      value: value,
      activeThumbColor: _onPrimary,
      activeTrackColor: _primary.withValues(alpha: 0.55),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _pageBg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAppBar(),
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _pageBg,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAppBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _introBanner(),
                        const SizedBox(height: 20),
                        _section(
                          icon: Icons.account_balance_outlined,
                          title: 'سقوف المبالغ',
                          subtitle:
                              'حدود المبالغ بالدينار العراقي. الفارغ أو 0 يعني عدم تفعيل السقف.',
                          children: [
                            TextField(
                              controller: _maxPerCustomer,
                              keyboardType: TextInputType.number,
                              decoration: _fieldDecoration(
                                label: 'أقصى مجموع متبقٍ لكل عميل (د.ع)',
                                helper:
                                    'مجموع المتبقي عبر كل فواتير الدين المفتوحة لنفس العميل. يمنع للعميل تجاوز السقف عند التفعيل أدناه.',
                                helperMaxLines: 3,
                                prefixIcon: Icon(
                                  Icons.groups_outlined,
                                  size: 20,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _maxPerInvoice,
                              keyboardType: TextInputType.number,
                              decoration: _fieldDecoration(
                                label: 'أقصى متبقٍ لفاتورة دين واحدة (د.ع)',
                                helper: 'إجمالي الفاتورة − المقدّم (النقدي).',
                                prefixIcon: Icon(
                                  Icons.receipt_long_outlined,
                                  size: 20,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _warnDays,
                              keyboardType: TextInputType.number,
                              decoration: _fieldDecoration(
                                label: 'أيام «تحذير العمر» في لوحة الديون',
                                helper:
                                    '0 = لا تنبيه بالعمر. بعد هذا العدد من أيام تاريخ الفاتورة تُعرَّف الفاتورة كقديمة.',
                                helperMaxLines: 3,
                                prefixIcon: Icon(
                                  Icons.schedule_outlined,
                                  size: 20,
                                  color: _textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _section(
                          icon: Icons.gavel_outlined,
                          title: 'الفرض عند البيع',
                          subtitle:
                              'عند التعطيل، يُسمح بالتجاوز لكن تبقى الأرقام مرجعاً لك يدوياً.',
                          children: [
                            _switchTile(
                              title: 'منع تجاوز سقف العميل',
                              subtitle:
                                  'يمنع حفظ فاتورة دين جديدة إذا تجاوز العميل الحد المحدد في «أقصى مجموع لكل عميل».',
                              value: _data.enforceCustomerCapAtSale,
                              onChanged: (v) => setState(
                                () => _data = _data.copyWith(
                                  enforceCustomerCapAtSale: v,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _switchTile(
                              title: 'منع تجاوز سقف الفاتورة الواحدة',
                              subtitle:
                                  'يمنع الحفظ إذا تجاوز المتبقي في هذه الفاتورة الحد المحدد لكل فاتورة.',
                              value: _data.enforceSingleInvoiceCapAtSale,
                              onChanged: (v) => setState(
                                () => _data = _data.copyWith(
                                  enforceSingleInvoiceCapAtSale: v,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_outlined, size: 22),
                          label: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'حفظ الإعدادات',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _primary,
                            foregroundColor: _onPrimary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppShape.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
