import 'dart:async';

import 'package:flutter/material.dart';

import '../exec/assistant_reminders.dart';
import 'assistant_view_models.dart' show isolateLtr;

/// «تذكيراتي» (م4-11): ما طلبه المستخدم من المساعد أن يذكّره به، لهذا
/// المستخدم وحده على هذا الجهاز. الحذف يلغي الإشعار المجدول أيضاً.
class AssistantRemindersScreen extends StatefulWidget {
  const AssistantRemindersScreen({
    super.key,
    required this.store,
    required this.tenantId,
    required this.userKey,
    required this.onCancel,
  });

  static const routeName = '/assistant/reminders';

  final AssistantReminderStore store;
  final String tenantId;
  final String userKey;
  final Future<void> Function(int id) onCancel;

  @override
  State<AssistantRemindersScreen> createState() => _AssistantRemindersScreenState();
}

class _AssistantRemindersScreenState extends State<AssistantRemindersScreen> {
  List<AssistantReminder>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await widget.store.list(tenantId: widget.tenantId, userKey: widget.userKey);
      if (mounted) setState(() => (_items = items, _failed = false));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _delete(AssistantReminder r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ألغي هذا التذكير؟'),
        content: Text(r.text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ألغِه')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.onCancel(r.id);
    if (mounted) setState(() => _items = [...?_items]..removeWhere((x) => x.id == r.id));
  }

  static const _days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  static String when(DateTime w, DateTime now) {
    final d = DateTime(w.year, w.month, w.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = d.difference(today).inDays;
    final day = switch (diff) {
      0 => 'اليوم',
      1 => 'باچر',
      _ => '${_days[w.weekday - 1]} ${w.day}/${w.month}',
    };
    final h = w.hour % 12 == 0 ? 12 : w.hour % 12;
    final m = w.minute.toString().padLeft(2, '0');
    return '$day $h:$m ${w.hour < 12 ? 'صباحاً' : 'مساءً'}';
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = _items;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: const Text('تذكيراتي')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'اطلب من المساعد «ذكّرني باچر الساعة 10 أتصل بالمورّد»، ويطلع لك إشعار بوقته. '
              'التذكيرات على هذا الجهاز ولك وحدك.',
              style: t.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (_failed)
              const Text('ما گدرت أقرأ التذكيرات. اسحب للتحديث.')
            else if (items == null)
              const Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const Text('ما عندك تذكيرات قادمة.')
            else
              for (final r in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.alarm_outlined),
                    title: Text(isolateLtr(r.text)),
                    subtitle: Text(isolateLtr(when(r.when, now))),
                    trailing: IconButton(
                      tooltip: 'ألغِ التذكير',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => unawaited(_delete(r)),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
