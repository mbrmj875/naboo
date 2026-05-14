import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/database_helper.dart';
import '../../widgets/employee_id_card.dart';

/// قائمة الموظفين وبطاقة الهوية (باركود + QR) لكل مستخدم.
class EmployeeIdentityScreen extends StatefulWidget {
  const EmployeeIdentityScreen({super.key, this.initialUserId});

  /// عند الانتقال من إنشاء مستخدم: يفتح البطاقة مباشرة.
  final int? initialUserId;

  @override
  State<EmployeeIdentityScreen> createState() => _EmployeeIdentityScreenState();
}

class _EmployeeIdentityScreenState extends State<EmployeeIdentityScreen> {
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  int? _expandedId;

  @override
  void initState() {
    super.initState();
    _expandedId = widget.initialUserId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.listActiveUsers();
    if (!mounted) return;
    setState(() {
      _rows = list;
      _loading = false;
    });
  }

  Future<void> _regeneratePin(int userId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تجديد رمز الوردية'),
          content: const Text(
            'سيتم إنشاء رمز جديد. يجب طباعة/تحديث بطاقة الهوية وإعادة توزيعها.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    await _db.regenerateUserShiftAccessPin(userId);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم تجديد رمز الوردية.')));
    await _load();
    setState(() => _expandedId = userId);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0F1A) : const Color(0xFFF1F5F9);
    final auth = context.watch<AuthProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          title: const Text(
            'هويات الموظفين',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
            ? Center(
                child: Text(
                  'لا يوجد مستخدمون نشطون في قاعدة البيانات.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _rows.length,
                  itemBuilder: (context, i) {
                    final u = _rows[i];
                    final id = u['id'] as int;
                    final name =
                        (u['displayName'] as String?)?.trim().isNotEmpty == true
                        ? u['displayName'] as String
                        : (u['username'] as String? ?? '—');
                    final expanded = _expandedId == id;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ExpansionTile(
                        key: ValueKey('id_$id'),
                        initiallyExpanded: expanded,
                        onExpansionChanged: (open) {
                          setState(() => _expandedId = open ? id : null);
                        },
                        title: Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          u['email']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: Center(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: EmployeeIdCard(
                                  user: u,
                                  width: 320,
                                  compact: false,
                                ),
                              ),
                            ),
                          ),
                          if (auth.isAdmin)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TextButton.icon(
                                onPressed: () => _regeneratePin(id),
                                icon: const Icon(Icons.refresh),
                                label: const Text('تجديد رمز الوردية'),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
