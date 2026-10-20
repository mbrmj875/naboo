import 'package:flutter/material.dart';

import '../models/car_wash_service_item.dart';
import '../services/car_wash_services_repository.dart';
import '../widgets/car_wash_service_dialog.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/screen_layout.dart';
import '../../oil_change/widgets/oil_change_form_theme.dart';

/// أنواع الغسيل وأسعارها — يُختار منها عند إنشاء بطاقة غسيل.
class CarWashServicesScreen extends StatefulWidget {
  const CarWashServicesScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const CarWashServicesScreen()),
    );
  }

  @override
  State<CarWashServicesScreen> createState() => _CarWashServicesScreenState();
}

class _CarWashServicesScreenState extends State<CarWashServicesScreen> {
  final _repo = CarWashServicesRepository.instance;

  bool _loading = true;
  Object? _error;
  List<CarWashServiceItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.listActive();
      if (!mounted) return;
      setState(() {
        _items = list;
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

  Future<void> _addOrEdit({CarWashServiceItem? existing}) async {
    final result = await showCarWashServiceDialog(context, existing: existing);
    if (result == null) return;
    try {
      if (existing == null) {
        await _repo.insert(name: result.name, priceFils: result.priceFils);
      } else {
        await _repo.updateById(
          id: existing.id,
          name: result.name,
          priceFils: result.priceFils,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الحفظ: $e')),
      );
      return;
    }
    if (!mounted) return;
    await _load();
  }

  Future<void> _delete(CarWashServiceItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف نوع الغسيل؟'),
        content: Text(
          'سيُخفى «${item.name}» من قائمة الاختيار. '
          'البطاقات المحفوظة سابقاً لا تتأثر.',
        ),
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
    try {
      await _repo.softDeleteById(item.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الحذف: $e')),
      );
      return;
    }
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pad = context.screenLayout.pageHorizontalGap;

    return Scaffold(
      appBar: OilChangeFormTheme.appBar(
        context: context,
        title: 'أنواع الغسيل وأسعارها',
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add_rounded),
        label: const Text('نوع غسيل'),
      ),
      body: _buildBody(cs, pad),
    );
  }

  Widget _buildBody(ColorScheme cs, double pad) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error, size: 40),
              const SizedBox(height: 12),
              Text(
                'تعذّر تحميل أنواع الغسيل.',
                style: TextStyle(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(pad),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_car_wash_rounded,
                size: 48,
                color: OilChangeFormTheme.gold,
              ),
              const SizedBox(height: 12),
              const Text(
                'لا أنواع غسيل بعد',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'أضف نوعاً مثل «غسيل كامل» أو «تنظيف داخلي» وحدّد سعره، '
                'ثم اخترْه مباشرة عند إنشاء بطاقة غسيل.',
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsetsDirectional.fromSTEB(pad, 12, pad, 96),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final item = _items[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: const Icon(
              Icons.local_car_wash_rounded,
              color: OilChangeFormTheme.gold,
            ),
            title: Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(item.priceFils)),
              textAlign: TextAlign.start,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'تعديل',
                  onPressed: () => _addOrEdit(existing: item),
                  icon: const Icon(Icons.edit_rounded),
                ),
                IconButton(
                  tooltip: 'حذف',
                  onPressed: () => _delete(item),
                  icon: Icon(Icons.delete_outline_rounded, color: cs.error),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
