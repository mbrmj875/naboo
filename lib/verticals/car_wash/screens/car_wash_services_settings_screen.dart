import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_corner_style.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/screen_layout.dart';
import '../../oil_change/widgets/oil_change_form_theme.dart';
import '../../oil_change/widgets/oil_change_royal_card.dart';
import '../models/car_wash_service_item.dart';
import '../services/car_wash_services_repository.dart';

/// إدارة أنواع الغسل: إضافة / تعديل / حذف (اسم + سعر).
class CarWashServicesSettingsScreen extends StatefulWidget {
  const CarWashServicesSettingsScreen({super.key});

  @override
  State<CarWashServicesSettingsScreen> createState() =>
      _CarWashServicesSettingsScreenState();
}

class _CarWashServicesSettingsScreenState
    extends State<CarWashServicesSettingsScreen> {
  List<CarWashServiceItem> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await CarWashServicesRepository.instance.listActive();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل الخدمات.';
      });
    }
  }

  Future<void> _openEditor({CarWashServiceItem? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _CarWashServiceEditorSheet(existing: existing),
    );
    if (saved == true && mounted) await _reload();
  }

  Future<void> _confirmDelete(CarWashServiceItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الخدمة'),
        content: Text('حذف «${item.name}»؟'),
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
    if (ok != true || !mounted) return;

    // إزالة فورية من الواجهة ثم التأكيد من قاعدة البيانات.
    setState(() {
      _items = _items.where((e) => e.id != item.id).toList();
    });

    final deleted =
        await CarWashServicesRepository.instance.softDeleteById(item.id);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر حذف الخدمة. حاول مرة أخرى.')),
      );
      await _reload();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم حذف «${item.name}»')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final themed = OilChangeFormTheme.wrap(context, base);
    final cs = themed.colorScheme;
    final sl = ScreenLayout.of(context);
    final gold = OilChangeRoyalCard.gold;

    return Theme(
      data: themed,
      child: Scaffold(
      appBar: AppBar(title: const Text('خدمات الغسل')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: gold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('إضافة خدمة'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: TextStyle(color: cs.error)),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _reload,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                )
              : _items.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد خدمات — أضف نوع غسل وسعره',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      padding: EdgeInsetsDirectional.only(
                        start: sl.pageHorizontalGap,
                        end: sl.pageHorizontalGap,
                        top: 12,
                        bottom: 88,
                      ),
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        final price = IraqiCurrencyFormat.formatIqd(
                          IqdMoney.fromFils(item.priceFils),
                        );
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: context.appCorners.sm,
                            side: BorderSide(
                              color: gold.withValues(alpha: 0.45),
                            ),
                          ),
                          title: Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(price),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'تعديل',
                                onPressed: () => _openEditor(existing: item),
                                icon: Icon(Icons.edit_rounded, color: gold),
                              ),
                              IconButton(
                                tooltip: 'حذف',
                                onPressed: () => _confirmDelete(item),
                                icon: Icon(
                                  Icons.delete_outline_rounded,
                                  color: cs.error,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
    ),
    );
  }
}

class _CarWashServiceEditorSheet extends StatefulWidget {
  const _CarWashServiceEditorSheet({this.existing});

  final CarWashServiceItem? existing;

  @override
  State<_CarWashServiceEditorSheet> createState() =>
      _CarWashServiceEditorSheetState();
}

class _CarWashServiceEditorSheetState extends State<_CarWashServiceEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _priceCtrl = TextEditingController(
      text: e == null || e.priceFils <= 0
          ? ''
          : IraqiCurrencyFormat.formatInt(IqdMoney.fromFils(e.priceFils)),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'أدخل اسم الخدمة.');
      return;
    }
    final dinars = IraqiCurrencyFormat.parseIqdInt(_priceCtrl.text);
    final fils = IqdMoney.toFils(dinars.toDouble());
    if (fils <= 0) {
      setState(() => _error = 'أدخل سعراً صالحاً.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_isEdit) {
        await CarWashServicesRepository.instance.updateById(
          id: widget.existing!.id,
          name: name,
          priceFils: fils,
        );
      } else {
        await CarWashServicesRepository.instance.insert(
          name: name,
          priceFils: fils,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'تعذر الحفظ.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: 16,
        end: 16,
        top: 16,
        bottom: bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEdit ? 'تعديل خدمة' : 'إضافة خدمة',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'نوع الخدمة *',
              hintText: 'مثال: تلميع',
              border: OutlineInputBorder(borderRadius: ac.sm),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              IraqiCurrencyFormat.moneyInputFormatter(),
              FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
            ],
            decoration: InputDecoration(
              labelText: 'السعر (د.ع) *',
              border: OutlineInputBorder(borderRadius: ac.sm),
              suffixText: 'د.ع',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'جاري الحفظ…' : 'حفظ'),
          ),
        ],
      ),
    );
  }
}
