import 'dart:async';

import 'package:flutter/material.dart';

import '../../../utils/iqd_money.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../services/oil_change_orders_repository.dart';
import '../services/vehicle_registry.dart';
import '../utils/oil_change_lookup_normalize.dart';
import '../../../services/service_order_kinds.dart';
import 'oil_change_detail_screen.dart';
import '../../../utils/arabic_count.dart';
import '../utils/oil_odometer_unit.dart';

String _day(DateTime? d) => d == null
    ? ''
    : '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';

DateTime? _date(Object? v) => DateTime.tryParse((v ?? '').toString());

String _s(Object? v) => (v ?? '').toString().trim();

/// العداد في السجل رقم، وفي البطاقة نص («85,000» أو «٨٥٠٠٠»)، مع وحدته
/// («كم» أو «ميل»).
String _km(Object? v, [Object? unit]) {
  final n = v is num ? v.toInt() : int.tryParse(OilChangeLookupNormalize.toWesternDigits(_s(v)));
  if (n == null || n <= 0) return '';
  final label = OilOdometerUnit.label(OilOdometerUnit.parse(unit));
  return '${IraqiCurrencyFormat.formatInt(n)} $label';
}

/// سجل السيارات (المرحلة 6 — الشريحة 4): كل سيارات المحل مع البحث.
class VehiclesRegistryScreen extends StatefulWidget {
  const VehiclesRegistryScreen({super.key});

  @override
  State<VehiclesRegistryScreen> createState() => _VehiclesRegistryScreenState();
}

class _VehiclesRegistryScreenState extends State<VehiclesRegistryScreen> {
  static const _page = 50;
  final _search = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _rows = const [];
  bool _loading = true;
  bool _hasMore = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final gen = ++_generation;
    if (!more) setState(() => _loading = true);
    try {
      final rows = await OilChangeOrdersRepository.instance.listVehicles(
        query: _search.text,
        limit: _page,
        offset: more ? _rows.length : 0,
      );
      if (!mounted || gen != _generation) return;
      setState(() {
        _rows = more ? [..._rows, ...rows] : rows;
        _hasMore = rows.length == _page;
        _loading = false;
      });
    } catch (_) {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => unawaited(_load()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سجل السيارات')),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                key: const Key('vehiclesSearch'),
                controller: _search,
                onChanged: _onSearch,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'لوحة، اسم السيارة، اسم صاحبها أو هاتفه',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _search.text.trim().isEmpty
                              ? 'لا سيارات بعد. كل بطاقة غيار أو غسيل بلوحة تضيف سيارتها هنا.'
                              : 'لا سيارة تطابق البحث.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      itemCount: _rows.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, i) {
                        if (i == _rows.length) {
                          return TextButton(
                            onPressed: () => unawaited(_load(more: true)),
                            child: const Text('عرض المزيد'),
                          );
                        }
                        return _VehicleTile(
                          v: _rows[i],
                          onOpen: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => VehicleDetailScreen(
                                  vehicleGlobalId: _s(_rows[i]['global_id']),
                                ),
                              ),
                            );
                          },
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

class _VehicleTile extends StatelessWidget {
  const _VehicleTile({required this.v, required this.onOpen});

  final Map<String, dynamic> v;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final car = [_s(v['name']), _s(v['model'])]
        .where((e) => e.isNotEmpty)
        .join(' ');
    final visits = (v['visits_count'] as num?)?.toInt() ?? 0;
    final facts = [
      if (_date(v['last_visit_at']) != null) 'آخر زيارة ${_day(_date(v['last_visit_at']))}',
      arabicVisitsCount(visits),
      if (_km(v['last_odometer']).isNotEmpty) _km(v['last_odometer'], v['last_odometer_unit']),
    ].join(' · ');
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        key: Key('vehicleTile_${v['global_id']}'),
        onTap: onOpen,
        leading: const Icon(Icons.directions_car_rounded),
        title: Row(
          children: [
            Text(
              _s(v['plate_display']),
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (car.isNotEmpty) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(car, overflow: TextOverflow.ellipsis),
              ),
            ],
          ],
        ),
        subtitle: Text(
          [
            if (_s(v['customer_name']).isNotEmpty) _s(v['customer_name']),
            facts,
          ].join('\n'),
          style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
        ),
        isThreeLine: _s(v['customer_name']).isNotEmpty,
        trailing: const Icon(Icons.chevron_left_rounded),
      ),
    );
  }
}

