import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../services/database_helper.dart';
import '../../services/inventory_repository.dart';
import '../../services/permission_service.dart';
import '../../services/tenant_context_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/app_logger.dart';
import '../../widgets/permission_guard.dart';

/// شاشة «الجرد الدوري» — نسخة Royal Gold:
/// - بطاقات بحواف `circular(12)` ومتوافقة مع الوضع الليلي.
/// - أزرار CTA ذهبية، شريط تقدّم ذهبي، شارات تنبيه ناعمة.
/// - بحث Debounced + حفظ Debounced لمنع تجمّد الواجهة وفقدان البيانات.

/// لون «الإنجاز» الموحَّد عبر الشاشة (مطابق + مكتمل + فائض).
/// لون ثابت يضمن تباينًا جيدًا في كلا الوضعين (لا يتغيّر مع ColorScheme).
const Color _kSuccessGreen = Color(0xFF15803D);

class StocktakingScreen extends StatefulWidget {
  const StocktakingScreen({super.key});

  @override
  State<StocktakingScreen> createState() => _StocktakingScreenState();
}

class _StocktakingScreenState extends State<StocktakingScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  final _repo = InventoryRepository();
  List<Map<String, dynamic>> _openSessions = const [];
  List<Map<String, dynamic>> _closedSessions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final openRows = await _repo.listStocktakingSessions(status: 'open');
      final closedRows = await _repo.listStocktakingSessions(status: 'closed');
      if (!mounted) return;
      setState(() {
        _openSessions = openRows;
        _closedSessions = closedRows;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.error('Stocktaking', 'failed to load sessions', e, st);
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الجلسات: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _newSession() async {
    final result =
        await showModalBottomSheet<({String title, int warehouseId})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NewSessionSheet(),
    );
    if (result == null || !mounted) return;
    try {
      await _repo.createStocktakingSession(
        title: result.title,
        warehouseId: result.warehouseId,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء جلسة الجرد بنجاح')),
      );
    } catch (e, st) {
      AppLogger.error('Stocktaking', 'create session failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر إنشاء الجلسة: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PermissionGuard(
      permissionKey: PermissionKeys.inventoryStocktakingManage,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            title: const Text(
              'الجرد الدوري',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            backgroundColor: cs.surface,
            foregroundColor: cs.onSurface,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(49),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TabBar(
                    controller: _tab,
                    indicatorColor: AppColors.accentGold,
                    indicatorWeight: 2.5,
                    labelColor: AppColors.accentGold,
                    unselectedLabelColor: cs.onSurfaceVariant,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    tabs: [
                      Tab(text: 'جلسات مفتوحة (${_openSessions.length})'),
                      Tab(text: 'مكتملة (${_closedSessions.length})'),
                    ],
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: AppColors.accentGold,
            foregroundColor: AppColors.primaryDark,
            onPressed: _newSession,
            icon: const Icon(Icons.fact_check_rounded),
            label: const Text(
              'بدء جرد جديد',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          body: _buildBody(cs),
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentGold),
      );
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    return TabBarView(
      controller: _tab,
      children: [
        _SessionList(
          sessions: _openSessions,
          onTap: (s) => _openCounting(context, s),
          onClose: _closeSession,
          emptyHint: 'ابدأ جلسة جرد جديدة لمستودعك من زرّ الأسفل.',
          emptyIcon: Icons.fact_check_outlined,
        ),
        _SessionList(
          sessions: _closedSessions,
          onTap: (s) => _openReport(context, s),
          emptyHint: 'لا توجد جلسات مكتملة بعد.',
          emptyIcon: Icons.archive_outlined,
        ),
      ],
    );
  }

  Future<void> _closeSession(Map<String, dynamic> s) async {
    var postDiffs = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
        return StatefulBuilder(
          builder: (context, setLocal) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            title: const Text('إقفال الجرد'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'هل تريد إقفال جلسة «${s['title']}»؟',
                  style: TextStyle(color: cs.onSurface),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: postDiffs,
                  activeColor: AppColors.accentGold,
                  onChanged: (v) => setLocal(() => postDiffs = v ?? true),
                  title: const Text('ترحيل الفروقات تلقائياً'),
                  subtitle: const Text('ينشئ سند تسوية مخزني واحد للجلسة'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentGold,
                  foregroundColor: AppColors.primaryDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'إقفال',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (ok != true || !mounted) return;
    try {
      if (postDiffs) {
        await _repo.postStocktakingAdjustments((s['id'] as num).toInt());
      }
      await _repo.closeStocktakingSession((s['id'] as num).toInt());
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إقفال الجلسة بنجاح')),
      );
    } catch (e, st) {
      AppLogger.error('Stocktaking', 'close session failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الإقفال: $e')),
      );
    }
  }

  void _openCounting(BuildContext ctx, Map<String, dynamic> s) {
    Navigator.push(
      ctx,
      MaterialPageRoute(builder: (_) => _CountingScreen(session: s)),
    ).then((_) => _load());
  }

  void _openReport(BuildContext ctx, Map<String, dynamic> s) {
    showModalBottomSheet(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SessionReportSheet(session: s),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session List
// ─────────────────────────────────────────────────────────────────────────────
class _SessionList extends StatelessWidget {
  const _SessionList({
    required this.sessions,
    required this.onTap,
    required this.emptyHint,
    required this.emptyIcon,
    this.onClose,
  });

  final List<Map<String, dynamic>> sessions;
  final void Function(Map<String, dynamic>) onTap;
  final void Function(Map<String, dynamic>)? onClose;
  final String emptyHint;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return _EmptyState(message: emptyHint, icon: emptyIcon);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
      itemCount: sessions.length,
      cacheExtent: 600,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) =>
          _SessionCard(data: sessions[i], onTap: onTap, onClose: onClose),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.data,
    required this.onTap,
    this.onClose,
  });

  final Map<String, dynamic> data;
  final void Function(Map<String, dynamic>) onTap;
  final void Function(Map<String, dynamic>)? onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isOpen = data['status'] == 'open';
    final total = (data['totalItems'] as num?)?.toInt() ?? 0;
    final counted = (data['countedItems'] as num?)?.toInt() ?? 0;
    final progress = total > 0 ? (counted / total).clamp(0.0, 1.0) : 0.0;

    // ألوان دلالية ثابتة (لا تعتمد على cs.primary الذي يتفاوت بين النمطين).
    final accent = isOpen ? AppColors.accentGold : _kSuccessGreen;
    final radius = BorderRadius.circular(12);
    // خلفية صلبة بدل النصف-شفّاف لضمان تباين النصوص في كلا الوضعين.
    final cardBg = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.85)
        : cs.surfaceContainerLowest;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(data),
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: radius,
            border: Border.all(
              color: isOpen
                  ? AppColors.accentGold.withValues(alpha: 0.6)
                  : cs.outlineVariant.withValues(alpha: 0.7),
              width: isOpen ? 1.4 : 1,
            ),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isOpen
                          ? Icons.pending_actions_rounded
                          : Icons.check_circle_rounded,
                      color: accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['title']?.toString() ?? '',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              Icons.warehouse_outlined,
                              size: 13,
                              color: cs.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                data['warehouseName']?.toString() ?? '—',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.5),
                        width: 0.9,
                      ),
                    ),
                    child: Text(
                      isOpen ? 'مفتوح' : 'مكتمل',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Progress
              Row(
                children: [
                  Text(
                    '$counted / $total صنف',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor:
                      cs.surfaceContainerHighest.withValues(alpha: 0.6),
                  color: accent,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.calendar_today_outlined,
                    size: 13,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      isOpen
                          ? 'بدأ: ${_fmtDate(data['startedAt']?.toString())}'
                          : 'أُقفل: ${_fmtDate(data['closedAt']?.toString())}',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  if (isOpen && onClose != null)
                    TextButton.icon(
                      onPressed: () => onClose!(data),
                      icon: const Icon(
                        Icons.lock_rounded,
                        size: 14,
                        color: AppColors.accentGold,
                      ),
                      label: const Text(
                        'إقفال الجرد',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.accentGold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => onTap(data),
                      icon: const Icon(
                        Icons.bar_chart_rounded,
                        size: 14,
                        color: _kSuccessGreen,
                      ),
                      label: const Text(
                        'التقرير',
                        style: TextStyle(
                          fontSize: 12,
                          color: _kSuccessGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return DateFormat('yyyy-MM-dd', 'en').format(dt.toLocal());
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty / Error states
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.accentGold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.accentGold),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد جلسات',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: cs.error),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurface),
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New Session Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _NewSessionSheet extends StatefulWidget {
  const _NewSessionSheet();

  @override
  State<_NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends State<_NewSessionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _warehouses = const [];
  int? _warehouseId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    try {
      final rows = await _db.listWarehousesActive(
        tenantId: TenantContextService.instance.activeTenantId,
      );
      if (!mounted) return;
      setState(() {
        _warehouses = rows;
        _warehouseId ??= rows.isNotEmpty
            ? (rows.first['id'] as num).toInt()
            : null;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.error('Stocktaking', 'load warehouses failed', e, st);
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String label,
    String? hint,
    IconData? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null
          ? null
          : Icon(icon, size: 20, color: cs.onSurfaceVariant),
      filled: true,
      fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
      ),
      isDense: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.fact_check_rounded,
                      color: AppColors.accentGold,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'بدء جلسة جرد جديدة',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleCtrl,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: _inputDecoration(
                  context,
                  label: 'عنوان الجلسة *',
                  hint: 'مثال: جرد شهر يوليو 2025',
                  icon: Icons.title_rounded,
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.accentGold,
                      ),
                    ),
                  ),
                )
              else
                DropdownButtonFormField<int>(
                  initialValue: _warehouseId,
                  isExpanded: true,
                  decoration: _inputDecoration(
                    context,
                    label: 'المستودع',
                    icon: Icons.warehouse_outlined,
                  ),
                  items: _warehouses
                      .map(
                        (w) => DropdownMenuItem<int>(
                          value: (w['id'] as num).toInt(),
                          child: Text(w['name']?.toString() ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _warehouseId = v),
                  validator: (v) => v == null ? 'اختر مستودعاً' : null,
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loading
                    ? null
                    : () {
                        if (!_formKey.currentState!.validate()) return;
                        Navigator.pop(context, (
                          title: _titleCtrl.text.trim(),
                          warehouseId: _warehouseId!,
                        ));
                      },
                icon: const Icon(Icons.fact_check_rounded),
                label: const Text(
                  'بدء الجرد',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentGold,
                  foregroundColor: AppColors.primaryDark,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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

// ─────────────────────────────────────────────────────────────────────────────
// Counting Screen
// ─────────────────────────────────────────────────────────────────────────────
class _CountingScreen extends StatefulWidget {
  const _CountingScreen({required this.session});

  final Map<String, dynamic> session;

  @override
  State<_CountingScreen> createState() => _CountingScreenState();
}

class _CountingScreenState extends State<_CountingScreen> {
  final _searchCtrl = TextEditingController();
  final _repo = InventoryRepository();
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _items = const [];
  bool _loading = true;
  String? _error;

  static const _kSearchDebounce = Duration(milliseconds: 320);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _repo.listStocktakingItems(
        (widget.session['id'] as num).toInt(),
        search: _searchCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _items = rows;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.error('Stocktaking', 'load items failed', e, st);
      if (!mounted) return;
      setState(() {
        _error = 'تعذّر تحميل الأصناف: $e';
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(_kSearchDebounce, _load);
  }

  int get _countedCount =>
      _items.where((i) => i['countedQty'] != null).length;

  /// يُستدعى من بطاقة الصنف بعد debounce داخلي. يحدّث الصف محليًا أيضًا
  /// لتجنّب إعادة تحميل القائمة كاملة عند كل ضغطة زر.
  Future<void> _persistCount({
    required int itemId,
    required double? qty,
  }) async {
    try {
      await _repo.saveStocktakingCount(
        itemId: itemId,
        countedQty: qty ?? 0,
      );
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((it) => (it['id'] as num).toInt() == itemId);
        if (idx == -1) return;
        final sys = (_items[idx]['systemQty'] as num?)?.toDouble() ?? 0;
        final updated = Map<String, dynamic>.from(_items[idx]);
        if (qty == null) {
          updated['countedQty'] = null;
          updated['difference'] = null;
        } else {
          updated['countedQty'] = qty;
          updated['difference'] = qty - sys;
        }
        _items = [
          for (var i = 0; i < _items.length; i++)
            if (i == idx) updated else _items[i],
        ];
      });
    } catch (e, st) {
      AppLogger.error('Stocktaking', 'save count failed', e, st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر حفظ الكمية: $e')),
      );
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = _items.length;
    final progress = total == 0 ? 0.0 : (_countedCount / total).clamp(0.0, 1.0);

    return PermissionGuard(
      permissionKey: PermissionKeys.inventoryStocktakingManage,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            backgroundColor: cs.surface,
            foregroundColor: cs.onSurface,
            elevation: 0,
            scrolledUnderElevation: 0,
            surfaceTintColor: Colors.transparent,
            shape: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            title: Text(
              widget.session['title']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              Center(
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
                  child: Container(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.accentGold.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.accentGold.withValues(alpha: 0.5),
                        width: 0.9,
                      ),
                    ),
                    child: Text(
                      '$_countedCount / $total',
                      style: const TextStyle(
                        color: AppColors.accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              // Progress bar
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor:
                        cs.surfaceContainerHighest.withValues(alpha: 0.6),
                    color: AppColors.accentGold,
                    minHeight: 6,
                  ),
                ),
              ),
              // Search
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 10),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'بحث بالاسم أو الباركود…',
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: cs.onSurfaceVariant,
                    ),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'مسح',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                              setState(() {});
                            },
                          ),
                    filled: true,
                    fillColor:
                        cs.surfaceContainerHighest.withValues(alpha: 0.35),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.accentGold,
                        width: 2,
                      ),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(child: _buildItemsBody(cs)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemsBody(ColorScheme cs) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.accentGold),
      );
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _load);
    }
    if (_items.isEmpty) {
      return _EmptyState(
        message: _searchCtrl.text.trim().isEmpty
            ? 'لا توجد أصناف في هذه الجلسة.'
            : 'لا نتائج مطابقة للبحث.',
        icon: Icons.inventory_2_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 80),
      itemCount: _items.length,
      cacheExtent: 800,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final item = _items[i];
        return _CountItem(
          key: ValueKey('count-${item['id']}'),
          item: item,
          onCommit: (qty) => _persistCount(
            itemId: (item['id'] as num).toInt(),
            qty: qty,
          ),
        );
      },
    );
  }
}

class _CountItem extends StatefulWidget {
  const _CountItem({super.key, required this.item, required this.onCommit});

  final Map<String, dynamic> item;

  /// `qty == null` يعني تفريغ الكمية (لم تُعَدّ بعد).
  final Future<void> Function(double? qty) onCommit;

  @override
  State<_CountItem> createState() => _CountItemState();
}

class _CountItemState extends State<_CountItem> {
  late final TextEditingController _ctrl;
  Timer? _saveDebounce;

  static const _kSaveDebounce = Duration(milliseconds: 500);

  @override
  void initState() {
    super.initState();
    final countedQty = widget.item['countedQty'];
    _ctrl = TextEditingController(
      text: countedQty == null
          ? ''
          : (countedQty as num).toDouble().toStringAsFixed(
                _isInt(countedQty) ? 0 : 2,
              ),
    );
  }

  bool _isInt(num n) => (n.toDouble() - n.truncate()).abs() < 1e-9;

  double? get _diff {
    final c = double.tryParse(_ctrl.text);
    if (c == null) return null;
    return c - ((widget.item['systemQty'] as num?)?.toDouble() ?? 0);
  }

  void _scheduleSave(String text) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_kSaveDebounce, () {
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        widget.onCommit(null);
      } else {
        final v = double.tryParse(trimmed);
        if (v != null && v >= 0) {
          widget.onCommit(v);
        }
      }
    });
    setState(() {}); // refresh diff label
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCounted = widget.item['countedQty'] != null;
    final diff = _diff;
    final isMatch = isCounted && diff != null && diff.abs() < 1e-9;

    // Status palette (تباين جيد في كلا الوضعين — ألوان دلالية ثابتة):
    // - مطابق  ← ذهبي (هوية النظام).
    // - فائض   ← أخضر هادئ ثابت.
    // - نقص    ← cs.error (يستجيب للنمط).
    // - لم يُعَدّ ← cs.onSurfaceVariant.
    final Color statusColor;
    final IconData statusIcon;
    if (!isCounted) {
      statusColor = cs.onSurfaceVariant;
      statusIcon = Icons.pending_outlined;
    } else if (isMatch) {
      statusColor = AppColors.accentGold;
      statusIcon = Icons.check_circle_rounded;
    } else if ((diff ?? 0) > 0) {
      statusColor = _kSuccessGreen;
      statusIcon = Icons.trending_up_rounded;
    } else {
      statusColor = cs.error;
      statusIcon = Icons.trending_down_rounded;
    }

    final cardBg = isDark
        ? cs.surfaceContainerHighest.withValues(alpha: 0.85)
        : cs.surfaceContainerLowest;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCounted
              ? statusColor.withValues(alpha: 0.6)
              : cs.outlineVariant.withValues(alpha: 0.7),
          width: isCounted ? 1.2 : 1,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 10),
          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item['name']?.toString() ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: cs.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'النظام: ${_fmtQty((widget.item['systemQty'] as num?)?.toDouble() ?? 0)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (diff != null && diff.abs() > 1e-9) ...[
                      const SizedBox(width: 10),
                      Text(
                        'فرق: ${diff > 0 ? '+' : ''}${_fmtQty(diff)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Count input
          SizedBox(
            width: 86,
            child: TextField(
              controller: _ctrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
              decoration: InputDecoration(
                hintText: 'العدّ',
                hintStyle: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
                filled: true,
                fillColor: cs.surface,
                contentPadding: const EdgeInsetsDirectional.symmetric(
                  vertical: 10,
                  horizontal: 8,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: cs.outlineVariant.withValues(alpha: 0.7),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: AppColors.accentGold,
                    width: 1.5,
                  ),
                ),
              ),
              onChanged: _scheduleSave,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtQty(double v) {
    if ((v - v.truncate()).abs() < 1e-9) {
      return v.toStringAsFixed(0);
    }
    return v.toStringAsFixed(2);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Session Report Sheet
// ─────────────────────────────────────────────────────────────────────────────
class _SessionReportSheet extends StatelessWidget {
  const _SessionReportSheet({required this.session});

  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = (session['totalItems'] as num?)?.toInt() ?? 0;
    final counted = (session['countedItems'] as num?)?.toInt() ?? 0;
    final missing = (total - counted).clamp(0, total);
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.accentGold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.bar_chart_rounded,
                    color: AppColors.accentGold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'تقرير: ${session['title']}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.6)),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      _ReportBadge(
                        label: 'إجمالي الأصناف',
                        value: '$total',
                        color: AppColors.accentGold,
                      ),
                      const SizedBox(width: 10),
                      _ReportBadge(
                        label: 'تم عدّه',
                        value: '$counted',
                        color: _kSuccessGreen,
                      ),
                      const SizedBox(width: 10),
                      _ReportBadge(
                        label: 'غير معدود',
                        value: '$missing',
                        color: cs.error,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'ملخّص الجلسة',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _summaryRow(
                    context,
                    name: 'إنجاز العَدّ',
                    sys: total,
                    cnt: counted,
                    diff: counted - total,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context, {
    required String name,
    required int sys,
    required int cnt,
    required int diff,
  }) {
    final cs = Theme.of(context).colorScheme;
    final color = diff == 0
        ? AppColors.accentGold
        : (diff > 0 ? _kSuccessGreen : cs.error);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          Text(
            'المتوقع: $sys',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Text(
            'الفعلي: $cnt',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(width: 12),
          Text(
            '${diff > 0 ? '+' : ''}$diff',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportBadge extends StatelessWidget {
  const _ReportBadge({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
