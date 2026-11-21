import 'package:flutter/material.dart';

import '../../../models/store_policy.dart';
import '../../../screens/settings/policy_settings_save.dart';
import '../../../services/store_policy_settings_repository.dart';
import '../models/car_wash_service_item.dart';
import '../services/car_wash_services_repository.dart';

/// عروض الغسيل — للمالك فقط، والحفظ برمزه. العرضان مطفآن افتراضياً.
class WashOffersSettingsScreen extends StatefulWidget {
  const WashOffersSettingsScreen({super.key});

  @override
  State<WashOffersSettingsScreen> createState() =>
      _WashOffersSettingsScreenState();
}

class _WashOffersSettingsScreenState extends State<WashOffersSettingsScreen> {
  StorePolicy? _saved;
  late WashRepeatOffer _r;
  late OilCustomerWashDiscount _o;
  List<CarWashServiceItem> _catalog = const [];
  bool _saving = false;
  final _rewardValue = TextEditingController();
  final _maxDiscount = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _rewardValue.dispose();
    _maxDiscount.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await StorePolicySettingsRepository.instance.load();
    List<CarWashServiceItem> cat = const [];
    try {
      cat = await CarWashServicesRepository.instance.listActive();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _saved = s;
      _r = s.washRepeat;
      _o = s.oilWash;
      _catalog = cat;
      _rewardValue.text = _r.rewardValue == 0 ? '' : _fmt(_r.rewardValue);
      _maxDiscount.text = _r.maxDiscount == 0 ? '' : _fmt(_r.maxDiscount);
    });
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  static double _num(String s) =>
      double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;

  StorePolicy get _draft => _saved!.copyWith(washRepeat: _r, oilWash: _o);

  bool get _dirty =>
      _saved != null && _draft.toJsonString() != _saved!.toJsonString();

  String? get _error {
    if (_r.enabled) {
      if (_r.rewardType == WashRewardType.percent &&
          (_r.rewardValue <= 0 || _r.rewardValue > 100)) {
        return 'نسبة المكافأة بين 1 و100.';
      }
      if (_r.rewardType == WashRewardType.fixed && _r.rewardValue <= 0) {
        return 'اكتب مبلغ الخصم الثابت.';
      }
    }
    if (_o.enabled && _o.tiers.isEmpty) return 'أضف شريحة واحدة على الأقل.';
    return null;
  }

  Future<void> _save() async {
    final before = _saved!;
    setState(() => _saving = true);
    final ok = await saveStorePolicyWithOwnerPin(
      context,
      before: before,
      after: _draft,
      eventType: 'wash_offers_changed',
      sectionTitle: 'عروض الغسيل',
      slice: (s) => {
        'washRepeat': s.washRepeat.toJson(),
        'oilWash': s.oilWash.toJson(),
      },
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) await _load();
  }

  Widget _stepper(
    String label,
    int value,
    void Function(int) onChanged, {
    int min = 1,
    int max = 365,
    String unit = '',
    bool enabled = true,
  }) {
    return ListTile(
      enabled: enabled,
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'إنقاص',
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: !enabled || value <= min
                ? null
                : () => onChanged(value - 1),
          ),
          Text(
            '$value$unit',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          IconButton(
            tooltip: 'زيادة',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: !enabled || value >= max
                ? null
                : () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
    child: Text(
      t,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    ),
  );

  Future<void> _editTier(int? index) async {
    final cur = index == null ? null : _o.tiers[index];
    final minCtrl = TextEditingController(
      text: cur == null ? '' : '${cur.minOilChanges}',
    );
    final pctCtrl = TextEditingController(
      text: cur == null ? '' : _fmt(cur.percent),
    );
    final res = await showDialog<OilCustomerTier>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(index == null ? 'شريحة جديدة' : 'تعديل الشريحة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'من عدد غيارات'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pctCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'نسبة الخصم % (100 = مجانية)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              final m = int.tryParse(minCtrl.text.trim()) ?? 0;
              final p = _num(pctCtrl.text);
              if (m < 1 || p <= 0 || p > 100) return;
              Navigator.pop(ctx, OilCustomerTier(m, p));
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    minCtrl.dispose();
    pctCtrl.dispose();
    if (res == null || !mounted) return;
    final tiers = [..._o.tiers];
    if (index == null) {
      tiers.removeWhere((t) => t.minOilChanges == res.minOilChanges);
      tiers.add(res);
    } else {
      tiers[index] = res;
    }
    tiers.sort((a, b) => a.minOilChanges.compareTo(b.minOilChanges));
    setState(() => _o = _o.copyWith(tiers: tiers));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final saved = _saved;
    final err = saved == null ? null : _error;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('عروض الغسيل')),
        body: saved == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _sectionTitle('عرض تكرار الغسل'),
                  SwitchListTile(
                    value: _r.enabled,
                    title: const Text('تفعيل العرض'),
                    subtitle: Text(
                      'كل ${_r.washesRequired} غسلات خلال ${_r.periodDays} أيام: '
                      'الغسلة رقم ${_r.washesRequired} ${switch (_r.rewardType) {
                        WashRewardType.free => 'مجانية',
                        WashRewardType.percent => 'بخصم نسبة',
                        WashRewardType.fixed => 'بخصم ثابت',
                      }}',
                    ),
                    onChanged: (v) =>
                        setState(() => _r = _r.copyWith(enabled: v)),
                  ),
                  _stepper(
                    'عدد الغسلات (مع غسلة المكافأة)',
                    _r.washesRequired,
                    (v) => setState(() => _r = _r.copyWith(washesRequired: v)),
                    min: 2,
                    max: 50,
                    enabled: _r.enabled,
                  ),
                  _stepper(
                    'خلال (أيام)',
                    _r.periodDays,
                    (v) => setState(() => _r = _r.copyWith(periodDays: v)),
                    enabled: _r.enabled,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: SegmentedButton<WashRewardType>(
                      segments: const [
                        ButtonSegment(
                          value: WashRewardType.free,
                          label: Text('مجانية'),
                        ),
                        ButtonSegment(
                          value: WashRewardType.percent,
                          label: Text('نسبة %'),
                        ),
                        ButtonSegment(
                          value: WashRewardType.fixed,
                          label: Text('مبلغ ثابت'),
                        ),
                      ],
                      selected: {_r.rewardType},
                      onSelectionChanged: _r.enabled
                          ? (s) => setState(
                              () => _r = _r.copyWith(rewardType: s.first),
                            )
                          : null,
                    ),
                  ),
                  if (_r.rewardType != WashRewardType.free)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: TextField(
                        controller: _rewardValue,
                        enabled: _r.enabled,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: _r.rewardType == WashRewardType.percent
                              ? 'نسبة الخصم %'
                              : 'مبلغ الخصم (د.ع)',
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(
                          () => _r = _r.copyWith(rewardValue: _num(v)),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: TextField(
                      controller: _maxDiscount,
                      enabled: _r.enabled,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'حد أعلى للخصم (د.ع) — اختياري',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(
                        () => _r = _r.copyWith(maxDiscount: _num(v)),
                      ),
                    ),
                  ),
                  if (_catalog.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _r.coveredServiceNames.isEmpty
                                ? 'الأنواع المشمولة: كل الأنواع'
                                : 'الأنواع المشمولة:',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              for (final item in _catalog)
                                FilterChip(
                                  label: Text(item.name),
                                  selected: _r.coveredServiceNames.contains(
                                    item.name,
                                  ),
                                  onSelected: !_r.enabled
                                      ? null
                                      : (v) {
                                          final set = {
                                            ..._r.coveredServiceNames,
                                          };
                                          v
                                              ? set.add(item.name)
                                              : set.remove(item.name);
                                          setState(
                                            () => _r = _r.copyWith(
                                              coveredServiceNames: set.toList(),
                                            ),
                                          );
                                        },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'العدّ يبدأ من جديد بعد المكافأة. الغسلات الملغاة أو المرتجعة لا تُحسب.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  const Divider(height: 28),
                  _sectionTitle('خصم زبون الزيت'),
                  SwitchListTile(
                    value: _o.enabled,
                    title: const Text('تفعيل الخصم'),
                    subtitle: const Text(
                      'خصم على الغسيل حسب عدد غيارات السيارة في المحل',
                    ),
                    onChanged: (v) =>
                        setState(() => _o = _o.copyWith(enabled: v)),
                  ),
                  for (var i = 0; i < _o.tiers.length; i++)
                    ListTile(
                      enabled: _o.enabled,
                      leading: const Icon(Icons.oil_barrel_outlined),
                      title: Text(
                        '${_o.tiers[i].minOilChanges} غيار فأكثر ← '
                        '${_o.tiers[i].percent >= 100 ? 'مجانية' : '${_fmt(_o.tiers[i].percent)}%'}',
                      ),
                      onTap: _o.enabled ? () => _editTier(i) : null,
                      trailing: IconButton(
                        tooltip: 'حذف الشريحة',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: !_o.enabled
                            ? null
                            : () => setState(
                                () => _o = _o.copyWith(
                                  tiers: [..._o.tiers]..removeAt(i),
                                ),
                              ),
                      ),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: TextButton.icon(
                        onPressed: _o.enabled ? () => _editTier(null) : null,
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة شريحة'),
                      ),
                    ),
                  ),
                  _stepper(
                    'فترة عدّ الغيارات (أيام)',
                    _o.countingPeriodDays,
                    (v) =>
                        setState(() => _o = _o.copyWith(countingPeriodDays: v)),
                    max: 3650,
                    enabled: _o.enabled,
                  ),
                  _stepper(
                    'غسلات مخصومة لكل غيار',
                    _o.washesPerOilChange,
                    (v) =>
                        setState(() => _o = _o.copyWith(washesPerOilChange: v)),
                    max: 20,
                    enabled: _o.enabled,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(
                      'إن انطبق العرضان على غسلة واحدة يُطبَّق الأكبر.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (err != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Text(err, style: TextStyle(color: cs.error)),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: FilledButton.icon(
                      onPressed: _saving || !_dirty || err != null
                          ? null
                          : _save,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('حفظ برمز المالك'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
