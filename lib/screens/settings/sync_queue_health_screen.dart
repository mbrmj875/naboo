import 'package:flutter/material.dart';

import '../../services/cloud_sync_service.dart';
import '../../services/sync_queue_service.dart';

class SyncQueueHealthScreen extends StatefulWidget {
  const SyncQueueHealthScreen({super.key});

  @override
  State<SyncQueueHealthScreen> createState() => _SyncQueueHealthScreenState();
}

class _SyncQueueHealthScreenState extends State<SyncQueueHealthScreen> {
  bool _busy = false;
  String? _message;
  List<Map<String, dynamic>> _blockingMutations = const [];
  Map<String, int> _stats = const {
    'pending': 0,
    'failed': 0,
    'dead': 0,
    'synced': 0,
  };

  bool get _hasClockSkew => _blockingMutations.any((row) {
        final err = (row['last_error'] ?? '').toString().toLowerCase();
        return err.contains('clock_skew_rejected');
      });

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final stats = await SyncQueueService.instance.getQueueStats();
      if (!mounted) return;
      setState(() => _stats = stats);

      try {
        final blocking =
            await SyncQueueService.instance.getRecentBlockingMutations();
        if (!mounted) return;
        setState(() => _blockingMutations = blocking);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _message =
              'تعذر قراءة تفاصيل العمليات المتعثرة: $e';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'تعذر قراءة حالة الطابور: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _retryAll() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final count = await SyncQueueService.instance.retryAllFailedAndDead();
      await SyncQueueService.instance.processQueue();
      // دورة ثانية بعد إصلاح clock_skew المحتملة في الدفعة الأولى.
      await SyncQueueService.instance.processQueue();
      final stats = await SyncQueueService.instance.getQueueStats();
      final blocking =
          await SyncQueueService.instance.getRecentBlockingMutations();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _blockingMutations = blocking;
        _message = count > 0
            ? 'تمت إعادة جدولة $count عملية فاشلة/ميتة وإعادة الإرسال.'
            : 'لا توجد عمليات فاشلة أو ميتة لإعادة المحاولة.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'تعذرت إعادة المحاولة: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _syncNow() async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await CloudSyncService.instance.syncNow(
        forcePull: true,
        forcePush: true,
        forceImportOnPull: true,
      );
      await SyncQueueService.instance.processQueue();
      await SyncQueueService.instance.processQueue();
      final stats = await SyncQueueService.instance.getQueueStats();
      final blocking =
          await SyncQueueService.instance.getRecentBlockingMutations();
      final err = CloudSyncService.instance.lastError.value;
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _blockingMutations = blocking;
        _message = err ?? 'تمت المزامنة وفحص الطابور بنجاح.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _message = 'فشلت المزامنة: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  int _count(String key) => _stats[key] ?? 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pending = _count('pending');
    final failed = _count('failed');
    final dead = _count('dead');
    final healthy = pending == 0 && failed == 0 && dead == 0;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('حالة المزامنة والعمليات العالقة'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 24),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      healthy
                          ? 'الحالة العامة: سليمة'
                          : 'الحالة العامة: تحتاج متابعة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: healthy ? Colors.green : Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'هذه الشاشة تساعدك على اكتشاف العمليات غير المرفوعة ومنع فقدان البيانات عند تبديل الحساب أو تسجيل الخروج.',
                      style: TextStyle(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
            if (_hasClockSkew) ...[
              const SizedBox(height: 10),
              Card(
                color: cs.errorContainer.withValues(alpha: 0.35),
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'انحراف ساعة الجهاز عن السيرفر',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'رُفضت بعض العمليات لأن وقت الجهاز متقدم عن وقت السيرفر بأكثر من 5 دقائق. اضبط التاريخ/الوقت التلقائي في إعدادات الهاتف، ثم اضغط «إعادة محاولة العمليات الفاشلة/الميتة».',
                        style: TextStyle(height: 1.4, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _StatTile(
              label: 'عمليات معلّقة',
              count: pending,
              color: Colors.orange,
              icon: Icons.schedule_rounded,
            ),
            _StatTile(
              label: 'عمليات فاشلة',
              count: failed,
              color: Colors.redAccent,
              icon: Icons.error_outline_rounded,
            ),
            _StatTile(
              label: 'عمليات ميتة',
              count: dead,
              color: Colors.red,
              icon: Icons.dangerous_outlined,
            ),
            if (_blockingMutations.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'أحدث العمليات المتعثرة (failed/dead)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      for (final row in _blockingMutations.take(8))
                        _BlockingMutationTile(row: row),
                    ],
                  ),
                ),
              ),
            ],
            _StatTile(
              label: 'عمليات متزامنة',
              count: _count('synced'),
              color: Colors.green,
              icon: Icons.check_circle_outline_rounded,
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<String?>(
              valueListenable: CloudSyncService.instance.lastError,
              builder: (_, err, __) {
                if ((err ?? '').trim().isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    err!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                );
              },
            ),
            if (_message != null) ...[
              Text(
                _message!,
                style: TextStyle(
                  color: _message!.contains('تعذر') || _message!.contains('فشل')
                      ? Colors.red
                      : Colors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _syncNow,
              icon: const Icon(Icons.sync),
              label: const Text('مزامنة الآن'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _retryAll,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة محاولة العمليات الفاشلة/الميتة'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _busy ? null : _reload,
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('تحديث الحالة'),
            ),
            if (_busy) ...[
              const SizedBox(height: 8),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label),
        trailing: Text(
          '$count',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
    );
  }
}

class _BlockingMutationTile extends StatelessWidget {
  const _BlockingMutationTile({required this.row});

  final Map<String, dynamic> row;

  static String _friendlyError(String lastError) {
    final lower = lastError.toLowerCase();
    if (lower.contains('clock_skew_rejected')) {
      return 'رفض بسبب انحراف ساعة الجهاز عن السيرفر (أكثر من 5 دقائق). '
          'اضبط وقت الهاتف ثم أعد المحاولة.';
    }
    return lastError;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final status = (row['status'] ?? '').toString();
    final isDead = status == 'dead';
    final retryCount = (row['retry_count'] as num?)?.toInt() ?? 0;
    final entityType = (row['entity_type'] ?? '').toString();
    final operation = (row['operation'] ?? '').toString();
    final mutationId = (row['mutation_id'] ?? '').toString();
    final lastError = (row['last_error'] ?? '').toString().trim();
    final when = ((row['last_attempt_at'] ?? row['created_at']) ?? '')
        .toString()
        .trim();

    return Container(
      margin: const EdgeInsetsDirectional.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDead
            ? cs.errorContainer.withValues(alpha: 0.28)
            : cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDead ? cs.error : cs.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${isDead ? 'ميتة' : 'فاشلة'} · $entityType · $operation',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: isDead ? cs.error : cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'retry=$retryCount · ${mutationId.isEmpty ? 'بدون mutation_id' : mutationId}',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          if (when.isNotEmpty)
            Text(
              'آخر محاولة: $when',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          if (lastError.isNotEmpty)
            Text(
              'السبب: ${_friendlyError(lastError)}',
              style: TextStyle(
                fontSize: 12,
                color: isDead ? cs.error : cs.onSurfaceVariant,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
