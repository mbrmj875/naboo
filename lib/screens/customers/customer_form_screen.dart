import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/customer_record.dart';
import '../../utils/app_logger.dart';
import '../../utils/screen_layout.dart';
import '../../services/database_helper.dart';
import '../../services/price_list_repository.dart';
import '../../services/tenant_context_service.dart';
import '../../verticals/_contract/vertical_registry.dart';
import '../../theme/design_tokens.dart';
import '../../utils/customer_validation.dart';
import '../../widgets/adaptive/adaptive_form_container.dart';

/// صفحة إضافة أو تعديل عميل — بدون نافذة منبثقة؛ مرتبطة بجدول [customers] وباقي التطبيق.
///
/// عند نجاح الحفظ تُرجع [Navigator.pop] قيمة [CustomerRecord] للشاشة النافذة (مثل البيع).
class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.existing});

  /// `null` = إضافة جديدة، وإلا تعديل.
  final CustomerRecord? existing;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final DatabaseHelper _db = DatabaseHelper();
  final PriceListRepository _priceLists = PriceListRepository();

  late final TextEditingController _nameCtrl;
  final List<TextEditingController> _phoneCtrls = [];
  late final TextEditingController _addressCtrl;
  late final TextEditingController _notesCtrl;

  bool _saving = false;
  int? _tenantId;

  /// قائمة الأسعار المختارة للعميل (`null` = استخدام الافتراضي العام).
  int? _selectedPriceListId;
  bool _priceListsLoading = true;
  List<Map<String, dynamic>> _priceListOptions = const [];

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _phoneCtrls.add(TextEditingController(text: e?.phone ?? ''));
    _addressCtrl = TextEditingController(text: e?.address ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _selectedPriceListId = e?.priceListId;
    if (e != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final extras = await _db.getCustomerExtraPhones(e.id);
        if (!mounted || extras.isEmpty) return;
        setState(() {
          for (final p in extras) {
            _phoneCtrls.add(TextEditingController(text: p));
          }
        });
      });
    }
    _loadPriceLists();
    _loadTenantId();
  }

  Future<void> _loadTenantId() async {
    try {
      final tenant = TenantContextService.instance;
      if (!tenant.loaded) await tenant.load();
      if (!mounted) return;
      setState(() => _tenantId = tenant.requireActiveTenantId());
    } catch (e, st) {
      AppLogger.error('CustomerForm', 'failed to load tenant', e, st);
    }
  }

  Future<void> _loadPriceLists() async {
    try {
      final lists = await _priceLists.listPriceLists();
      if (!mounted) return;
      final activeIds = lists
          .map((l) => (l['id'] as num?)?.toInt())
          .whereType<int>()
          .toSet();
      setState(() {
        _priceListOptions = lists;
        _priceListsLoading = false;
        if (_selectedPriceListId != null &&
            !activeIds.contains(_selectedPriceListId)) {
          _selectedPriceListId = null;
        }
      });
    } catch (e, st) {
      AppLogger.error('CustomerForm', 'failed to load price lists', e, st);
      if (!mounted) return;
      setState(() => _priceListsLoading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _phoneCtrls) {
      c.dispose();
    }
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? v) => CustomerValidation.name(v);
  String? _validatePhone(String? v) => CustomerValidation.iraqiMobilePhone(v);

  static final _iraqiPhoneInputFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
    LengthLimitingTextInputFormatter(11),
  ];

  List<String> _phonesInOrder() {
    return _phoneCtrls
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  void _addEmptyPhoneField() {
    if (_saving) return;
    setState(() => _phoneCtrls.add(TextEditingController()));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final phones = _phonesInOrder();
      final primary = phones.isEmpty ? null : phones.first;
      final extra = phones.length <= 1 ? <String>[] : phones.sublist(1);

      final normalizedPrimary = primary == null
          ? null
          : CustomerValidation.normalizePhoneDigits(primary);
      final normalizedExtra = extra
          .map(CustomerValidation.normalizePhoneDigits)
          .whereType<String>()
          .toList();

      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'phone': normalizedPrimary ?? '',
        'address': _addressCtrl.text.trim(),
        'notes': _notesCtrl.text.trim(),
      };

      if (_isEdit) {
        final id = widget.existing!.id;
        await _db.updateCustomer(
          id: id,
          name: data['name'] as String,
          phone: (data['phone'] as String).isEmpty
              ? null
              : data['phone'] as String?,
          email: widget.existing?.email,
          address: (data['address'] as String).isEmpty
              ? null
              : data['address'] as String?,
          notes: (data['notes'] as String).isEmpty
              ? null
              : data['notes'] as String?,
          extraPhones: normalizedExtra,
          priceListId: _selectedPriceListId,
        );
      } else {
        final newId = await _db.insertCustomer(
          name: data['name'] as String,
          phone: (data['phone'] as String).isEmpty
              ? null
              : data['phone'] as String?,
          email: null,
          address: (data['address'] as String).isEmpty
              ? null
              : data['address'] as String?,
          notes: (data['notes'] as String).isEmpty
              ? null
              : data['notes'] as String?,
          extraPhones: normalizedExtra,
          priceListId: _selectedPriceListId,
        );
        final row = await _db.getCustomerById(newId);
        if (!mounted) return;
        if (row == null) {
          throw StateError('تعذر تحميل بيانات العميل بعد الإضافة');
        }
        Navigator.pop(context, CustomerRecord.fromMap(row));
        return;
      }

      final id = widget.existing!.id;
      final row = await _db.getCustomerById(id);
      if (!mounted) return;
      if (row == null) throw StateError('تعذر تحميل بيانات العميل');
      Navigator.pop(context, CustomerRecord.fromMap(row));
    } catch (e) {
      if (mounted) {
        final msg = e is DuplicateCustomerPhoneException
            ? e.message
            : 'تعذر الحفظ: $e';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final created = widget.existing?.createdAt;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHighest,
          foregroundColor: cs.onSurface,
          iconTheme: IconThemeData(color: cs.onSurface),
          elevation: 0,
          title: Text(
            _isEdit ? 'تعديل بيانات العميل' : 'إضافة عميل جديد',
            style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
          ),
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new_rounded, color: cs.onSurface),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
        ),
        body: AdaptiveFormContainer(
          child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsetsDirectional.only(
                  start: ScreenLayout.of(context).pageHorizontalGap,
                  end: ScreenLayout.of(context).pageHorizontalGap,
                  top: 16,
                  bottom: 24,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (created != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'مسجّل منذ ${DateFormat('yyyy/MM/dd', 'en').format(created)}',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      Text(
                        'املأ البيانات الأساسية. يمكن ترك الحقول الاختيارية فارغة.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _CustomerFormField(
                        controller: _nameCtrl,
                        label: 'اسم العميل',
                        hint: 'الاسم الكامل كما يظهر في الفواتير',
                        icon: Icons.person_outline,
                        autofocus: !_isEdit,
                        validator: _validateName,
                      ),
                      const SizedBox(height: 14),
                      for (var i = 0; i < _phoneCtrls.length; i++) ...[
                        Builder(
                          builder: (context) {
                            final idx = i;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: _CustomerFormField(
                                    controller: _phoneCtrls[idx],
                                    label: idx == 0
                                        ? 'رقم الهاتف (اختياري)'
                                        : 'رقم هاتف إضافي',
                                    hint: idx == 0
                                        ? '07701234567 — 11 رقمًا يبدأ بـ 07'
                                        : '07801234567 — 11 رقمًا يبدأ بـ 07',
                                    icon: Icons.phone_outlined,
                                    keyboardType: TextInputType.phone,
                                    textDirection: TextDirection.ltr,
                                    inputFormatters: _iraqiPhoneInputFormatters,
                                    validator: _validatePhone,
                                  ),
                                ),
                                if (idx > 0) ...[
                                  const SizedBox(width: 4),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 28),
                                    child: IconButton(
                                      tooltip: 'حذف الرقم',
                                      onPressed: _saving
                                          ? null
                                          : () {
                                              setState(() {
                                                _phoneCtrls[idx].dispose();
                                                _phoneCtrls.removeAt(idx);
                                              });
                                            },
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                        if (i == 0) ...[
                          const SizedBox(height: 4),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              onPressed: _saving ? null : _addEmptyPhoneField,
                              icon: Icon(
                                Icons.add_circle_outline_rounded,
                                size: 20,
                                color: AppColors.accentGold,
                              ),
                              label: Text(
                                'إضافة رقم آخر',
                                style: TextStyle(
                                  color: AppColors.accentGold,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                      ],
                      _CustomerFormField(
                        controller: _addressCtrl,
                        label: 'العنوان (اختياري)',
                        hint: 'المدينة، المنطقة',
                        icon: Icons.location_on_outlined,
                      ),
                      const SizedBox(height: 14),
                      _CustomerFormField(
                        controller: _notesCtrl,
                        label: 'ملاحظات (اختياري)',
                        hint: 'تفضيلات العميل، ملاحظات داخلية…',
                        icon: Icons.notes_outlined,
                        maxLines: 3,
                      ),
                      const SizedBox(height: 14),
                      _PriceListPicker(
                        loading: _priceListsLoading,
                        options: _priceListOptions,
                        selectedId: _selectedPriceListId,
                        onChanged: _saving
                            ? null
                            : (id) => setState(() => _selectedPriceListId = id),
                      ),
                      if (_isEdit && widget.existing!.id > 0 && _tenantId != null)
                        ...[
                          const SizedBox(height: 14),
                          VerticalRegistry.instance.activeManifest
                                  .buildCustomerExtensionSection(
                                context: context,
                                tenantId: _tenantId!,
                                customerId: widget.existing!.id,
                                customerName: _nameCtrl.text.trim().isEmpty
                                    ? widget.existing!.name
                                    : _nameCtrl.text.trim(),
                                customerPhone: _phonesInOrder().isEmpty
                                    ? widget.existing!.phone
                                    : _phonesInOrder().first,
                                onUpdated: () {
                                  if (mounted) setState(() {});
                                },
                              ) ??
                              const SizedBox.shrink(),
                        ],
                    ],
                  ),
                ),
              ),
            ),
            Material(
              elevation: 8,
              color: cs.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: ScreenLayout.of(context).pageHorizontalGap,
                    end: ScreenLayout.of(context).pageHorizontalGap,
                    top: 10,
                    bottom: 12,
                  ),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          style: TextButton.styleFrom(foregroundColor: cs.onSurface),
                          child: const Text('إلغاء'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _saving ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.accentGold.withValues(alpha: 0.2),
                            foregroundColor: AppColors.accentGold,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _saving
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: cs.onPrimary,
                                  ),
                                )
                              : const Text('حفظ'),
                        ),
                      ],
                    ),
                  ),
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

