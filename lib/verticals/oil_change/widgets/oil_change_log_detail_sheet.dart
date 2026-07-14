import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';
import '../../../theme/sale_brand.dart';
import '../utils/oil_change_finance.dart';
import '../utils/oil_change_filter_format.dart';
import '../utils/oil_change_log_format.dart';
import '../../../utils/screen_layout.dart';

/// عرض تفاصيل صف من سجل غيارات الزيت — قراءة فقط.
class OilChangeLogDetailSheet extends StatefulWidget {
  const OilChangeLogDetailSheet({
    super.key,
    required this.row,
    this.onNewCardFromRow,
  });

  final Map<String, dynamic> row;
  final VoidCallback? onNewCardFromRow;

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> row,
    VoidCallback? onNewCardFromRow,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OilChangeLogDetailSheet(
        row: row,
        onNewCardFromRow: onNewCardFromRow,
      ),
    );
  }

  @override
  State<OilChangeLogDetailSheet> createState() => _OilChangeLogDetailSheetState();
}

class _OilChangeLogDetailSheetState extends State<OilChangeLogDetailSheet> {
  static const _royalGold = SaleBrandColors.gold;

  String? _oilProductName;
  bool _loadingExtra = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadExtra());
  }

  Future<void> _loadExtra() async {
    try {
      final name = await oilProductDisplayName(widget.row);
      if (!mounted) return;
      setState(() {
        _oilProductName = name;
        _loadingExtra = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingExtra = false);
    }
  }

  Widget _detailRow(ColorScheme cs, String label, String value,
      {TextDirection? valueDirection}) {
    final display = value.trim().isEmpty ? '—' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
              textAlign: TextAlign.start,
            ),
          ),
          Expanded(
            child: Text(
              display,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                height: 1.35,
              ),
              textAlign: TextAlign.start,
              textDirection: valueDirection,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _filterDetailRows(ColorScheme cs, Map<String, dynamic> r) {
    final lines = oilFilterLinesFromRow(r);
    if (lines.isEmpty) {
      final legacy = oilFormatFilterType(r);
      if (legacy == '—') return const [];
      return [_detailRow(cs, 'الفلاتر', legacy)];
    }
    return lines.map((line) => _detailRow(cs, 'فلتر', line)).toList();
  }

  Widget _section(
    ColorScheme cs, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _royalGold.withValues(alpha: 0.38),
          width: 1.25,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 14, 10),
            decoration: BoxDecoration(
              color: _royalGold.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(
                  color: _royalGold.withValues(alpha: 0.28),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: _royalGold),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = widget.row;
    final layout = context.screenLayout;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    final maxW = layout.isHandsetForLayout ? double.infinity : 520.0;
    final bottom = MediaQuery.paddingOf(context).bottom;

    final customer = (r['customerNameSnapshot'] ?? '').toString().trim();
    final services = parseOilRequestedServices(r['requestedServices']?.toString());
    final flags = OilExcelStyleFlags.fromRow(r);
    final customerOil = oilIsCustomerProvided(r);
    final invId = (r['invoiceId'] as num?)?.toInt() ?? 0;
    final stockVid = (r['stockVoucherId'] as num?)?.toInt() ?? 0;
    final liters = (r['oilLitersUsed'] as num?)?.toDouble() ?? 0;

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12 + bottom),
      child: Align(
        alignment: AlignmentDirectional.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
          child: Material(
            color: cs.surface,
            elevation: 16,
            shadowColor: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _royalGold.withValues(alpha: 0.85),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: AppGlass.goldGlow,
                    blurRadius: 20,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 0),
                    child: Row(
                      children: [
                        Icon(Icons.visibility_rounded, color: _royalGold, size: 24),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                customer.isEmpty ? 'تفاصيل البطاقة' : customer,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                ),
                                textAlign: TextAlign.start,
                              ),
                              Text(
                                oilFormatDate((r['createdAt'] ?? '').toString()),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.start,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'إغلاق',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsetsDirectional.fromSTEB(14, 0, 14, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _section(
                            cs,
                            title: 'العميل',
                            icon: Icons.person_outline_rounded,
                            children: [
                              _detailRow(cs, 'الاسم', customer),
                              _detailRow(
                                cs,
                                'الهاتف',
                                oilFormatPhone(r),
                                valueDirection: TextDirection.ltr,
                              ),
                            ],
                          ),
                          _section(
                            cs,
                            title: 'المركبة',
                            icon: Icons.directions_car_filled_rounded,
                            children: [
                              _detailRow(cs, 'اسم السيارة', (r['deviceName'] ?? '').toString()),
                              _detailRow(cs, 'الموديل', (r['carModel'] ?? '').toString()),
                              _detailRow(
                                cs,
                                'رقم اللوحة',
                                oilFormatPlate(r),
                                valueDirection: TextDirection.ltr,
                              ),
                              _detailRow(cs, 'حجم المحرك', (r['engineSize'] ?? '').toString()),
                            ],
                          ),
                          _section(
                            cs,
                            title: 'الزيت والفلتر',
                            icon: Icons.opacity_rounded,
                            children: [
                              _detailRow(
                                cs,
                                'قراءة حالية',
                                '${oilFormatOdo((r['odometerCurrent'] ?? '').toString())} كم',
                                valueDirection: TextDirection.ltr,
                              ),
                              _detailRow(
                                cs,
                                'قراءة لاحقة',
                                '${oilFormatOdo((r['odometerNext'] ?? '').toString())} كم',
                                valueDirection: TextDirection.ltr,
                              ),
                              _detailRow(cs, 'مصدر الزيت', oilFormatOilSource(r)),
                              _detailRow(cs, 'نوع الزيت', (r['oilType'] ?? '').toString()),
                              _detailRow(cs, 'اللزوجة', (r['oilViscosity'] ?? '').toString()),
                              _detailRow(cs, 'اللترات / الحجم', oilFormatLitersOrSize(r)),
                              ..._filterDetailRows(cs, r),
                              if (!customerOil && _loadingExtra)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: LinearProgressIndicator(minHeight: 2),
                                )
                              else if (!customerOil &&
                                  (_oilProductName ?? '').trim().isNotEmpty)
                                _detailRow(
                                  cs,
                                  'صنف المخزون',
                                  _oilProductName!,
                                ),
                              if (!customerOil && liters > 0)
                                _detailRow(
                                  cs,
                                  'لترات مُصرفة',
                                  '${liters.toStringAsFixed(1)} لتر',
                                  valueDirection: TextDirection.ltr,
                                ),
                              _detailRow(cs, 'زيت كير', oilYesNo(flags.gearOil)),
                            ],
                          ),
                          if (services.isNotEmpty)
                            _section(
                              cs,
                              title: 'الخدمات الإضافية',
                              icon: Icons.checklist_rounded,
                              children: [
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: services
                                      .map(
                                        (s) => Chip(
                                          label: Text(
                                            s,
                                            style: const TextStyle(fontSize: 12),
                                          ),
                                          side: BorderSide(
                                            color: _royalGold.withValues(alpha: 0.45),
                                          ),
                                          backgroundColor:
                                              _royalGold.withValues(alpha: 0.08),
                                        ),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          _section(
                            cs,
                            title: 'السعر والمتابعة',
                            icon: Icons.payments_outlined,
                            children: [
                              _detailRow(
                                cs,
                                'السعر',
                                oilFormatPrice(r),
                                valueDirection: TextDirection.ltr,
                              ),
                              _detailRow(cs, 'الفني', oilFormatTechnician(r)),
                              _detailRow(
                                cs,
                                'فاتورة البيع',
                                invId > 0 ? '#$invId' : '—',
                                valueDirection: TextDirection.ltr,
                              ),
                              if (!customerOil)
                                _detailRow(
                                  cs,
                                  'سند الصرف',
                                  stockVid > 0 ? '#$stockVid' : '—',
                                  valueDirection: TextDirection.ltr,
                                ),
                              _detailRow(
                                cs,
                                'ملاحظات',
                                (r['issueDescription'] ?? '').toString(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsetsDirectional.fromSTEB(14, 4, 14, 14 + bottom),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.onNewCardFromRow != null)
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              widget.onNewCardFromRow!();
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('بطاقة جديدة بنفس البيانات'),
                          ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('إغلاق'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