/// صفحة سيارة: بياناتها، من ملكها ومتى، وكل زياراتها بقراءات العداد.
class VehicleDetailScreen extends StatefulWidget {
  const VehicleDetailScreen({super.key, required this.vehicleGlobalId});

  final String vehicleGlobalId;

  @override
  State<VehicleDetailScreen> createState() => _VehicleDetailScreenState();
}

class _VehicleDetailScreenState extends State<VehicleDetailScreen> {
  Map<String, dynamic>? _v;
  List<Map<String, dynamic>> _visits = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final repo = OilChangeOrdersRepository.instance;
    final v = await repo.getVehicle(widget.vehicleGlobalId);
    final visits = await repo.vehicleVisits(widget.vehicleGlobalId);
    if (!mounted) return;
    setState(() {
      _v = v;
      _visits = visits;
      _loading = false;
    });
  }

  Widget _section(BuildContext context, String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = _v;
    final owners = VehicleRegistry.ownerPeriods(_visits).reversed.toList();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            v == null ? 'السيارة' : _s(v['plate_display']),
            textDirection: TextDirection.ltr,
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : v == null
            ? const Center(child: Text('السيارة غير موجودة.'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _s(v['plate_display']),
                            key: const Key('vehiclePlate'),
                            textDirection: TextDirection.ltr,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            [
                              _s(v['name']),
                              _s(v['model']),
                              if (_s(v['engine_size']).isNotEmpty)
                                'محرك ${_s(v['engine_size'])}',
                            ].where((e) => e.isNotEmpty).join(' · '),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            [
                              arabicVisitsCount((v['visits_count'] as num?)?.toInt() ?? 0),
                              if (_km(v['last_odometer']).isNotEmpty)
                                'آخر عداد ${_km(v['last_odometer'], v['last_odometer_unit'])}',
                            ].join(' · '),
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _section(context, 'المالكون', [
                    if (owners.isEmpty)
                      Text(
                        'لا اسم زبون في بطاقاتها.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    for (var i = 0; i < owners.length; i++)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          key: Key('vehicleOwner_$i'),
                          leading: Icon(
                            i == 0
                                ? Icons.person_rounded
                                : Icons.person_outline_rounded,
                          ),
                          title: Text(
                            owners[i].name.isEmpty ? 'بلا اسم' : owners[i].name,
                            style: TextStyle(
                              fontWeight: i == 0 ? FontWeight.w800 : null,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (owners[i].phone.isNotEmpty) owners[i].phone,
                              owners[i].from == owners[i].to
                                  ? _day(owners[i].from)
                                  : 'من ${_day(owners[i].from)} إلى ${_day(owners[i].to)}',
                              arabicVisitsCount(owners[i].visits),
                            ].join(' · '),
                          ),
                          trailing: i == 0 ? const Text('الحالي') : null,
                        ),
                      ),
                  ]),
                  _section(context, 'الزيارات', [
                    for (final o in _visits) _VisitTile(o: o),
                  ]),
                ],
              ),
      ),
    );
  }
}

class _VisitTile extends StatelessWidget {
  const _VisitTile({required this.o});

  final Map<String, dynamic> o;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wash = ServiceOrderKinds.isCarWash(o);
    final oil = [
      _s(o['oilType']),
      _s(o['oilViscosity']),
    ].where((e) => e.isNotEmpty).join(' ');
    final price = (o['agreedPriceFils'] as num?)?.toInt() ??
        (o['estimatedPriceFils'] as num?)?.toInt() ??
        0;
    final id = (o['id'] as num?)?.toInt() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        key: Key('vehicleVisit_$id'),
        leading: Icon(
          wash ? Icons.local_car_wash_rounded : Icons.opacity_rounded,
          color: cs.primary,
        ),
        title: Text(
          [
            _day(_date(o['createdAt'])),
            wash ? 'غسيل' : 'غيار زيت',
            if (_km(o['odometerCurrent']).isNotEmpty) _km(o['odometerCurrent'], o['odometerUnit']),
          ].join(' · '),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          [
            if (_s(o['customerNameSnapshot']).isNotEmpty)
              _s(o['customerNameSnapshot']),
            if (oil.isNotEmpty) oil,
            if (price > 0) IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(price)),
          ].join(' · '),
        ),
        trailing: wash ? null : const Icon(Icons.chevron_left_rounded),
        onTap: wash || id <= 0
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => OilChangeDetailScreen(
                    orderId: id,
                    orderGlobalId: _s(o['global_id']),
                  ),
                ),
              ),
      ),
    );
  }
}
