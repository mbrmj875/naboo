import 'package:flutter/material.dart';

import '../constants/common_allergies.dart';
import '../models/pharmacy_customer_ext.dart';
import '../services/pharmacy_customer_repository.dart';
import '../widgets/allergy_badge.dart';
import '../widgets/chronic_med_list.dart';

/// Bottom sheet — بيانات صيدلانية للعميل (حساسيات · أدوية مزمنة · ملاحظات).
class PharmacyCustomerDetailSheet extends StatefulWidget {
  const PharmacyCustomerDetailSheet({
    super.key,
    required this.tenantId,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    this.repository,
    this.onUpdated,
    this.initialData,
  });

  final int tenantId;
  final int customerId;
  final String customerName;
  final String? customerPhone;
  final PharmacyCustomerRepository? repository;
  final VoidCallback? onUpdated;

  /// للاختبارات — يتخطى التحميل غير المتزامن من DB.
  final PharmacyCustomerExt? initialData;

  static Future<void> show({
    required BuildContext context,
    required int tenantId,
    required int customerId,
    required String customerName,
    String? customerPhone,
    PharmacyCustomerRepository? repository,
    VoidCallback? onUpdated,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: PharmacyCustomerDetailSheet(
          tenantId: tenantId,
          customerId: customerId,
          customerName: customerName,
          customerPhone: customerPhone,
          repository: repository,
          onUpdated: onUpdated,
        ),
      ),
    );
  }

  @override
  State<PharmacyCustomerDetailSheet> createState() =>
      _PharmacyCustomerDetailSheetState();
}

class _PharmacyCustomerDetailSheetState extends State<PharmacyCustomerDetailSheet> {
  late final PharmacyCustomerRepository _repo =
      widget.repository ?? PharmacyCustomerRepository();

