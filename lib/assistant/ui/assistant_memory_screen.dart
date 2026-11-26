import 'dart:async';

import 'package:flutter/material.dart';

import '../data/assistant_memory_store.dart';

/// صفحة «ما أعرفه عنك» (4.11، م2-15): ما طلب المحل من المساعد تذكّره.
/// الكل يرى القائمة، والحذف لمن يملك [canDelete] (المالك و`settings.app`).
class AssistantMemoryScreen extends StatefulWidget {
  const AssistantMemoryScreen({super.key, required this.canDelete, this.store});

  static const routeName = '/assistant/memory';

  final bool canDelete;
  final AssistantMemoryStore? store;

  @override
  State<AssistantMemoryScreen> createState() => _AssistantMemoryScreenState();
}

class _AssistantMemoryScreenState extends State<AssistantMemoryScreen> {
  late final AssistantMemoryStore _store = widget.store ?? AssistantMemoryStore.instance;
  List<AssistantMemoryItem>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final items = await _store.list();
      if (mounted) setState(() => (_items = items, _failed = false));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _delete(AssistantMemoryItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('أحذف هذه المعلومة؟'),
        content: Text(item.text),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('احذف')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _store.delete(item.id);
      if (mounted) setState(() => _items = [...?_items]..removeWhere((x) => x.id == item.id));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ما گدرت أحذفها، تأكد من الإنترنت')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final items = _items;
    return Scaffold(
      appBar: AppBar(title: const Text('ما أعرفه عنك')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'هذه الأشياء طلبت من المساعد يتذكرها عن محلك، ويستعملها بكل جواب. '
              'تنحفظ بس لما تگول «تذكّر أن…».',
              style: t.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (_failed)
              const _Note(icon: Icons.wifi_off_rounded, text: 'ما گدرت أجيب القائمة. اسحب للتحديث.')
            else if (items == null)
              const Center(
                child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()),
              )
            else if (items.isEmpty)
              const _Note(
                icon: Icons.lightbulb_outline_rounded,
                text: 'ما محفوظ شي بعد. جرّب: «تذكّر إننا نغلق الجمعة».',
              )
            else ...[
              for (final x in items)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(x.text),
                    subtitle: x.createdBy == null ? null : Text('حفظها ${x.createdBy}'),
                    trailing: widget.canDelete
                        ? IconButton(
                            tooltip: 'احذف',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => unawaited(_delete(x)),
                          )
                        : null,
                  ),
                ),
              const SizedBox(height: 8),
              Text('${items.length} من 40', style: t.textTheme.bodySmall),
              if (!widget.canDelete) ...[
                const SizedBox(height: 8),
                Text('الحذف لصاحب المحل.', style: t.textTheme.bodySmall),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
