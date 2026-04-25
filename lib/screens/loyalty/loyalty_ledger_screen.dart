import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/database_helper.dart';

/// سجل حركات نقاط الولاء (جميع العملاء أو حسب التصفية لاحقاً).
class LoyaltyLedgerScreen extends StatefulWidget {
  const LoyaltyLedgerScreen({super.key});

  @override
  State<LoyaltyLedgerScreen> createState() => _LoyaltyLedgerScreenState();
}

class _LoyaltyLedgerScreenState extends State<LoyaltyLedgerScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Map<String, dynamic>> _rows = [];
  Map<int, String> _names = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ledger = await _db.getLoyaltyLedger(limit: 800);
      final customers = await _db.getAllCustomers();
      final names = {
        for (final c in customers) c['id'] as int: c['name']?.toString() ?? '',
      };
      if (!mounted) return;
      setState(() {
        _rows = ledger;
        _names = names;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر التحميل: $e')),
      );
    }
  }

  String _kindLabel(String? k) {
    switch (k) {
      case 'earn':
        return 'منح';
      case 'redeem':
        return 'استبدال';
      default:
        return k ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy/MM/dd HH:mm', 'en');
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل نقاط الولاء'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rows.isEmpty
              ? Center(
                  child: Text(
                    'لا توجد حركات بعد — فعّل الولاء من الإعدادات وسجّل مبيعات مرتبطة بعملاء.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = _rows[i];
                    final cid = r['customerId'] as int? ?? 0;
                    final name = _names[cid] ?? 'عميل #$cid';
                    final pts = (r['points'] as num?)?.toInt() ?? 0;
                    final bal = (r['balanceAfter'] as num?)?.toInt() ?? 0;
                    final note = r['note']?.toString() ?? '';
                    final created = r['createdAt']?.toString() ?? '';
                    DateTime? dt;
                    try {
                      dt = DateTime.parse(created);
                    } catch (_) {}
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: pts >= 0
                            ? Colors.teal.shade100
                            : Colors.orange.shade100,
                        child: Icon(
                          pts >= 0 ? Icons.add_rounded : Icons.remove_rounded,
                          color: pts >= 0
                              ? Colors.teal.shade800
                              : Colors.orange.shade800,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${_kindLabel(r['kind'] as String?)} · $note\n'
                        '${dt != null ? df.format(dt) : created}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${pts >= 0 ? '+' : ''}$pts',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: pts >= 0 ? Colors.teal : Colors.deepOrange,
                            ),
                          ),
                          Text(
                            'رصيد $bal',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
