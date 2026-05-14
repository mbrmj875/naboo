import 'package:flutter/material.dart';
import 'dart:async' show unawaited;
import 'package:provider/provider.dart';

import '../../models/customer_record.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../providers/customers_provider.dart';
import '../../utils/screen_layout.dart';
import 'customer_financial_detail_screen.dart';
import 'customer_form_screen.dart';
import 'customers_screen.dart';

enum _ContactSort {
  nameAsc,
  balanceDesc,
}

/// تصفية جهات الاتصال: دين/آجل مقابل أقساط.
enum _ContactFilter {
  /// عرض الجميع
  all,
  /// فواتير آجل أو رصيد مدين — للمتابعة والاتصال بمن عليهم دين
  debtOrCreditSale,
  /// وجود خطة تقسيط — للمتابعة والاتصال بخصوص الأقساط
  hasInstallments,
}

/// قائمة جهات اتصال العملاء — عرض منظم من قاعدة البيانات مع ربط التعديل والتفاصيل المالية.
class CustomerContactsScreen extends StatefulWidget {
  const CustomerContactsScreen({super.key});

  @override
  State<CustomerContactsScreen> createState() => _CustomerContactsScreenState();
}

class _CustomerContactsScreenState extends State<CustomerContactsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _idCtrl = TextEditingController();

  String _appliedText = '';
  String _appliedId = '';
  _ContactFilter _filter = _ContactFilter.all;
  _ContactSort _sort = _ContactSort.nameAsc;

  Color get _pageBg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _primary => Theme.of(context).colorScheme.primary;
  Color get _onPrimary => Theme.of(context).colorScheme.onPrimary;
  Color get _filterBg =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
  Color get _textPrimary => Theme.of(context).colorScheme.onSurface;
  Color get _textSecondary => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _outline => Theme.of(context).colorScheme.outline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CustomersProvider>().refresh();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  List<CustomerRecord> _visible(
    List<CustomerRecord> input,
    Map<int, ({int creditInvoices, int installmentPlans})> financeById,
  ) {
    var list = input.where((c) {
      if (!_passesContactFilter(c, financeById)) return false;
      return true;
    }).toList();

    // الترتيب هنا فقط للعرض. الترتيب الأساسي يأتي من الاستعلام المصفح في [CustomersProvider].
    if (_sort == _ContactSort.balanceDesc) {
      list.sort((a, b) => b.balance.abs().compareTo(a.balance.abs()));
    }
    return list;
  }

  bool _passesContactFilter(
    CustomerRecord c,
    Map<int, ({int creditInvoices, int installmentPlans})> financeById,
  ) {
    final fin = financeById[c.id] ?? (creditInvoices: 0, installmentPlans: 0);
    switch (_filter) {
      case _ContactFilter.all:
        return true;
      case _ContactFilter.debtOrCreditSale:
        return fin.creditInvoices > 0 || c.balance > 0.01;
      case _ContactFilter.hasInstallments:
        return fin.installmentPlans > 0;
    }
  }

  void _applySearch() {
    setState(() {
      _appliedText = _searchCtrl.text;
      _appliedId = _idCtrl.text;
    });
    unawaited(
      context.read<CustomersProvider>().setFilters(
            query: _appliedText,
            idQuery: _appliedId,
            statusArabic: 'الكل',
            sortKey: _sort == _ContactSort.balanceDesc ? 'balance_desc' : 'name_asc',
          ),
    );
  }

  void _clearFilters() {
    setState(() {
      _searchCtrl.clear();
      _idCtrl.clear();
      _appliedText = '';
      _appliedId = '';
      _filter = _ContactFilter.all;
      _sort = _ContactSort.nameAsc;
    });
    unawaited(
      context.read<CustomersProvider>().setFilters(
            query: '',
            idQuery: '',
            statusArabic: 'الكل',
            sortKey: 'name_asc',
          ),
    );
  }

  Future<void> _openEditor({CustomerRecord? customer}) async {
    final saved = await Navigator.of(context).push<CustomerRecord?>(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(existing: customer),
      ),
    );
    if (saved != null && mounted) {
      context.read<CustomersProvider>().onCustomerChanged();
    }
  }

  void _openFinancialDetail(CustomerRecord c) {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CustomerFinancialDetailScreen(customer: c),
      ),
    );
  }

  Future<void> _confirmDelete(CustomerRecord c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف جهة الاتصال'),
        content: Text('حذف «${c.name}» من النظام؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await DatabaseHelper().deleteCustomer(c.id);
      CloudSyncService.instance.scheduleSyncSoon();
      context.read<CustomersProvider>().onCustomerChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الحذف: $e')),
        );
      }
    }
  }

  void _openAdvancedCustomers() {
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => const CustomersScreen(),
        ),
      );
    }

  Color _statusColor(String label) {
    switch (label) {
      case 'مديون':
        return const Color(0xFFFF9800);
      case 'دائن':
        return const Color(0xFF7E57C2);
      default:
        return const Color(0xFF00897B);
    }
  }

  Color _avatarColor(int id) {
    final cs = Theme.of(context).colorScheme;
    final colors = <Color>[
      cs.primary,
      cs.secondary,
      cs.tertiary,
      Color.lerp(cs.primary, cs.secondary, 0.45)!,
    ];
    return colors[id % colors.length];
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _primary,
      foregroundColor: _onPrimary,
          elevation: 0,
      centerTitle: false,
          title: const Text(
            'جهات اتصال العملاء',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'تحديث',
          onPressed: () => context.read<CustomersProvider>().refresh(),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  Widget _buildToolbar(int shown) {
    final gap = ScreenLayout.of(context).pageHorizontalGap;
    return Material(
      color: _surface,
      elevation: 1,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: Padding(
        padding: EdgeInsets.fromLTRB(gap, 10, gap, 10),
        child: Row(
            children: [
            Expanded(
              child: Text(
                'المعروض: $shown',
                style: TextStyle(fontSize: 13, color: _textSecondary),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openEditor(),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
              ),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
                  label: const Text(
                    'عميل جديد',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required _ContactFilter filter,
    required String label,
    String? tooltip,
  }) {
    final selected = _filter == filter;
    final chip = FilterChip(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13.5,
          color: selected ? _primary : _textPrimary,
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _filter = filter),
      selectedColor: _primary.withValues(alpha: 0.2),
      checkmarkColor: _primary,
      showCheckmark: false,
      side: BorderSide(
        color: selected ? _primary : _outline.withValues(alpha: 0.55),
        width: selected ? 1.5 : 1,
      ),
    );
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(message: tooltip, child: chip);
    }
    return chip;
  }

  /// حقول البحث والترتيب والأزرار — تطوى مع التمرير (فوق شريط التصفية الثابت).
  Widget _buildFiltersScrollCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _filterBg,
        borderRadius: AppShape.none,
        border: Border.all(color: _outline.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 200,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ترتيب',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: AppShape.none,
                        border: Border.all(
                          color: _outline.withValues(alpha: 0.55),
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<_ContactSort>(
                          isExpanded: true,
                          value: _sort,
                          items: const [
                            DropdownMenuItem(
                              value: _ContactSort.nameAsc,
                              child: Text('الاسم (أ-ي)'),
                            ),
                            DropdownMenuItem(
                              value: _ContactSort.balanceDesc,
                              child: Text('حجم الرصيد'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _sort = v);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Expanded(child: SizedBox.shrink()),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, c) {
              final row = c.maxWidth >= 560;
              final searchField = TextField(
                controller: _searchCtrl,
                onSubmitted: (_) => _applySearch(),
                decoration: InputDecoration(
                  labelText: 'بحث بالاسم أو الهاتف أو البريد',
                  hintText: 'مثال: محمد، 077…، name@…',
                  filled: true,
                  fillColor: _surface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: AppShape.none,
                    borderSide: BorderSide(color: _outline.withValues(alpha: 0.55)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppShape.none,
                    borderSide: BorderSide(color: _outline.withValues(alpha: 0.55)),
                  ),
                  prefixIcon: Icon(Icons.search, color: _textSecondary, size: 22),
                ),
              );
              final idField = TextField(
                controller: _idCtrl,
                onSubmitted: (_) => _applySearch(),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'رقم المعرف / الكود',
                  hintText: 'مثال: 12 أو 000012',
                  filled: true,
                  fillColor: _surface,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: AppShape.none,
                    borderSide: BorderSide(color: _outline.withValues(alpha: 0.55)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppShape.none,
                    borderSide: BorderSide(color: _outline.withValues(alpha: 0.55)),
                  ),
                  prefixIcon: Icon(Icons.tag, color: _textSecondary, size: 22),
                ),
              );
              if (row) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 3, child: searchField),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: idField),
                  ],
                );
              }
              return Column(
                children: [
                  searchField,
                  const SizedBox(height: 12),
                  idField,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _applySearch,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('تطبيق البحث'),
                style: FilledButton.styleFrom(
                  shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('مسح التصفية'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _textPrimary,
                  side: BorderSide(color: _outline),
                  shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
                ),
              ),
              TextButton.icon(
                onPressed: _openAdvancedCustomers,
                icon: Icon(Icons.manage_accounts_outlined, color: _primary, size: 20),
                label: Text(
                  'إدارة العملاء الكاملة',
                  style: TextStyle(color: _primary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// شريط التصفية (الكل / دين / أقساط) — ثابت أثناء التمرير مثل تبويبات الفواتير.
  Widget _buildContactFilterChipsStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(
          bottom: BorderSide(color: _outline.withValues(alpha: 0.35)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildFilterChip(
              filter: _ContactFilter.all,
              label: 'الكل',
            ),
            const SizedBox(width: 10),
            _buildFilterChip(
              filter: _ContactFilter.debtOrCreditSale,
              label: 'عليهم دين أو آجل',
              tooltip:
                  'فواتير بيع آجل غير مرتجعة، أو رصيد مدين على الحساب — للاتصال بخصوص الدين.',
            ),
            const SizedBox(width: 10),
            _buildFilterChip(
              filter: _ContactFilter.hasInstallments,
              label: 'عليهم أقساط',
              tooltip:
                  'لديهم خطة تقسيط مسجّلة — للاتصال بخصوص الأقساط.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final noData =
        context.read<CustomersProvider>().items.isEmpty &&
        _appliedText.trim().isEmpty &&
        _appliedId.trim().isEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: AppShape.none,
        border: Border.all(color: _outline.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Icon(Icons.contact_phone_outlined, size: 56, color: _textSecondary),
          const SizedBox(height: 12),
          Text(
            noData
                ? 'لا توجد جهات اتصال بعد'
                : 'لا توجد نتائج مطابقة. غيّر البحث أو أضف عميلاً.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _textSecondary, fontSize: 15),
          ),
          if (noData) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('إضافة أول عميل'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tableHeader(bool narrow) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 12, vertical: 12),
      decoration: BoxDecoration(color: _filterBg),
      child: narrow
          ? Row(
              children: [
                const SizedBox(width: 44),
        Text(
                  'الرصيد',
          style: TextStyle(
            fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: _textPrimary,
                  ),
                ),
                Expanded(
                  child: Text(
                    'العميل',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _textPrimary,
                    ),
                  ),
                ),
              ],
            )
          : const Row(
              children: [
                SizedBox(width: 44),
                SizedBox(
                  width: 88,
                  child: Text(
                    'الحالة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'الرصيد',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'البريد',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'الهاتف',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: Text(
                    'العميل',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
            ),
    );
  }

  /// شارات «آجل / تقسيط» من قاعدة البيانات — تظهر بجانب الاسم للتمييز السريع.
  Widget _financeBadges(
    CustomerRecord c,
    Map<int, ({int creditInvoices, int installmentPlans})> financeById,
  ) {
    final fin = financeById[c.id] ?? (creditInvoices: 0, installmentPlans: 0);
    if (fin.creditInvoices == 0 && fin.installmentPlans == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
          children: [
          if (fin.creditInvoices > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFF9800).withValues(alpha: 0.16),
                borderRadius: AppShape.none,
                border: Border.all(
                  color: const Color(0xFFFF9800).withValues(alpha: 0.45),
                ),
              ),
                child: Text(
                'بيع آجل ×${fin.creditInvoices}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFE65100),
                ),
              ),
            ),
          if (fin.installmentPlans > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00897B).withValues(alpha: 0.14),
                borderRadius: AppShape.none,
                border: Border.all(
                  color: const Color(0xFF00897B).withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                'تقسيط ×${fin.installmentPlans}',
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF00695C),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tableRow(
    CustomerRecord c,
    bool narrow,
    Map<int, ({int creditInvoices, int installmentPlans})> financeById,
  ) {
    final initial = c.name.isNotEmpty ? c.name.substring(0, 1) : '?';
    final idStr = '#${c.id.toString().padLeft(5, '0')}';
    final phone = (c.phone?.trim().isNotEmpty == true) ? c.phone! : '—';
    final email = (c.email?.trim().isNotEmpty == true) ? c.email! : '—';
    final av = _avatarColor(c.id);
    final st = c.statusLabel;
    final bal = IraqiCurrencyFormat.formatIqd(c.balance);

    return Material(
      color: _surface,
      child: InkWell(
        onTap: () => _openFinancialDetail(c),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 10, vertical: 10),
          child: narrow
              ? Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
                    _rowMenu(c),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          bal,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _statusColor(st).withValues(alpha: 0.15),
                            borderRadius: AppShape.none,
                          ),
                          child: Text(
                            st,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _statusColor(st),
                            ),
                          ),
                ),
              ],
            ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: av.withValues(alpha: 0.2),
                            foregroundColor: av,
                            child: Text(
                              initial,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 10),
          Expanded(
            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                                  c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  idStr,
                                  style: TextStyle(fontSize: 11.5, color: _textSecondary),
                                ),
                                _financeBadges(c, financeById),
                                if (phone != '—') ...[
                                  const SizedBox(height: 4),
                                  Row(
                    children: [
                                      Icon(Icons.phone_outlined, size: 14, color: _textSecondary),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                        phone,
                        style: TextStyle(
                                            fontSize: 12.5,
                                            color: _textSecondary,
                                            fontWeight: FontWeight.w600,
                        ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                      ),
                                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                    _rowMenu(c),
                    SizedBox(
                      width: 88,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(st).withValues(alpha: 0.15),
                            borderRadius: AppShape.none,
                          ),
                          child: Text(
                            st,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _statusColor(st),
                            ),
                          ),
                        ),
                      ),
                    ),
                      Expanded(
                      flex: 2,
                        child: Text(
                        bal,
                        textAlign: TextAlign.center,
                          style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          ),
                        ),
                      ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        email,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12.5, color: _textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        phone,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: _textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: av.withValues(alpha: 0.2),
                            foregroundColor: av,
                            child: Text(
                              initial,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                    child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                                Text(
                                  c.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  idStr,
                                  style: TextStyle(fontSize: 11.5, color: _textSecondary),
                                ),
                                _financeBadges(c, financeById),
                              ],
                            ),
                        ),
                      ],
                    ),
                  ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _rowMenu(CustomerRecord c) {
    return SizedBox(
      width: 44,
      child: PopupMenuButton<String>(
        tooltip: 'إجراءات',
        shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
        onSelected: (v) {
          if (v == 'edit') _openEditor(customer: c);
          if (v == 'detail') _openFinancialDetail(c);
          if (v == 'delete') _confirmDelete(c);
        },
        itemBuilder: (ctx) => [
          const PopupMenuItem(value: 'detail', child: Text('التفاصيل المالية')),
          const PopupMenuItem(value: 'edit', child: Text('تعديل البيانات')),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.more_vert, color: _textSecondary),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CustomersProvider>(
      builder: (context, prov, _) {
        final loading = prov.isLoading && prov.items.isEmpty;
        final financeById = prov.financeById;
        final visible = _visible(prov.items, financeById);
        final total = visible.length;

        final gap = ScreenLayout.of(context).pageHorizontalGap;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: _pageBg,
            appBar: _buildAppBar(),
            body: loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 720;
                      return NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.extentAfter < 360) {
                            unawaited(prov.loadMore());
                          }
                          return false;
                        },
                        child: CustomScrollView(
                          slivers: [
                            SliverToBoxAdapter(
                              child: _buildToolbar(total),
                            ),
                            SliverPadding(
                              padding: EdgeInsets.fromLTRB(gap, 0, gap, 12),
                              sliver: SliverToBoxAdapter(
                                child: _buildFiltersScrollCard(),
                              ),
                            ),
                            SliverPersistentHeader(
                              pinned: true,
                              delegate: _StickyContactFiltersDelegate(
                                background: _surface,
                                outline: _outline,
                                child: _buildContactFilterChipsStrip(),
                              ),
                            ),
                            if (total == 0)
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(gap, 12, gap, 24),
                                sliver: SliverToBoxAdapter(
                                  child: _buildEmptyState(),
                                ),
                              )
                            else ...[
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(gap, 12, gap, 0),
                                sliver: SliverToBoxAdapter(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _surface,
                                      borderRadius: AppShape.none,
                                      border: Border.all(
                                        color: _outline.withValues(alpha: 0.35),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.04),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      children: [
                                        _tableHeader(narrow),
                                        const Divider(height: 1),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SliverPadding(
                                padding: EdgeInsets.fromLTRB(gap, 0, gap, 24),
                                sliver: SliverList(
                                  delegate: SliverChildBuilderDelegate(
                                    (context, i) {
                                      if (i >= visible.length) return null;
                                      final c = visible[i];
                                      return Column(
                                        children: [
                                          if (i > 0)
                                            Divider(
                                              height: 1,
                                              color: _outline.withValues(alpha: 0.35),
                                            ),
                                          Container(
                                            decoration: BoxDecoration(
                                              color: _surface,
                                              border: Border(
                                                left: BorderSide(
                                                  color: _outline.withValues(alpha: 0.35),
                                                ),
                                                right: BorderSide(
                                                  color: _outline.withValues(alpha: 0.35),
                                                ),
                                              ),
                                            ),
                                            child: _tableRow(c, narrow, financeById),
                                          ),
                                          if (i == visible.length - 1)
                                            Container(
                                              height: 1,
                                              color: _outline.withValues(alpha: 0.35),
                                            ),
                                        ],
                                      );
                                    },
                                    childCount: visible.length,
                                  ),
                                ),
                              ),
                            ],
                            if (prov.isLoadingMore)
                              const SliverToBoxAdapter(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(vertical: 16),
                                  child: Center(child: CircularProgressIndicator()),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _StickyContactFiltersDelegate extends SliverPersistentHeaderDelegate {
  _StickyContactFiltersDelegate({
    required this.child,
    required this.background,
    required this.outline,
  });

  final Widget child;
  final Color background;
  final Color outline;

  @override
  double get minExtent => 60;

  @override
  double get maxExtent => 60;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: background,
      elevation: overlapsContent ? 2 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.1),
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _StickyContactFiltersDelegate oldDelegate) {
    return oldDelegate.child != child ||
        oldDelegate.background != background ||
        oldDelegate.outline != outline;
  }
}
