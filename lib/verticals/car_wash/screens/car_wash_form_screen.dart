import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../home/home_kpi_repository.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/cloud_sync_service.dart';
import '../../../theme/app_corner_style.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/screen_layout.dart';
import '../../oil_change/widgets/oil_change_form_theme.dart';
import '../../oil_change/widgets/oil_change_royal_card.dart';
import '../models/car_wash_service_item.dart';
import '../services/car_wash_checkout_service.dart';
import '../services/car_wash_orders_repository.dart';
import '../services/car_wash_services_repository.dart';
import 'car_wash_services_settings_screen.dart';

/// نموذج سريع: لوحة اختيارية + أنواع غسل متعددة + سعر + دفع فوري + مزامنة.
class CarWashFormScreen extends StatefulWidget {
  const CarWashFormScreen({super.key});

  @override
  State<CarWashFormScreen> createState() => _CarWashFormScreenState();
}

class _CarWashFormScreenState extends State<CarWashFormScreen> {
  final _plateCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  List<CarWashServiceItem> _services = [];
  final Set<int> _selectedIds = {};
  bool _loadingServices = true;
  bool _saving = false;
  String? _error;

  static const _gold = OilChangeFormTheme.gold;

  @override
  void initState() {
    super.initState();
    _loadServices();
  }

