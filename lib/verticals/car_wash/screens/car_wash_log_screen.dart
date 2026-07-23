import 'package:flutter/material.dart';

import '../../../theme/app_corner_style.dart';
import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import '../../../utils/screen_layout.dart';
import '../../oil_change/widgets/oil_change_royal_card.dart';
import '../services/car_wash_orders_repository.dart';
import 'car_wash_form_screen.dart';

/// سجل بسيط لعمليات الغسل.
class CarWashLogScreen extends StatefulWidget {
  const CarWashLogScreen({super.key});

  @override
  State<CarWashLogScreen> createState() => _CarWashLogScreenState();
}

class _CarWashLogScreenState extends State<CarWashLogScreen> {
  final _searchCtrl = TextEditingController();
  final _rows = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _hasMore = true;
    });
    try {
      final page = await CarWashOrdersRepository.instance.listLogPage(
        searchQuery: _searchCtrl.text,
        limit: 40,
      );
      if (!mounted) return;
      setState(() {
        _rows
          ..clear()
          ..addAll(page);
        _hasMore = page.length >= 40;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل سجل الغسل.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _rows.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final afterId = (_rows.last['id'] as num?)?.toInt();
      final page = await CarWashOrdersRepository.instance.listLogPage(
        searchQuery: _searchCtrl.text,
        afterId: afterId,
        limit: 40,
      );
      if (!mounted) return;
      setState(() {
        _rows.addAll(page);
        _hasMore = page.length >= 40;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _openCreate() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CarWashFormScreen()),
    );
    if (ok == true && mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ac = context.appCorners;
    final sl = ScreenLayout.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الغسل'),
        actions: [
          IconButton(
            tooltip: 'غسل جديد',
            onPressed: _openCreate,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: OilChangeRoyalCard.gold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.local_car_wash_rounded),
        label: const Text('غسل سيارة'),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(
              start: sl.pageHorizontalGap,
              end: sl.pageHorizontalGap,
              top: 12,
              bottom: 8,
            ),
            child: TextField(
              controller: _searchCtrl,
              onSubmitted: (_) => _reload(),
              decoration: InputDecoration(
                hintText: 'بحث باللوحة أو النوع…',
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(borderRadius: ac.sm),
                suffixIcon: IconButton(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(cs, ac)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, AppCornerStyle ac) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
          ],
        ),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          'لا توجد عمليات غسل بعد',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 120) {
          _loadMore();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsetsDirectional.only(
          start: 12,
          end: 12,
          bottom: 88,
        ),
        itemCount: _rows.length + (_loadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i >= _rows.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final r = _rows[i];
          final plate = (r['deviceSerial'] ?? '—').toString();
          final type = (r['deviceName'] ?? 'غسل').toString();
          final fils = (r['agreedPriceFils'] as num?)?.toInt() ??
              (r['estimatedPriceFils'] as num?)?.toInt() ??
              0;
          final inv = (r['invoiceId'] as num?)?.toInt();
          final price = IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
          return Material(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: ac.sm,
            child: ListTile(
              shape: RoundedRectangleBorder(borderRadius: ac.sm),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFF0D9488).withValues(alpha: 0.15),
                child: const Icon(
                  Icons.local_car_wash_rounded,
                  color: Color(0xFF0D9488),
                ),
              ),
              title: Text(
                plate,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                inv != null && inv > 0 ? '$type · فاتورة #$inv' : type,
              ),
              trailing: Text(
                price,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          );
        },
      ),
    );
  }
}
