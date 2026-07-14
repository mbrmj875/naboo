import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../models/oil_change_filter_catalog_entry.dart';
import '../models/oil_change_filter_kind.dart';
import '../services/oil_change_filter_catalog_repository.dart';
import '../../../theme/sale_brand.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import 'oil_change_royal_card.dart';

/// إدارة كتالوج الفلاتر (فئة + اسم + سعر) أو اختيار صنف للبطاقة.
Future<OilChangeFilterPick?> showOilChangeFilterCatalogSheet(
  BuildContext context, {
  bool manageOnly = false,
  OilChangeFilterKind? initialKind,
}) {
  return showModalBottomSheet<OilChangeFilterPick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _OilChangeFilterCatalogSheetBody(
      manageOnly: manageOnly,
      initialKind: initialKind ?? OilChangeFilterKind.engine,
    ),
  );
}

class _OilChangeFilterCatalogSheetBody extends StatefulWidget {
  const _OilChangeFilterCatalogSheetBody({
    required this.initialKind,
    this.manageOnly = false,
  });

  final bool manageOnly;
  final OilChangeFilterKind initialKind;

  @override
  State<_OilChangeFilterCatalogSheetBody> createState() =>
      _OilChangeFilterCatalogSheetBodyState();
}

class _OilChangeFilterCatalogSheetBodyState
    extends State<_OilChangeFilterCatalogSheetBody> {
  static const _gold = SaleBrandColors.gold;

  late OilChangeFilterKind _kind;
  bool _loading = true;
  Object? _error;
  List<OilChangeFilterCatalogEntry> _entries = const [];
  bool _adding = false;

  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    unawaited(_load());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await OilChangeFilterCatalogRepository.instance.listActive();
      if (!mounted) return;
      setState(() {
        _entries = list;
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

  List<OilChangeFilterCatalogEntry> get _kindEntries =>
      OilChangeFilterCatalogRepository.entriesForKind(_entries, _kind);

  Future<void> _saveNew() async {
    final name = _nameCtrl.text.trim();
    final priceDinars = IraqiCurrencyFormat.parseIqdInt(_priceCtrl.text);
    final priceFils = IqdMoney.toFils(priceDinars.toDouble());
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم الفلتر')),
      );
      return;
    }
    if (priceFils <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل السعر')),
      );
      return;
    }
    try {
      await OilChangeFilterCatalogRepository.instance.insert(
        kind: _kind,
        name: name,
        priceFils: priceFils,
      );
      _nameCtrl.clear();
      _priceCtrl.clear();
      if (!mounted) return;
      setState(() => _adding = false);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تمت إضافة «$name» لـ ${_kind.label}')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      final msg = e.message == 'duplicate_kind_name'
          ? 'نفس الاسم موجود لهذه الفئة'
          : 'تعذّر الحفظ';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر الحفظ')),
      );
    }
  }

  Future<void> _delete(OilChangeFilterCatalogEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الصنف؟'),
        content: Text('«${e.name}» لن يظهر في القوائم الجديدة.'),
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
    await OilChangeFilterCatalogRepository.instance.softDeleteById(e.id);
    if (mounted) unawaited(_load());
  }

  void _pick(OilChangeFilterCatalogEntry e) {
    Navigator.pop(
      context,
      OilChangeFilterPick(
        kind: e.kind,
        name: e.name,
        priceFils: e.priceFils,
        catalogEntryId: e.id,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12 + bottom),
      child: SizedBox(
        height: maxH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.filter_alt_outlined, color: _gold, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'كتالوج الفلاتر',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Text(
              widget.manageOnly
                  ? 'أضف لكل فئة (محرك، هواء، كير) أسماء فلاتر بأسعارها. الاختيار في البطاقة من القوائم فقط.'
                  : 'اختر صنفاً للبطاقة أو أضف أسماء جديدة بأسعارها.',
              style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 10),
            SegmentedButton<OilChangeFilterKind>(
              segments: [
                for (final k in OilChangeFilterKind.all)
                  ButtonSegment(
                    value: k,
                    label: Text(
                      k.label.replaceFirst('فلتر ', ''),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) {
                if (s.isEmpty) return;
                setState(() => _kind = s.first);
              },
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                onPressed: () => setState(() => _adding = !_adding),
                icon: Icon(_adding ? Icons.expand_less : Icons.add_rounded),
                label: Text(_adding ? 'إخفاء الإضافة' : 'إضافة صنف'),
              ),
            ),
            if (_adding) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'اسم الفلتر',
                        hintText: 'مثال: تويوتا أصلي',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'السعر',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    onPressed: () => unawaited(_saveNew()),
                    icon: const Icon(Icons.check_rounded),
                    tooltip: 'حفظ',
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(
                            'تعذّر تحميل الكتالوج',
                            style: TextStyle(color: cs.error),
                          ),
                        )
                      : _kindEntries.isEmpty
                          ? Center(
                              child: Text(
                                'لا توجد أصناف لـ ${_kind.label}.\nاضغط «إضافة صنف».',
                                style: TextStyle(color: cs.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: _kindEntries.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                final e = _kindEntries[i];
                                final price = IraqiCurrencyFormat.formatIqd(
                                  IqdMoney.fromFils(e.priceFils),
                                );
                                return OilChangeRoyalCard.listTileCard(
                                  cs: cs,
                                  onTap: widget.manageOnly
                                      ? null
                                      : () => _pick(e),
                                  child: ListTile(
                                    title: Text(
                                      e.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    subtitle: Text(
                                      price,
                                      textDirection: TextDirection.ltr,
                                      textAlign: TextAlign.start,
                                    ),
                                    trailing: widget.manageOnly
                                        ? IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                            ),
                                            onPressed: () =>
                                                unawaited(_delete(e)),
                                          )
                                        : const Icon(Icons.chevron_left),
                                  ),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