class _CustomerFormField extends StatelessWidget {
  const _CustomerFormField({
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.autofocus = false,
    this.inputFormatters,
    this.textDirection,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final outline = cs.outline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.accentGold,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          autofocus: autofocus,
          inputFormatters: inputFormatters,
          textDirection: textDirection,
          style: TextStyle(fontSize: 14, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.75),
              fontSize: 13,
            ),
            prefixIcon: icon != null
                ? Icon(icon, size: 20, color: AppColors.accentGold)
                : null,
            filled: true,
            fillColor: cs.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}

class _PriceListPicker extends StatelessWidget {
  const _PriceListPicker({
    required this.loading,
    required this.options,
    required this.selectedId,
    required this.onChanged,
  });

  final bool loading;
  final List<Map<String, dynamic>> options;
  final int? selectedId;
  final ValueChanged<int?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final outline = cs.outline;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'قائمة الأسعار للعميل (اختياري)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.accentGold,
          ),
        ),
        const SizedBox(height: 6),
        if (loading)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border.all(color: outline.withValues(alpha: 0.55)),
              borderRadius: AppShape.none,
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Text(
                  'جاري تحميل القوائم…',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else
          DropdownButtonFormField<int?>(
            initialValue: selectedId,
            isExpanded: true,
            onChanged: onChanged,
            dropdownColor: cs.surfaceContainerHighest,
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.price_change_outlined,
                size: 20,
                color: AppColors.accentGold,
              ),
              filled: true,
              fillColor: cs.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.accentGold, width: 2),
              ),
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('استخدام الأسعار الافتراضية'),
              ),
              for (final l in options)
                DropdownMenuItem<int?>(
                  value: (l['id'] as num?)?.toInt(),
                  child: Row(
                    children: [
                      if (((l['isDefault'] as int?) ?? 0) == 1)
                        const Padding(
                          padding: EdgeInsetsDirectional.only(end: 6),
                          child: Icon(
                            Icons.star_rounded,
                            size: 16,
                            color: AppColors.accentGold,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          (l['name'] as String?) ?? '—',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        const SizedBox(height: 4),
        Text(
          'عند ترك الخيار افتراضيًا، يطبَّق هرم الأسعار العام تلقائيًا في الفواتير.',
          style: TextStyle(
            fontSize: 11.5,
            color: cs.onSurfaceVariant.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}