  final _notesCtrl = TextEditingController();
  List<String> _allergies = const [];
  List<PharmacyChronicMedication> _chronicMeds = const [];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialData;
    if (seed != null) {
      _allergies = List<String>.from(seed.allergies);
      _chronicMeds = List<PharmacyChronicMedication>.from(seed.chronicMedications);
      _notesCtrl.text = seed.medicalNotes ?? '';
      _loading = false;
      return;
    }
    _load();
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.ensureSchema();
      final ext = await _repo.getByCustomerId(
        tenantId: widget.tenantId,
        customerId: widget.customerId,
      );
      if (!mounted) return;
      setState(() {
        _allergies = List<String>.from(ext?.allergies ?? const []);
        _chronicMeds =
            List<PharmacyChronicMedication>.from(ext?.chronicMedications ?? const []);
        _notesCtrl.text = ext?.medicalNotes ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل البيانات الصيدلانية.';
      });
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final notes = _notesCtrl.text.trim();
      final ext = PharmacyCustomerExt(
        tenantId: widget.tenantId,
        customerId: widget.customerId,
        allergies: _allergies,
        chronicMedications: _chronicMeds,
        medicalNotes: notes.isEmpty ? null : notes,
      );
      await _repo.upsert(ext);
      widget.onUpdated?.call();
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر حفظ البيانات الصيدلانية.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addAllergy() async {
    String? selected = kCommonPharmacyAllergies.first.key;
    final customCtrl = TextEditingController();
    final added = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('إضافة حساسية'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: selected,
                    decoration: const InputDecoration(labelText: 'حساسية شائعة'),
                    items: [
                      for (final a in kCommonPharmacyAllergies)
                        DropdownMenuItem(
                          value: a.key,
                          child: Text(a.labelAr),
                        ),
                      const DropdownMenuItem(
                        value: '__custom__',
                        child: Text('نص حر…'),
                      ),
                    ],
                    onChanged: (v) => setLocal(() => selected = v),
                  ),
                  if (selected == '__custom__') ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: customCtrl,
                      decoration: const InputDecoration(
                        labelText: 'اسم الحساسية',
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: () {
                    if (selected == '__custom__') {
                      final custom = customCtrl.text.trim();
                      if (custom.isEmpty) return;
                      Navigator.pop(ctx, custom);
                      return;
                    }
                    if (selected == null || selected!.isEmpty) return;
                    Navigator.pop(ctx, selected);
                  },
                  child: const Text('إضافة'),
                ),
              ],
            );
          },
        );
      },
    );
    customCtrl.dispose();
    if (added == null || added.trim().isEmpty) return;
    final key = added.trim();
    if (_allergies.any((a) => a.toLowerCase() == key.toLowerCase())) return;
    setState(() => _allergies = [..._allergies, key]);
  }

  Future<void> _addChronicMed() async {
    final searchCtrl = TextEditingController();
    int? pickedProductId;
    String pickedName = '';
    DateTime startDate = DateTime.now();
    List<Map<String, dynamic>> hits = const [];

    final added = await showDialog<PharmacyChronicMedication>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return AlertDialog(
              title: const Text('إضافة دواء مزمن'),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        labelText: 'بحث عن دواء',
                        hintText: 'اسم المنتج أو الباركود',
                      ),
                      onChanged: (v) async {
                        final rows = await _repo.searchProducts(
                          tenantId: widget.tenantId,
                          query: v,
                        );
                        setLocal(() => hits = rows);
                      },
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: hits.length,
                        itemBuilder: (_, i) {
                          final row = hits[i];
                          final id = (row['id'] as num?)?.toInt() ?? 0;
                          final name = row['name']?.toString() ?? '';
                          return ListTile(
                            dense: true,
                            title: Text(name),
                            selected: pickedProductId == id,
                            onTap: () {
                              setLocal(() {
                                pickedProductId = id;
                                pickedName = name;
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: startDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                          helpText: 'تاريخ بدء الدواء',
                        );
                        if (picked != null) {
                          setLocal(() => startDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(
                        'تاريخ البداية: ${_formatPharmacyDate(startDate)}',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: pickedProductId == null || pickedName.isEmpty
                      ? null
                      : () {
                          Navigator.pop(
                            ctx,
                            PharmacyChronicMedication(
                              productId: pickedProductId!,
                              productName: pickedName,
                              startDate: startDate,
                            ),
                          );
                        },
                  child: const Text('إضافة'),
                ),
              ],
            );
          },
        );
      },
    );
    searchCtrl.dispose();
    if (added == null) return;
    if (_chronicMeds.any((m) => m.productId == added.productId)) return;
    setState(() => _chronicMeds = [..._chronicMeds, added]);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return const SizedBox(
        height: 240,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'بيانات العميل',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(widget.customerName),
            subtitle: widget.customerPhone?.trim().isNotEmpty == true
                ? Text(
                    widget.customerPhone!,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                  )
                : null,
          ),
          if (_error != null) ...[
            Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          Text(
            'حساسيات',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: cs.error,
            ),
          ),
          const SizedBox(height: 8),
          AllergyBadgeRow(
            allergies: _allergies,
            onDelete: (a) => setState(
              () => _allergies = _allergies.where((x) => x != a).toList(),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _saving ? null : _addAllergy,
              icon: const Icon(Icons.add),
              label: const Text('إضافة حساسية'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'أدوية مزمنة',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
          const SizedBox(height: 8),
          ChronicMedList(
            medications: _chronicMeds,
            onDelete: (m) => setState(
              () => _chronicMeds =
                  _chronicMeds.where((x) => x.productId != m.productId).toList(),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: _saving ? null : _addChronicMed,
              icon: const Icon(Icons.add),
              label: const Text('إضافة دواء مزمن'),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'ملاحظات طبية',
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            maxLines: 4,
            maxLength: PharmacyCustomerExt.maxMedicalNotesLength,
            decoration: const InputDecoration(
              hintText: 'أمراض مزمنة · ملاحظات عامة…',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: const Text('إلغاء'),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('حفظ'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// قسم مدمج في نموذج العميل — يفتح نفس الـ sheet.
class PharmacyCustomerExtensionSection extends StatelessWidget {
  const PharmacyCustomerExtensionSection({
    super.key,
    required this.tenantId,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    this.repository,
    required this.onUpdated,
  });

  final int tenantId;
  final int customerId;
  final String customerName;
  final String? customerPhone;
  final PharmacyCustomerRepository? repository;
  final VoidCallback onUpdated;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.medical_information_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'معلومات صيدلانية',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'حساسيات · أدوية مزمنة · ملاحظات طبية',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                PharmacyCustomerDetailSheet.show(
                  context: context,
                  tenantId: tenantId,
                  customerId: customerId,
                  customerName: customerName,
                  customerPhone: customerPhone,
                  repository: repository,
                  onUpdated: onUpdated,
                );
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('فتح البيانات الصيدلانية'),
            ),
          ],
        ),
      ),
    );
  }
}

/// شريط حساسيات للعرض في POS.
class PharmacyCustomerAllergiesBanner extends StatelessWidget {
  const PharmacyCustomerAllergiesBanner({
    super.key,
    required this.allergies,
  });

  final List<String> allergies;

  @override
  Widget build(BuildContext context) {
    if (allergies.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        border: Border.all(color: cs.error.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
              const SizedBox(width: 6),
              Text(
                'حساسيات العميل',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cs.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AllergyBadgeRow(allergies: allergies),
        ],
      ),
    );
  }
}

String _formatPharmacyDate(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y/$m/$d';
}
