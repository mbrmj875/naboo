import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/oil_change_service_item.dart';
import '../../../navigation/content_navigation.dart';
import '../services/oil_change_services_repository.dart';
import '../services/oil_change_settings.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../models/oil_change_filter_kind.dart';
import '../widgets/oil_change_royal_card.dart';
import '../widgets/oil_change_filter_catalog_sheet.dart';
import '../../../utils/screen_layout.dart';
import 'oil_change_service_form_screen.dart';

/// كتالوج خدمات غيار الزيت: سعر أساسي + خدمات إضافية.
class OilChangeServicesScreen extends StatefulWidget {
  const OilChangeServicesScreen({super.key});

  @override
  State<OilChangeServicesScreen> createState() => _OilChangeServicesScreenState();
}

class _OilChangeServicesScreenState extends State<OilChangeServicesScreen> {
  final _basePriceCtrl = TextEditingController();

  bool _loading = true;
  Object? _error;
  List<OilChangeServiceItem> _services = [];
  bool _savingBase = false;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _basePriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final baseFils = await OilChangeSettings.getBaseOilChangePriceFils();
      final list = await OilChangeServicesRepository.instance.listActive();
      if (!mounted) return;
      setState(() {
        _services = list;
        _basePriceCtrl.text = baseFils <= 0
            ? ''
            : IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(baseFils));
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

  Future<void> _saveBasePrice() async {
    final raw = _basePriceCtrl.text.trim().replaceAll(',', '');
    if (raw.isEmpty) {
      await OilChangeSettings.setBaseOilChangePriceFils(0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ سعر تبديل الزيت الأساسي')),
        );
      }
      return;
    }
    final n = double.tryParse(raw);
    if (n == null || n < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('سعر غير صالح')),
      );
      return;
    }
    setState(() => _savingBase = true);
    try {
      await OilChangeSettings.setBaseOilChangePriceFils(IqdMoney.toFils(n));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ سعر تبديل الزيت الأساسي')),
      );
    } finally {
      if (mounted) setState(() => _savingBase = false);
    }
  }

  Future<void> _openServiceForm({OilChangeServiceItem? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      contentMaterialRoute(
        routeId: existing == null
            ? AppContentRoutes.oilChangeServiceCreate
            : AppContentRoutes.oilChangeServiceEditId(existing.id),
        breadcrumbTitle: existing == null ? 'إضافة خدمة' : 'تعديل خدمة',
        builder: (_) => OilChangeServiceFormScreen(existing: existing),
      ),
    );
    if (saved == true) unawaited(_reload());
  }

  Future<void> _confirmDelete(OilChangeServiceItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الخدمة؟'),
        content: Text('«${item.name}» لن تظهر في بطاقات الغيار الجديدة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await OilChangeServicesRepository.instance.softDeleteById(item.id);
    if (mounted) unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pad = context.screenLayout.pageHorizontalGap;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الخدمات وأسعارها'),
        actions: [
          IconButton(
            tooltip: 'كتالوج الفلاتر',
            onPressed: _loading
                ? null
                : () => unawaited(
                      showOilChangeFilterCatalogSheet(
                        context,
                        manageOnly: true,
                        initialKind: OilChangeFilterKind.engine,
                      ),
                    ),
            icon: const Icon(Icons.filter_alt_outlined),
          ),
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'تعذّر تحميل الخدمات',
                          style: TextStyle(color: cs.error),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => unawaited(_reload()),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(pad, 12, pad, 8),
                      child: _BasePriceCard(
                        controller: _basePriceCtrl,
                        saving: _savingBase,
                        onSave: _saveBasePrice,
                      ),
                    ),
                    Padding(
                      padding: EdgeInsetsDirectional.fromSTEB(pad, 0, pad, 8),
                      child: Row(
                        children: [
                          Text(
                            'خدمات إضافية',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const Spacer(),
                          FilledButton.tonalIcon(
                            onPressed: () => unawaited(_openServiceForm()),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('إضافة خدمة'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _services.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد خدمات إضافية بعد.\nاضغط «إضافة خدمة».',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            )
                          : ListView.separated(
                              padding: EdgeInsetsDirectional.fromSTEB(
                                pad,
                                0,
                                pad,
                                24,
                              ),
                              itemCount: _services.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final s = _services[i];
                                final price = IraqiCurrencyFormat.formatIqd(
                                  IqdMoney.fromFils(s.priceFils),
                                );
                                return OilChangeRoyalCard.listTileCard(
                                  cs: cs,
                                  onTap: () =>
                                      unawaited(_openServiceForm(existing: s)),
                                  child: ListTile(
                                    title: Text(
                                      s.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      price,
                                      textDirection: TextDirection.ltr,
                                      textAlign: TextAlign.start,
                                    ),
                                    trailing: PopupMenuButton<String>(
                                      onSelected: (v) {
                                        if (v == 'edit') {
                                          unawaited(
                                            _openServiceForm(existing: s),
                                          );
                                        } else if (v == 'delete') {
                                          unawaited(_confirmDelete(s));
                                        }
                                      },
                                      itemBuilder: (_) => const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('تعديل'),
                                        ),
                                        PopupMenuItem(
                                          value: 'delete',
                                          child: Text('حذف'),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
    );
  }
}

class _BasePriceCard extends StatelessWidget {
  const _BasePriceCard({
    required this.controller,
    required this.saving,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: OilChangeRoyalCard.decoration(
        cs,
        radius: 12,
        backgroundColor: OilChangeRoyalCard.gold.withValues(alpha: 0.06),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.oil_barrel_outlined,
                  color: OilChangeRoyalCard.gold,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'سعر تبديل الزيت (أساسي)',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'يُضاف تلقائياً لكل بطاقة غيار جديدة مع الخدمات المحددة.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'السعر (د.ع)',
                border: OutlineInputBorder(),
                filled: true,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: saving ? null : onSave,
                icon: saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onPrimary,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text('حفظ السعر الأساسي'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
