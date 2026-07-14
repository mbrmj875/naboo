import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../../utils/iraqi_currency_format.dart';
import '../../../utils/iqd_money.dart';
import '../../_contract/vertical_manifest.dart';
import '../models/pharmacy_dosage_form.dart';
import '../models/pharmacy_drug_reference.dart';
import '../models/pharmacy_manufacturer.dart';
import '../models/pharmacy_manufacturer_type.dart';
import '../models/pharmacy_rx_schedule.dart';
import 'pharmacy_product_editor_form.dart';

/// تخطيط خطوة واحدة في المعالج — `null` = كل الأقسام (دمج Core).
enum PharmacyProductEditorStepLayout {
  modeA1DrugReference,
  modeA2Commercial,
  modeA3BatchRx,
  modeA4PricingNotes,
  modeB1DrugCommercial,
  modeB2BatchPricing,
  modeC1DrugReference,
  modeC2Manufacturer,
  modeC3FormStrength,
  modeC4BatchExpiry,
  modeC5PricingQty,
  modeC6Notes,
}

/// أقسام نموذج الدواء — قابلة للدمج في Core أو شاشة Mode A.
class PharmacyProductEditorSections extends StatefulWidget {
  const PharmacyProductEditorSections({
    super.key,
    required this.controller,
    required this.onChanged,
    this.onDrugReferenceSelected,
    this.onBatchDraftChanged,
    this.showBatchAndQty = true,
    this.stepLayout,
    this.notesController,
  });

  final PharmacyProductEditorFormController controller;
  final VoidCallback onChanged;
  final void Function(VerticalPharmacyDrugReferenceSnapshot reference)?
      onDrugReferenceSelected;
  final void Function(VerticalPharmacyBatchDraftSnapshot batch)?
      onBatchDraftChanged;
  final bool showBatchAndQty;
  final PharmacyProductEditorStepLayout? stepLayout;
  final TextEditingController? notesController;

  @override
  State<PharmacyProductEditorSections> createState() =>
      PharmacyProductEditorSectionsState();
}