  @override
  void dispose() {
    _plateCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  List<CarWashServiceItem> get _selectedServices =>
      _services.where((s) => _selectedIds.contains(s.id)).toList();

  Future<void> _loadServices({bool force = false}) async {
    // عرض الكاش فوراً إن وُجد — ثم تحديث خلفي عند الحاجة.
    final cached = CarWashServicesRepository.instance.cachedActive;
    if (cached != null && !force) {
      _applyServicesList(cached);
    } else {
      setState(() => _loadingServices = true);
    }
    try {
      final list = await CarWashServicesRepository.instance.listActive(
        force: force,
      );
      if (!mounted) return;
      _applyServicesList(list);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingServices = false;
        if (_services.isEmpty) {
          _error = 'تعذر تحميل أنواع الغسل.';
        }
      });
    }
  }

  void _applyServicesList(List<CarWashServiceItem> list) {
    final stillValid = _selectedIds.where(
      (id) => list.any((s) => s.id == id),
    );
    setState(() {
      _services = list;
      _selectedIds
        ..clear()
        ..addAll(stillValid);
      _loadingServices = false;
      _syncPriceFromSelection();
    });
  }

  void _syncPriceFromSelection() {
    final sum = _selectedServices.fold<int>(0, (s, e) => s + e.priceFils);
    if (sum <= 0) {
      _priceCtrl.clear();
      return;
    }
    _priceCtrl.text = IraqiCurrencyFormat.formatInt(IqdMoney.fromFils(sum));
  }

  void _toggleService(CarWashServiceItem service) {
    setState(() {
      if (_selectedIds.contains(service.id)) {
        _selectedIds.remove(service.id);
      } else {
        _selectedIds.add(service.id);
      }
      _error = null;
      _syncPriceFromSelection();
    });
  }

  int _priceFilsFromField() {
    final dinars = IraqiCurrencyFormat.parseIqdInt(_priceCtrl.text);
    return IqdMoney.toFils(dinars.toDouble());
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => const CarWashServicesSettingsScreen(),
      ),
    );
    if (!mounted) return;
    await _loadServices(force: true);
  }

  Future<void> _submit() async {
    if (_saving) return;
    final selected = _selectedServices;
    if (selected.isEmpty) {
      setState(
        () => _error =
            'اختر نوع غسل واحداً على الأقل، أو أضفه من الإعدادات.',
      );
      return;
    }
    final priceFils = _priceFilsFromField();
    if (priceFils <= 0) {
      setState(() => _error = 'أدخل سعراً صالحاً.');
      return;
    }

    final plate = _plateCtrl.text.trim();
    final typeLabel = selected.map((s) => s.name).join(' + ');
    final staff = context.read<AuthProvider>().displayName;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final orderId =
          await CarWashOrdersRepository.instance.createPaidWashOrder(
        plate: plate,
        washTypeNameAr: typeLabel,
        priceFils: priceFils,
      );
      final customerLabel = plate.isEmpty ? 'عميل غسيل' : 'لوحة $plate';
      final result = await CarWashCheckoutService.instance.completeFromOrder(
        order: {
          'deviceName': typeLabel,
          'deviceSerial': plate.isEmpty ? null : plate,
          'customerNameSnapshot': customerLabel,
          'agreedPriceFils': priceFils,
          'estimatedPriceFils': priceFils,
        },
        orderId: orderId,
        createdByUserName: staff,
        selectedServices: selected,
      );

      HomeKpiRepository.instance.invalidate();
      // دفع فوري للسحابة — يرى المالك العدد على الأجهزة الأخرى بسرعة.
      unawaited(
        CloudSyncService.instance.syncNow(
          forcePull: false,
          forcePush: true,
        ),
      );

      if (!mounted) return;
      final amount = IraqiCurrencyFormat.formatIqd(
        IqdMoney.fromFils(result.totalFils),
      );
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text('تم الحفظ — فاتورة #${result.invoiceId} · $amount'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on CarWashCheckoutException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'تعذر حفظ عملية الغسل. حاول مرة أخرى.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final themed = OilChangeFormTheme.wrap(context, base);
    final cs = themed.colorScheme;
    final ac = context.appCorners;
    final sl = ScreenLayout.of(context);
    final gold = OilChangeRoyalCard.gold;

    return Theme(
      data: themed,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('غسل سيارة'),
          actions: [
            IconButton(
              tooltip: 'إعدادات الخدمات',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_rounded),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: EdgeInsetsDirectional.only(
              start: sl.pageHorizontalGap,
              end: sl.pageHorizontalGap,
              top: 16,
              bottom: 24,
            ),
            children: [
              TextField(
                controller: _plateCtrl,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: 'رقم اللوحة (اختياري)',
                  hintText: 'مثال: 12345',
                  border: OutlineInputBorder(borderRadius: ac.sm),
                  prefixIcon: const Icon(Icons.directions_car_rounded),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'نوع الغسل * (يمكن اختيار أكثر من نوع)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: OilChangeFormTheme.emphasisText(context),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.tune_rounded, size: 18, color: _gold),
                    label: const Text('إعدادات', style: TextStyle(color: _gold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_loadingServices && _services.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_services.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: OilChangeRoyalCard.decoration(cs),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'لا توجد خدمات بعد. ابدأ بإضافة نوع وسعر من الإعدادات.',
                        style: TextStyle(
                          color: OilChangeFormTheme.secondaryText(context),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: _openSettings,
                        child: const Text('فتح الإعدادات'),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in _services)
                      FilterChip(
                        selectedColor: gold.withValues(alpha: 0.92),
                        checkmarkColor: Colors.white,
                        avatar: Icon(
                          Icons.push_pin_rounded,
                          size: 16,
                          color: _selectedIds.contains(s.id)
                              ? Colors.white
                              : gold,
                        ),
                        label: Text(
                          '${s.name} · ${IraqiCurrencyFormat.formatInt(IqdMoney.fromFils(s.priceFils))}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _selectedIds.contains(s.id)
                                ? Colors.white
                                : OilChangeFormTheme.emphasisText(context),
                          ),
                        ),
                        selected: _selectedIds.contains(s.id),
                        onSelected: (_) => _toggleService(s),
                        side: BorderSide(
                          color: gold.withValues(alpha: 0.75),
                          width: 1.4,
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  IraqiCurrencyFormat.moneyInputFormatter(),
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                ],
                decoration: InputDecoration(
                  labelText: 'السعر (د.ع) *',
                  helperText: _selectedIds.length > 1
                      ? 'يُحسب تلقائياً من الأنواع المختارة ويمكن تعديله'
                      : null,
                  border: OutlineInputBorder(borderRadius: ac.sm),
                  prefixIcon: const Icon(Icons.payments_rounded),
                  suffixText: 'د.ع',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _saving ? null : _submit,
                  borderRadius: ac.md,
                  child: Ink(
                    height: 52,
                    decoration: BoxDecoration(
                      borderRadius: ac.md,
                      gradient: LinearGradient(
                        begin: AlignmentDirectional.topStart,
                        end: AlignmentDirectional.bottomEnd,
                        colors: [
                          gold.withValues(alpha: 0.95),
                          gold.withValues(alpha: 0.78),
                        ],
                      ),
                      border: Border.all(color: gold, width: 1.5),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x40B8960C),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.check_rounded, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'حفظ ودفع',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
