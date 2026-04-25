import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/database_helper.dart';

final _dtFmt = DateFormat('dd/MM/yyyy HH:mm', 'ar');

/// عرض الورديات التي تتقاطع مع شهراً معيناً (من فتحها إلى إغلاقها واسم موظف الوردية).
class WorkShiftsCalendarScreen extends StatefulWidget {
  const WorkShiftsCalendarScreen({super.key});

  @override
  State<WorkShiftsCalendarScreen> createState() =>
      _WorkShiftsCalendarScreenState();
}

class _WorkShiftsCalendarScreenState extends State<WorkShiftsCalendarScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  late DateTime _month;
  List<Map<String, dynamic>> _rows = [];
  Map<int, int> _invoiceCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month, 1);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _db.listWorkShiftsOverlappingMonth(
      _month.year,
      _month.month,
    );
    final ids = rows
        .map((r) => r['id'] as int?)
        .whereType<int>()
        .toSet();
    final counts = await _db.getInvoiceTotalCountsByShiftIds(ids);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _invoiceCounts = counts;
      _loading = false;
    });
  }

  void _prevMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month - 1, 1);
    });
    _load();
  }

  void _nextMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month + 1, 1);
    });
    _load();
  }

  String _monthTitle() {
    return DateFormat('MMMM yyyy', 'ar').format(_month);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0F0F1A) : const Color(0xFFF1F5F9);
    const navy = Color(0xFF1E3A5F);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          title: const Text(
            'ورديات الشهر',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: Column(
          children: [
            Material(
              color: isDark ? const Color(0xFF1E1E2E) : Colors.white,
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _loading ? null : _nextMonth,
                      icon: const Icon(Icons.chevron_right_rounded),
                      tooltip: 'الشهر التالي',
                    ),
                    Expanded(
                      child: Text(
                        _monthTitle(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _loading ? null : _prevMonth,
                      icon: const Icon(Icons.chevron_left_rounded),
                      tooltip: 'الشهر السابق',
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'تظهر الورديات التي بدأت أو انتهت ضمن هذا الشهر (أو ما زالت مفتوحة وتمرّ بها). اسم «موظف الوردية» هو ما أُدخل عند فتح الوردية.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(
                          child: Text(
                            'لا توجد ورديات في هذا الشهر',
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 15,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                          itemCount: _rows.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final r = _rows[i];
                            final id = r['id'] as int;
                            final name =
                                (r['shiftStaffName'] as String?)?.trim() ??
                                    '—';
                            final opened = DateTime.tryParse(
                                  r['openedAt']?.toString() ?? '',
                                ) ??
                                DateTime.now();
                            final closedRaw = r['closedAt']?.toString();
                            final closed = closedRaw != null &&
                                    closedRaw.isNotEmpty
                                ? DateTime.tryParse(closedRaw)
                                : null;
                            final invN = _invoiceCounts[id] ?? 0;
                            final openStr = _dtFmt.format(opened);
                            final closeStr = closed != null
                                ? _dtFmt.format(closed)
                                : 'مفتوحة (لم تُغلق)';

                            return Container(
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1E1E2E)
                                    : Colors.white,
                                border: Border.all(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          color: navy.withValues(alpha: 0.1),
                                          child: Text(
                                            '#$id',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              color: navy,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          '$invN فاتورة',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    _rowLine(Icons.login_rounded, 'فتح', openStr),
                                    const SizedBox(height: 6),
                                    _rowLine(
                                      Icons.logout_rounded,
                                      'إغلاق',
                                      closeStr,
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
      ),
    );
  }

  Widget _rowLine(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w500,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, height: 1.3),
          ),
        ),
      ],
    );
  }
}