class PharmacyProductEditorSectionsState
    extends State<PharmacyProductEditorSections> {
  PharmacyProductEditorFormController get _form => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_form.load().then((_) {
      if (mounted) setState(() {});
    }));
    for (final c in [
      _form.strengthCtrl,
      _form.batchCtrl,
      _form.costFilsCtrl,
      _form.qtyCtrl,
    ]) {
      c.addListener(_notifyBatchDraft);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _form.strengthCtrl,
      _form.batchCtrl,
      _form.costFilsCtrl,
      _form.qtyCtrl,
    ]) {
      c.removeListener(_notifyBatchDraft);
    }
    super.dispose();
  }

  void _notifyBatchDraft() {
    final draft = _form.currentBatchDraft();
    if (draft != null) {
      widget.onBatchDraftChanged?.call(draft);
    }
    widget.onChanged();
    setState(() {});
  }

  void _notifyChanged() {
    widget.onChanged();
    setState(() {});
  }

  Future<void> _tryAutoSelectReference(String query) async {
    final q = query.trim();
    if (q.isEmpty || _form.selectedReference != null) return;
    final tenantId = _form.tenantId;
    if (tenantId == null) return;

    final matches = await _form.catalog.searchDrugReferences(
      tenantId: tenantId,
      query: q,
    );
    if (matches.length == 1) {
      _form.selectReference(matches.single);
      widget.onDrugReferenceSelected
          ?.call(PharmacyDrugReferenceSnapshot(matches.single));
      _notifyChanged();
      return;
    }

    final normalized = q.toLowerCase();
    for (final match in matches) {
      if (match.nameAr.trim().toLowerCase() == normalized ||
          match.nameEn.trim().toLowerCase() == normalized) {
        _form.selectReference(match);
        widget.onDrugReferenceSelected
            ?.call(PharmacyDrugReferenceSnapshot(match));
        _notifyChanged();
        return;
      }
    }
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _form.expiryDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 15),
      helpText: 'اختر تاريخ الصلاحية',
      cancelText: 'إلغاء',
      confirmText: 'تأكيد',
    );
    if (picked == null) return;
    _form.setExpiryDate(picked);
    _notifyBatchDraft();
  }

  Widget buildDrugReferenceSection() {
    if (_form.loadingCatalog) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_form.loadError != null) {
      return Text(_form.loadError!);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PharmacyEditorSectionTitle(title: 'ابحث عن مادة فعّالة'),
        Autocomplete<PharmacyDrugReference>(
          key: ValueKey('drug_ref_${_form.formGeneration}'),
          displayStringForOption: (option) =>
              option.nameAr.isNotEmpty ? option.nameAr : option.nameEn,
          optionsBuilder: (value) async {
            final q = value.text.trim();
            final tenantId = _form.tenantId;
            if (q.isEmpty || tenantId == null) {
              return const Iterable.empty();
            }
            return _form.catalog.searchDrugReferences(
              tenantId: tenantId,
              query: q,
            );
          },
          onSelected: (option) {
            _form.selectReference(option);
            widget.onDrugReferenceSelected
                ?.call(PharmacyDrugReferenceSnapshot(option));
            _notifyChanged();
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: AlignmentDirectional.topStart,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240, maxWidth: 520),
                  child: options.isEmpty
                      ? Padding(
                          padding: const EdgeInsetsDirectional.all(12),
                          child: Text(
                            'لا توجد نتائج — اختر «إنشاء جديد» أو أكمل الحفظ',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              title: Text(
                                option.nameAr.isNotEmpty
                                    ? option.nameAr
                                    : option.nameEn,
                              ),
                              subtitle: option.atcCode == null
                                  ? null
                                  : Text('ATC: ${option.atcCode}'),
                              onTap: () => onSelected(option),
                            );
                          },
                        ),
                ),
              ),
            );
          },
          fieldViewBuilder: (context, textEditingController, focusNode, onSubmitted) {
            if (_form.drugReferenceController.text != textEditingController.text) {
              textEditingController.value = _form.drugReferenceController.value;
            }
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: 'اسم عربي / إنجليزي / ATC',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search),
                helperText: _form.selectedReference == null &&
                        textEditingController.text.trim().isNotEmpty
                    ? 'اختر من القائمة — أو سيُنشأ مرجع جديد عند الحفظ'
                    : null,
              ),
              onChanged: (value) {
                _form.drugReferenceController.text = value;
                if (_form.selectedReference != null) {
                  _form.clearSelectedReference();
                }
                _notifyChanged();
              },
              onSubmitted: (_) async {
                await _tryAutoSelectReference(textEditingController.text);
                onSubmitted();
              },
            );
          },
        ),
        if (_form.selectedReference != null) ...[
          const SizedBox(height: 8),
          PharmacyEditorReadOnlyBlock(
            lines: [
              'ATC: ${_form.selectedReference!.atcCode ?? '—'}',
              'الدواعي: ${_formatIndications(_form.selectedReference!)}',
              'تفاعلات (placeholder): ${_formatList(_form.selectedReference!.interactionsPlaceholder)}',
            ],
          ),
        ],
      ],
    );
  }

  Widget buildManufacturerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PharmacyEditorSectionTitle(title: 'الشركة'),
        if (_form.manufacturers.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 8),
            child: Text(
              'لا توجد شركات بعد — أضف شركة من إعدادات كتالوج الدواء',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        DropdownButtonFormField<PharmacyManufacturer>(
          value: _form.selectedManufacturer,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          hint: const Text('اختر الشركة'),
          items: _form.manufacturers
              .map(
                (m) => DropdownMenuItem(value: m, child: Text(m.name)),
              )
              .toList(),
          onChanged: (value) {
            _form.selectedManufacturer = value;
            _notifyChanged();
          },
        ),
        if (_form.selectedManufacturer != null) ...[
          const SizedBox(height: 8),
          PharmacyEditorReadOnlyBlock(
            lines: [
              'التصنيف: ${_manufacturerTypeLabel(_form.selectedManufacturer!.type)}',
              'الجودة: ${_form.selectedManufacturer!.qualityTier ?? '—'}',
              'البلد: ${_form.selectedManufacturer!.countryCode ?? '—'}',
            ],
          ),
        ],
      ],
    );
  }

  Widget buildDosageFormSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PharmacyEditorSectionTitle(title: 'الشكل الصيدلاني'),
        if (_form.dosageForms.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: 8),
            child: Text(
              'لا توجد أشكال صيدلانية بعد — أضف شكلاً من إعدادات كتالوج الدواء',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ),
        DropdownButtonFormField<PharmacyDosageForm>(
          value: _form.selectedDosageForm,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          hint: const Text('اختر الشكل'),
          items: _form.dosageForms
              .map(
                (f) => DropdownMenuItem(value: f, child: Text(f.nameAr)),
              )
              .toList(),
          onChanged: (value) {
            _form.selectedDosageForm = value;
            _notifyChanged();
          },
        ),
        if (_form.selectedDosageForm != null) ...[
          const SizedBox(height: 8),
          PharmacyEditorReadOnlyBlock(
            lines: [
              _form.selectedDosageForm!.isSplittable
                  ? 'قابل للتجزئة'
                  : 'غير قابل للتجزئة',
            ],
          ),
        ],
      ],
    );
  }

  Widget buildStrengthAndRxSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PharmacyEditorSectionTitle(title: 'التركيز'),
        TextField(
          controller: _form.strengthCtrl,
          decoration: const InputDecoration(
            hintText: '500 mg · 1000 mg',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _notifyChanged(),
        ),
        const SizedBox(height: 20),
        const PharmacyEditorSectionTitle(title: 'Rx / OTC'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: PharmacyRxSchedule.otc, label: Text('OTC')),
            ButtonSegment(value: PharmacyRxSchedule.rx, label: Text('Rx')),
          ],
          selected: {_form.rxSchedule},
          onSelectionChanged: (selection) {
            _form.rxSchedule = selection.first;
            _notifyChanged();
          },
        ),
      ],
    );
  }

  Widget buildBatchAndExpirySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PharmacyEditorSectionTitle(title: 'دفعة (Batch)'),
        TextField(
          controller: _form.batchCtrl,
          decoration: const InputDecoration(
            hintText: 'B2401',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _notifyBatchDraft(),
        ),
        const SizedBox(height: 20),
        const PharmacyEditorSectionTitle(title: 'صلاحية (Expiry)'),
        TextField(
          controller: _form.expiryCtrl,
          readOnly: true,
          decoration: InputDecoration(
            hintText: 'اختر التاريخ',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: _pickExpiryDate,
            ),
          ),
          onTap: _pickExpiryDate,
        ),
      ],
    );
  }

  Widget buildPricingAndQtySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PharmacyEditorSectionTitle(title: 'سعر الشراء (فلس)'),
        TextField(
          controller: _form.costFilsCtrl,
          decoration: InputDecoration(
            hintText: 'مثال: 15000',
            border: const OutlineInputBorder(),
            helperText: _form.costFilsCtrl.text.trim().isEmpty
                ? null
                : IraqiCurrencyFormat.formatIqd(
                    IqdMoney.fromFils(
                      int.tryParse(_form.costFilsCtrl.text.trim()) ?? 0,
                    ),
                  ),
          ),
          keyboardType: TextInputType.number,
          onChanged: (_) => _notifyBatchDraft(),
        ),
        const SizedBox(height: 20),
        const PharmacyEditorSectionTitle(title: 'الكمية'),
        TextField(
          controller: _form.qtyCtrl,
          decoration: const InputDecoration(
            hintText: '0',
            border: OutlineInputBorder(),
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => _notifyBatchDraft(),
        ),
      ],
    );
  }

  Widget buildRxOnlySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PharmacyEditorSectionTitle(title: 'Rx / OTC'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: PharmacyRxSchedule.otc, label: Text('OTC')),
            ButtonSegment(value: PharmacyRxSchedule.rx, label: Text('Rx')),
          ],
          selected: {_form.rxSchedule},
          onSelectionChanged: (selection) {
            _form.rxSchedule = selection.first;
            _notifyChanged();
          },
        ),
      ],
    );
  }

  Widget buildStrengthOnlySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PharmacyEditorSectionTitle(title: 'التركيز'),
        TextField(
          controller: _form.strengthCtrl,
          decoration: const InputDecoration(
            hintText: '500 mg · 1000 mg',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _notifyChanged(),
        ),
      ],
    );
  }

  Widget buildNotesSection() {
    final notes = widget.notesController;
    if (notes == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PharmacyEditorSectionTitle(title: 'ملاحظات (اختياري)'),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'نص حر…',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => _notifyChanged(),
        ),
      ],
    );
  }

  Widget? buildExpiryDaysHint() {
    final expiry = _form.expiryDate;
    if (expiry == null) return null;
    final today = DateTime.now();
    final days = DateTime(expiry.year, expiry.month, expiry.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
    if (days < 0) return null;
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 8),
      child: Text(
        days == 0 ? 'ينتهي اليوم' : 'يتبقى $days يوم',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: days <= 30
                  ? Theme.of(context).colorScheme.tertiary
                  : null,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final layout = widget.stepLayout;
    if (layout != null) {
      return _buildStepLayout(context, layout);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildDrugReferenceSection(),
        const SizedBox(height: 20),
        buildManufacturerSection(),
        const SizedBox(height: 20),
        buildDosageFormSection(),
        const SizedBox(height: 20),
        buildStrengthAndRxSection(),
        if (widget.showBatchAndQty) ...[
          const SizedBox(height: 20),
          buildBatchAndExpirySection(),
          const SizedBox(height: 20),
          buildPricingAndQtySection(),
        ],
      ],
    );
  }

  Widget _buildStepLayout(
    BuildContext context,
    PharmacyProductEditorStepLayout layout,
  ) {
    switch (layout) {
      case PharmacyProductEditorStepLayout.modeA1DrugReference:
      case PharmacyProductEditorStepLayout.modeC1DrugReference:
        return buildDrugReferenceSection();
      case PharmacyProductEditorStepLayout.modeA2Commercial:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildManufacturerSection(),
            const SizedBox(height: 20),
            buildDosageFormSection(),
            const SizedBox(height: 20),
            buildStrengthOnlySection(),
          ],
        );
      case PharmacyProductEditorStepLayout.modeA3BatchRx:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildBatchAndExpirySection(),
            if (buildExpiryDaysHint() != null) buildExpiryDaysHint()!,
            const SizedBox(height: 20),
            buildRxOnlySection(),
          ],
        );
      case PharmacyProductEditorStepLayout.modeA4PricingNotes:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildPricingAndQtySection(),
            const SizedBox(height: 20),
            buildNotesSection(),
          ],
        );
      case PharmacyProductEditorStepLayout.modeB1DrugCommercial:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildDrugReferenceSection(),
            const SizedBox(height: 20),
            buildManufacturerSection(),
            const SizedBox(height: 20),
            buildStrengthOnlySection(),
            const SizedBox(height: 20),
            buildDosageFormSection(),
            const SizedBox(height: 20),
            buildRxOnlySection(),
          ],
        );
      case PharmacyProductEditorStepLayout.modeB2BatchPricing:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildBatchAndExpirySection(),
            if (buildExpiryDaysHint() != null) buildExpiryDaysHint()!,
            const SizedBox(height: 20),
            buildPricingAndQtySection(),
          ],
        );
      case PharmacyProductEditorStepLayout.modeC2Manufacturer:
        return buildManufacturerSection();
      case PharmacyProductEditorStepLayout.modeC3FormStrength:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildDosageFormSection(),
            const SizedBox(height: 20),
            buildStrengthOnlySection(),
            const SizedBox(height: 20),
            buildRxOnlySection(),
          ],
        );
      case PharmacyProductEditorStepLayout.modeC4BatchExpiry:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildBatchAndExpirySection(),
            if (buildExpiryDaysHint() != null) buildExpiryDaysHint()!,
          ],
        );
      case PharmacyProductEditorStepLayout.modeC5PricingQty:
        return buildPricingAndQtySection();
      case PharmacyProductEditorStepLayout.modeC6Notes:
        return buildNotesSection();
    }
  }

  static String _formatList(List<String> values) {
    if (values.isEmpty) return '—';
    return values.join(' · ');
  }

  static String _formatIndications(PharmacyDrugReference reference) {
    final parts = <String>[
      ...reference.indications,
      if ((reference.indicationsFreeText ?? '').trim().isNotEmpty)
        reference.indicationsFreeText!.trim(),
    ];
    if (parts.isEmpty) return '—';
    return parts.join(' · ');
  }

  static String _manufacturerTypeLabel(String type) {
    switch (type) {
      case PharmacyManufacturerType.originator:
        return 'أصلي';
      case PharmacyManufacturerType.local:
        return 'محلي';
      case PharmacyManufacturerType.generic:
      default:
        return 'جنيس';
    }
  }
}

class PharmacyEditorSectionTitle extends StatelessWidget {
  const PharmacyEditorSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class PharmacyEditorReadOnlyBlock extends StatelessWidget {
  const PharmacyEditorReadOnlyBlock({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: lines
            .map(
              (line) => Padding(
                padding: const EdgeInsetsDirectional.only(bottom: 4),
                child: Text(
                  line,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}
