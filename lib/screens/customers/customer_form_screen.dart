import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/customer_record.dart';
import '../../services/database_helper.dart';
import '../../theme/design_tokens.dart';
import '../../utils/customer_validation.dart';

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

  late final TextEditingController _nameCtrl;
  final List<TextEditingController> _phoneCtrls = [];
  late final TextEditingController _addressCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _notesCtrl;

  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _phoneCtrls.add(TextEditingController(text: e?.phone ?? ''));
    _addressCtrl = TextEditingController(text: e?.address ?? '');
    _emailCtrl = TextEditingController(text: e?.email ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
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
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final c in _phoneCtrls) {
      c.dispose();
    }
    _addressCtrl.dispose();
    _emailCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? v) => CustomerValidation.name(v);
  String? _validateEmail(String? v) => CustomerValidation.optionalEmail(v);
  String? _validatePhone(String? v) => CustomerValidation.optionalPhone(v);

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

      final data = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'phone': primary ?? '',
        'address': _addressCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
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
          email: (data['email'] as String).isEmpty
              ? null
              : data['email'] as String?,
          address: (data['address'] as String).isEmpty
              ? null
              : data['address'] as String?,
          notes: (data['notes'] as String).isEmpty
              ? null
              : data['notes'] as String?,
          extraPhones: extra,
        );
      } else {
        final newId = await _db.insertCustomer(
          name: data['name'] as String,
          phone: (data['phone'] as String).isEmpty
              ? null
              : data['phone'] as String?,
          email: (data['email'] as String).isEmpty
              ? null
              : data['email'] as String?,
          address: (data['address'] as String).isEmpty
              ? null
              : data['address'] as String?,
          notes: (data['notes'] as String).isEmpty
              ? null
              : data['notes'] as String?,
          extraPhones: extra,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
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
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          title: Text(
            _isEdit ? 'تعديل بيانات العميل' : 'إضافة عميل جديد',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: _saving ? null : () => Navigator.pop(context),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                                        ? 'مثال: 07701234567 — لا يُكرَّر لعميل آخر (يُميّز الأسماء المتشابهة)'
                                        : 'مثال: 07801234567',
                                    icon: Icons.phone_outlined,
                                    keyboardType: TextInputType.phone,
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
                                color: cs.primary,
                              ),
                              label: Text(
                                'إضافة رقم آخر',
                                style: TextStyle(
                                  color: cs.primary,
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
                        controller: _emailCtrl,
                        label: 'البريد الإلكتروني (اختياري)',
                        hint: 'example@domain.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 14),
                      _CustomerFormField(
                        controller: _notesCtrl,
                        label: 'ملاحظات (اختياري)',
                        hint: 'تفضيلات العميل، ملاحظات داخلية…',
                        icon: Icons.notes_outlined,
                        maxLines: 3,
                      ),
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
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text('إلغاء'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _saving ? null : _submit,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 14,
                            ),
                            shape: const RoundedRectangleBorder(
                              borderRadius: AppShape.none,
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
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;
  final bool autofocus;

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
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          maxLines: maxLines,
          autofocus: autofocus,
          style: TextStyle(fontSize: 14, color: cs.onSurface),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: cs.onSurfaceVariant.withValues(alpha: 0.75),
              fontSize: 13,
            ),
            prefixIcon: icon != null
                ? Icon(icon, size: 20, color: cs.onSurfaceVariant)
                : null,
            filled: true,
            fillColor: cs.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: AppShape.none,
              borderSide: BorderSide(color: outline.withValues(alpha: 0.55)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppShape.none,
              borderSide: BorderSide(color: outline.withValues(alpha: 0.55)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppShape.none,
              borderSide: BorderSide(color: cs.primary, width: 1.5),
            ),
            errorBorder: const OutlineInputBorder(
              borderRadius: AppShape.none,
              borderSide: BorderSide(color: Colors.red, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }
}
