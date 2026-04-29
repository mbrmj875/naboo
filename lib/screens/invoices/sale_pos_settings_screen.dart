import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/sale_pos_settings_data.dart';
import '../../providers/sale_pos_settings_provider.dart';
import '../../theme/design_tokens.dart';
import '../../theme/sale_brand.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/app_color_picker_dialog.dart';

/// إعدادات نقطة البيع — سياسات البيع، الخصم والضريبة، وتقسيم العرض العريض.
///
/// [appearanceOnly]: يُفتح من «الإعدادات الرئيسية» لضبط **المظهر** (ألوان، زوايا، خط، نص).
/// شاشة نقطة البيع الكاملة لا تعيد هذه الحقول — تُضبط من الإعدادات الرئيسية فقط.
class SalePosSettingsScreen extends StatelessWidget {
  const SalePosSettingsScreen({super.key, this.appearanceOnly = false});

  /// وضع «مظهر التطبيق» من الإعدادات العامة — يخفي أقسام سياسة البيع.
  final bool appearanceOnly;

  static String _paletteTitle(String id) {
    switch (id) {
      case SalePaletteIds.royal:
        return 'كحلي ملكي — ذهبي — عاجي (الافتراضي)';
      case SalePaletteIds.midnight:
        return 'منتصف ليل — فضي — رمادي فاتح';
      case SalePaletteIds.ocean:
        return 'محيط — رملي ذهبي — كريمي';
      case SalePaletteIds.forest:
        return 'غابة — برونزي — نعناعي فاتح';
      case SalePaletteIds.wine:
        return 'نبيذي — ذهبي دافئ — أبيض وردي';
      case SalePaletteIds.charcoal:
        return 'فحمي — عنبر — أبيض مزرق';
      case SalePaletteIds.slate:
        return 'أردوازي — سماوي — أبيض بارد';
      case SalePaletteIds.copper:
        return 'نحاسي — نحاس محمر — رمل';
      case SalePaletteIds.custom:
        return 'مخصص — استوديو ألوان تفاعلي';
      default:
        return id;
    }
  }

  /// معاينة الخط في القائمة المنسدلة — يطابق عائلات [AppFontFamilies] + Google Fonts.
  static TextStyle _fontChoicePreviewStyle(String family) {
    const size = 13.0;
    switch (AppFontFamilies.normalize(family)) {
      case AppFontFamilies.cairo:
        return GoogleFonts.cairo(fontSize: size);
      case AppFontFamilies.almarai:
        return GoogleFonts.almarai(fontSize: size);
      case AppFontFamilies.amiri:
        return GoogleFonts.amiri(fontSize: size);
      case AppFontFamilies.lateef:
        return GoogleFonts.lateef(fontSize: size);
      case AppFontFamilies.scheherazadeNew:
        return GoogleFonts.scheherazadeNew(fontSize: size);
      case AppFontFamilies.ibmPlexSansArabic:
        return GoogleFonts.ibmPlexSansArabic(fontSize: size);
      case AppFontFamilies.elMessiri:
        return GoogleFonts.elMessiri(fontSize: size);
      case AppFontFamilies.changa:
        return GoogleFonts.changa(fontSize: size);
      case AppFontFamilies.notoNaskhArabic:
        return TextStyle(
          fontFamily: AppFontFamilies.notoNaskhArabic,
          fontSize: size,
        );
      case AppFontFamilies.tajawal:
      default:
        return TextStyle(fontFamily: AppFontFamilies.tajawal, fontSize: size);
    }
  }

  static Color _previewColorFor(String paletteId, int slot) {
    final p = SalePalette.fromSettings(
      SalePosSettingsData(
        enableTaxOnSale: true,
        enableInvoiceDiscount: true,
        allowCredit: true,
        allowInstallment: true,
        allowDelivery: true,
        enforceAvailableQtyAtSale: false,
        useSaleBrandSkin: true,
        showBuyerAddressOnCash: true,
        panelCornerStyle: SalePanelCornerStyle.sharp,
        salePaletteId: paletteId,
        enableWideSalePartition: true,
        wideSaleProductsFlex: SaleWideLayoutFlexBounds.defaultProducts,
        appTextScale: 1.0,
        appFontFamily: AppFontFamilies.tajawal,
        appTextColorLightArgb: null,
        appTextColorDarkArgb: null,
      ),
      ThemeData.light(),
    );
    switch (slot) {
      case 0:
        return p.navy;
      case 1:
        return p.gold;
      case 2:
        return p.ivory;
      default:
        return p.ivoryDark;
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SalePosSettingsProvider>();
    final d = prov.data;
    final scheme = Theme.of(context).colorScheme;
    final gap = ScreenLayout.of(context).pageHorizontalGap;
    final showWideSaleLayoutControls =
        !ScreenLayout.of(context).isHandsetForLayout;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            appearanceOnly ? 'مظهر التطبيق' : 'إعدادات نقطة البيع',
          ),
          backgroundColor: scheme.primary,
        ),
        body: ListView(
          padding: EdgeInsetsDirectional.fromSTEB(gap, 16, gap, 32),
          children: [
            if (appearanceOnly) ...[
              _GlobalBrandIntroCard(scheme: scheme),
              const SizedBox(height: 20),
            ],
            if (!appearanceOnly) ...[
            _IntroCard(scheme: scheme),
            const SizedBox(height: 20),
            _SectionLabel('طرق الدفع', Icons.payments_outlined, scheme),
            const SizedBox(height: 8),
            _PolicyCard(
              scheme: scheme,
              children: [
                _PolicySwitch(
                  title: 'البيع بالدين (آجل)',
                  subtitle: 'إيقافه يخفي خيار «دين» في شاشة البيع.',
                  value: d.allowCredit,
                  onChanged: (v) {
                    if (v == null) return;
                    prov.save(d.copyWith(allowCredit: v));
                  },
                ),
                const Divider(height: 1),
                _PolicySwitch(
                  title: 'البيع بالتقسيط',
                  subtitle: 'إيقافه يخفي خيار «تقسيط».',
                  value: d.allowInstallment,
                  onChanged: (v) {
                    if (v == null) return;
                    prov.save(d.copyWith(allowInstallment: v));
                  },
                ),
                const Divider(height: 1),
                _PolicySwitch(
                  title: 'البيع مع التوصيل',
                  subtitle: 'إيقافه يخفي خيار «توصيل».',
                  value: d.allowDelivery,
                  onChanged: (v) {
                    if (v == null) return;
                    prov.save(d.copyWith(allowDelivery: v));
                  },
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionLabel('العميل في البيع النقدي', Icons.person_pin_circle_outlined, scheme),
            const SizedBox(height: 8),
            _PolicyCard(
              scheme: scheme,
              children: [
                _PolicySwitch(
                  title: 'إظهار حقل عنوان المشتري عند النقدي',
                  subtitle:
                      'يظهر فقط إذا فعّلت «QR لعنوان المشتري» في إعدادات الطباعة. عند الإيقاف يبقى الحقل للتوصيل كما هو.',
                  value: d.showBuyerAddressOnCash,
                  onChanged: (v) {
                    if (v == null) return;
                    prov.save(d.copyWith(showBuyerAddressOnCash: v));
                  },
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionLabel('المخزون في البيع', Icons.inventory_2_outlined, scheme),
            const SizedBox(height: 8),
            _PolicyCard(
              scheme: scheme,
              children: [
                _PolicySwitch(
                  title: 'منع البيع عند تجاوز الرصيد المعروض',
                  subtitle:
                      'عند التفعيل لا تزيد الكمية في الفاتورة فوق المتاح. عند الإيقاف يُسمح بالبيع حتى لو أصبح الرصيد سالباً، فيُلغى السالب عند تسجيل وارد لاحقاً (حقل كمية المنتج في قاعدة البيانات).',
                  value: d.enforceAvailableQtyAtSale,
                  onChanged: (v) {
                    if (v == null) return;
                    prov.save(d.copyWith(enforceAvailableQtyAtSale: v));
                  },
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionLabel('الخصم والضريبة', Icons.percent_outlined, scheme),
            const SizedBox(height: 8),
            _PolicyCard(
              scheme: scheme,
              children: [
                _PolicySwitch(
                  title: 'حقل خصم الفاتورة (نسبة)',
                  subtitle: 'عند الإيقاف يُثبَّت الخصم على 0 ويُخفى الحقل.',
                  value: d.enableInvoiceDiscount,
                  onChanged: (v) {
                    if (v == null) return;
                    prov.save(d.copyWith(enableInvoiceDiscount: v));
                  },
                ),
                const Divider(height: 1),
                _PolicySwitch(
                  title: 'حقل الضريبة',
                  subtitle: 'عند الإيقاف يُثبَّت الضريبة على 0 ويُخفى الحقل.',
                  value: d.enableTaxOnSale,
                  onChanged: (v) {
                    if (v == null) return;
                    prov.save(d.copyWith(enableTaxOnSale: v));
                  },
                ),
              ],
            ),
            ],
            if (appearanceOnly) ...[
            const SizedBox(height: 22),
            _SectionLabel(
              'مظهر التطبيق',
              Icons.palette_outlined,
              scheme,
            ),
            const SizedBox(height: 8),
            _PolicyCard(
              scheme: scheme,
              children: [
                _PolicySwitch(
                  title: 'ألوان هوية الشعار بدل ثيم التطبيق',
                  subtitle:
                      'عند الإيقاف يبقى ثيم التطبيق العام (فاتح/داكن) في كل الصفحات، مع نفس شكل الزوايا أدناه.',
                  value: d.useSaleBrandSkin,
                  onChanged: (v) {
                    if (v == null) return;
                    prov.save(d.copyWith(useSaleBrandSkin: v));
                  },
                ),
                if (d.useSaleBrandSkin) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'مخطط الألوان',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'كل مخطط ألوان احترافي جاهز؛ «مخصص» يفتح استوديو ألوان تفاعلياً (طيف، تشبع، سطوع، جاهز، HEX) لكل لون.',
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 10),
                        InputDecorator(
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: AppShape.none),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: d.salePaletteId == SalePaletteIds.custom
                                  ? SalePaletteIds.custom
                                  : SalePaletteIds.builtIn.contains(d.salePaletteId)
                                      ? d.salePaletteId
                                      : SalePaletteIds.royal,
                              items: [
                                ...SalePaletteIds.builtIn.map(
                                  (id) => DropdownMenuItem(
                                    value: id,
                                    child: Text(_paletteTitle(id)),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: SalePaletteIds.custom,
                                  child: Text(
                                    _paletteTitle(SalePaletteIds.custom),
                                  ),
                                ),
                              ],
                              onChanged: (id) {
                                if (id == null) return;
                                if (id == SalePaletteIds.custom) {
                                  prov.save(d.copyWith(salePaletteId: id));
                                } else {
                                  prov.save(
                                    d.clearCustomPaletteFields().copyWith(
                                      salePaletteId: id,
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final id in SalePaletteIds.builtIn)
                              _MiniPaletteSwatch(
                                label: _paletteTitle(id).split(' —').first,
                                paletteId: id,
                                selected: d.salePaletteId == id,
                                onTap: () => prov.save(
                                  d.clearCustomPaletteFields().copyWith(
                                    salePaletteId: id,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (d.salePaletteId == SalePaletteIds.custom) ...[
                          const SizedBox(height: 14),
                          _CustomColorRow(
                            label: 'اللون الرئيسي (شريط العنوان والأزرار)',
                            color: Color(
                              d.customPrimaryArgb ?? 0xFF152B47,
                            ),
                            onColor: (c) => prov.save(
                              d.copyWith(customPrimaryArgb: c.toARGB32()),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _CustomColorRow(
                            label: 'لون التمييز (ذهبي/مميز)',
                            color: Color(d.customAccentArgb ?? 0xFFC9A85C),
                            onColor: (c) => prov.save(
                              d.copyWith(customAccentArgb: c.toARGB32()),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _CustomColorRow(
                            label: 'خلفية اللوحات الفاتحة',
                            color: Color(d.customSurfaceArgb ?? 0xFFF7F4EF),
                            onColor: (c) => prov.save(
                              d.copyWith(customSurfaceArgb: c.toARGB32()),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _CustomColorRow(
                            label: 'خلفية الوضع الداكن للوحات',
                            color: Color(d.customSurfaceDarkArgb ?? 0xFF1A2433),
                            onColor: (c) => prov.save(
                              d.copyWith(customSurfaceDarkArgb: c.toARGB32()),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'شكل بطاقات البيع',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'معاينة بسيطة بجانب كل خيار — كيف تبدو زوايا اللوحات وأسطر المنتجات.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _CornerChoiceTile(
                              title: 'زوايا حادة',
                              selected:
                                  d.panelCornerStyle == SalePanelCornerStyle.sharp,
                              scheme: scheme,
                              previewSharp: true,
                              onTap: () => prov.save(
                                d.copyWith(
                                  panelCornerStyle: SalePanelCornerStyle.sharp,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _CornerChoiceTile(
                              title: 'زوايا مستديرة',
                              selected: d.panelCornerStyle ==
                                  SalePanelCornerStyle.rounded,
                              scheme: scheme,
                              previewSharp: false,
                              onTap: () => prov.save(
                                d.copyWith(
                                  panelCornerStyle:
                                      SalePanelCornerStyle.rounded,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'خط التطبيق وحجمه',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'يُطبَّق على كل الشاشات والقوائم، ويُضرب مع حجم خط النظام (إن وُجد).',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'شكل الخط',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InputDecorator(
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: AppShape.none,
                          ),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: AppFontFamilies.normalize(d.appFontFamily),
                            items: [
                              for (final ff in AppFontFamilies.selectable)
                                DropdownMenuItem(
                                  value: ff,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      '${AppFontFamilies.labelAr(ff)} — ${AppFontFamilies.subtitleAr(ff)}',
                                      textAlign: TextAlign.right,
                                      style: SalePosSettingsScreen
                                          ._fontChoicePreviewStyle(ff),
                                    ),
                                  ),
                                ),
                            ],
                            onChanged: (ff) {
                              if (ff == null) return;
                              prov.save(d.copyWith(appFontFamily: ff));
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Text(
                            'حجم الخط',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(d.appTextScale * 100).round()}٪',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        min: AppTypographyScaleBounds.min,
                        max: AppTypographyScaleBounds.max,
                        divisions: 10,
                        label: '${(d.appTextScale * 100).round()}٪',
                        value: d.appTextScale,
                        onChanged: (v) =>
                            prov.save(d.copyWith(appTextScale: v)),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'لون النص',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'اختياري — استوديو ألوان كامل لكل وضع (فاتح/داكن)؛ يُطبَّق على النصوص الرئيسية والقوائم.',
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _AppTextColorRow(
                        label: 'لون النص — الوضع الفاتح',
                        hint:
                            'عند تشغيل الثيم الفاتح. اضغط للتعديل، أو «افتراضي» لإلغاء اللون المخصص.',
                        argb: d.appTextColorLightArgb,
                        defaultColor: ColorScheme.fromSeed(
                          seedColor: scheme.primary,
                          brightness: Brightness.light,
                        ).onSurface,
                        scheme: scheme,
                        onPick: (c) => prov.save(
                          d.copyWith(appTextColorLightArgb: c.toARGB32()),
                        ),
                        onClear: () =>
                            prov.save(d.clearAppTextColorLight()),
                      ),
                      const SizedBox(height: 8),
                      _AppTextColorRow(
                        label: 'لون النص — الوضع الداكن',
                        hint:
                            'عند تشغيل الثيم الداكن. اضغط للتعديل، أو «افتراضي» لإلغاء اللون المخصص.',
                        argb: d.appTextColorDarkArgb,
                        defaultColor: ColorScheme.fromSeed(
                          seedColor: scheme.primary,
                          brightness: Brightness.dark,
                        ).onSurface,
                        scheme: scheme,
                        onPick: (c) => prov.save(
                          d.copyWith(appTextColorDarkArgb: c.toARGB32()),
                        ),
                        onClear: () => prov.save(d.clearAppTextColorDark()),
                      ),
                      if (d.appTextColorLightArgb != null ||
                          d.appTextColorDarkArgb != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: TextButton.icon(
                            onPressed: () =>
                                prov.save(d.clearAppTextColors()),
                            icon: const Icon(Icons.restart_alt_rounded, size: 18),
                            label: const Text(
                              'إعادة ضبط لون النص للوضعين (الثيم الافتراضي)',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (d.useSaleBrandSkin) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          color: SaleBrandColors.navy,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 28,
                          height: 28,
                          color: SaleBrandColors.gold,
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: SaleBrandColors.ivory,
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'مرجع ألوان «الكحلي الملكي» الافتراضية — المخططات الأخرى أعلاه.',
                            style: TextStyle(
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            ],
            if (!appearanceOnly && showWideSaleLayoutControls) ...[
              const SizedBox(height: 22),
              _SectionLabel(
                'تقسيم مساحة البيع (عرض عريض)',
                Icons.view_column_outlined,
                scheme,
              ),
              const SizedBox(height: 8),
              _PolicyCard(
                scheme: scheme,
                children: [
                  _PolicySwitch(
                    title: 'تقسيم شاشة البيع إلى عمودين (عرض عريض)',
                    subtitle:
                        'عند الإيقاف تعود «بيع جديد» إلى عمود واحد كالمعتاد حتى على الشاشة الواسعة. النسبة تُحفظ ولا تُفقد عند التعطيل.',
                    value: d.enableWideSalePartition,
                    onChanged: (v) {
                      if (v == null) return;
                      prov.save(d.copyWith(enableWideSalePartition: v));
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'عندما يكون عرض النافذة ٧٠٠ نقطة فأكثر وليست شاشة هاتف، ومع تشغيل الخيار أعلاه، تُقسَّم شاشة «بيع جديد» إلى عمودين: المنتجات، ثم الملخص والعميل. يمكنك سحب الشريط الرفيع الذهبي بين العمودين، أو ضبط النسبة من هنا (لا يغيّر الحسابات).',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 14),
                        AbsorbPointer(
                          absorbing: !d.enableWideSalePartition,
                          child: Opacity(
                            opacity: d.enableWideSalePartition ? 1 : 0.48,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'عمود المنتجات: ${d.wideSaleProductsFlex} — الملخص والعميل: ${d.wideSaleSideFlex}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: scheme.onSurface,
                                        ),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        prov.save(
                                          d.copyWith(
                                            wideSaleProductsFlex:
                                                SaleWideLayoutFlexBounds
                                                    .defaultProducts,
                                          ),
                                        );
                                      },
                                      child: const Text('افتراضي'),
                                    ),
                                  ],
                                ),
                                Slider(
                                  value: d.wideSaleProductsFlex.toDouble(),
                                  min: SaleWideLayoutFlexBounds.min.toDouble(),
                                  max: SaleWideLayoutFlexBounds.max.toDouble(),
                                  divisions: SaleWideLayoutFlexBounds.max -
                                      SaleWideLayoutFlexBounds.min,
                                  label:
                                      'منتجات ${d.wideSaleProductsFlex} · باقي الشاشة ${d.wideSaleSideFlex}',
                                  onChanged: (v) {
                                    prov.save(
                                      d.copyWith(
                                        wideSaleProductsFlex: v.round(),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'معاينة مباشرة (مساحة صغيرة — كيف يتغيّر التقسيم عند تحريك المنزلق أو السحب في البيع):',
                                  style: TextStyle(
                                    fontSize: 11,
                                    height: 1.35,
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _WideSaleLayoutPreviewMini(
                                  productsFlex: d.wideSaleProductsFlex,
                                  sideFlex: d.wideSaleSideFlex,
                                  scheme: scheme,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'في شاشة «بيع جديد» على عرض عريض: مرّر المؤشر على الشريط الرفيع بين العمودين ثم اسحب أفقياً — يوسّع عمود «المنتجات» أو يضيّقه بنفس فكرة المعاينة أعلاه.',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    height: 1.4,
                                    color: scheme.onSurfaceVariant
                                        .withValues(alpha: 0.9),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ] else if (!appearanceOnly) ...[
              const SizedBox(height: 22),
              _SectionLabel(
                'تقسيم مساحة البيع',
                Icons.smartphone_outlined,
                scheme,
              ),
              const SizedBox(height: 8),
              _PolicyCard(
                scheme: scheme,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Text(
                      'على هذا الحجم (هاتف) تُعرض شاشة «بيع جديد» دائماً في عمود واحد. تقسيم المنتجات والملخص إلى عمودين مع سحب المساحة يظهر من التابلت أو الشاشة الأوسع فقط.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Text(
              appearanceOnly
                  ? 'تُطبَّق الألوان والزوايا فوراً على كامل التطبيق (عبر ثيم النظام). سياسات البيع تبقى من «إعدادات نقطة البيع» في القائمة الجانبية.'
                  : 'تُطبَّق سياسات البيع والتقسيم فوراً على شاشة «بيع جديد». المظهر (الألوان، الخط، الزوايا، لون النص) يُضبط من الإعدادات الرئيسية > مظهر التطبيق.',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (appearanceOnly) ...[
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('استرجاع المظهر الافتراضي؟'),
                        content: const Text(
                          'سيتم إرجاع نوع الخط، حجم النص، ألوان النص المخصصة، مخطط الألوان، الزوايا، وهوية الشعار إلى القيم الأساسية. لا يتغير البيع بالدين أو الضريبة أو المخزون.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('إلغاء'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('استرجاع'),
                          ),
                        ],
                      ),
                    );
                    if (ok != true || !context.mounted) return;
                    await prov.save(d.withAppearanceResetToDefaults());
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('تم استرجاع إعدادات المظهر الافتراضية'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text(
                    'استرجاع المظهر الافتراضي (خط، ألوان، مخطط، زوايا)',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// معاينة مصغّرة لعمودي «بيع جديد» — نفس أوزان [Expanded] الحقيقية (اتجاه RTL كالشاشة).
class _WideSaleLayoutPreviewMini extends StatelessWidget {
  const _WideSaleLayoutPreviewMini({
    required this.productsFlex,
    required this.sideFlex,
    required this.scheme,
  });

  final int productsFlex;
  final int sideFlex;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        height: 54,
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: productsFlex,
              child: ColoredBox(
                color: scheme.primary.withValues(alpha: 0.14),
                child: Center(
                  child: Text(
                    'منتجات',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: 4,
              color: scheme.tertiary.withValues(alpha: 0.7),
            ),
            Expanded(
              flex: sideFlex,
              child: ColoredBox(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.65),
                child: Center(
                  child: Text(
                    'ملخص\nوعميل',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9.5,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
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

class _MiniPaletteSwatch extends StatelessWidget {
  const _MiniPaletteSwatch({
    required this.label,
    required this.paletteId,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String paletteId;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dot(SalePosSettingsScreen._previewColorFor(paletteId, 0)),
              const SizedBox(width: 4),
              _dot(SalePosSettingsScreen._previewColorFor(paletteId, 1)),
              const SizedBox(width: 4),
              _dot(SalePosSettingsScreen._previewColorFor(paletteId, 2)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _dot(Color c) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black12),
      ),
    );
  }
}

class _CornerChoiceTile extends StatelessWidget {
  const _CornerChoiceTile({
    required this.title,
    required this.selected,
    required this.scheme,
    required this.previewSharp,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final ColorScheme scheme;
  final bool previewSharp;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final br = previewSharp ? BorderRadius.zero : BorderRadius.circular(10);
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded,
                        size: 20, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 72,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: br,
                    border: Border.all(color: scheme.outline),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 48,
                    height: 22,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.85),
                      borderRadius: previewSharp ? BorderRadius.zero : BorderRadius.circular(6),
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

class _AppTextColorRow extends StatelessWidget {
  const _AppTextColorRow({
    required this.label,
    required this.hint,
    required this.argb,
    required this.defaultColor,
    required this.scheme,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String hint;
  final int? argb;
  final Color defaultColor;
  final ColorScheme scheme;
  final ValueChanged<Color> onPick;
  final VoidCallback onClear;

  Future<void> _open(BuildContext context) async {
    final initial = argb != null ? Color(argb!) : defaultColor;
    final next = await showAppColorPickerDialog(
      context: context,
      initialColor: initial,
      title: label,
      subtitle: hint,
    );
    if (next != null) onPick(next);
  }

  @override
  Widget build(BuildContext context) {
    final effective = argb != null ? Color(argb!) : defaultColor;
    final hex = argb != null
        ? '#${(argb! & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}'
        : null;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: effective,
            border: Border.all(color: scheme.outlineVariant),
          ),
        ),
        title: Text(label, style: const TextStyle(fontSize: 12.5)),
        subtitle: Text(
          hex != null ? '$hex — مخصص' : 'افتراضي الثيم',
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (argb != null)
              TextButton(
                onPressed: onClear,
                child: const Text('افتراضي'),
              ),
            const Icon(Icons.palette_outlined, size: 22),
          ],
        ),
        onTap: () => _open(context),
      ),
    );
  }
}

class _CustomColorRow extends StatelessWidget {
  const _CustomColorRow({
    required this.label,
    required this.color,
    required this.onColor,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onColor;

  Future<void> _edit(BuildContext context) async {
    final next = await showAppColorPickerDialog(
      context: context,
      initialColor: color,
      title: label,
      subtitle:
          'مربع التشبع/السطوع، شريط الطيف، ألوان جاهزة، أو HEX — ثم تأكيد.',
    );
    if (next != null) onColor(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
      shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: scheme.outlineVariant),
          ),
        ),
        title: Text(label, style: const TextStyle(fontSize: 12.5)),
        trailing: const Icon(Icons.palette_outlined, size: 22),
        onTap: () => _edit(context),
      ),
    );
  }
}

/// يظهر في وضع [SalePosSettingsScreen.appearanceOnly] فقط.
class _GlobalBrandIntroCard extends StatelessWidget {
  const _GlobalBrandIntroCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'هوية التطبيق',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'هنا تضبط ألوان الهوية وشكل الزوايا ليُطبَّق على كامل التطبيق. '
            'سياسات الدفع والمخزون والخصم تبقى في «إعدادات نقطة البيع» من القائمة الجانبية.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.25),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تحكّم مركزي بالبيع',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 15,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'فعّل أو عطّل طرق الدفع والحقول المالية دون تعديل الكود — مناسب للسياسات المتغيرة أو أجهزة نقطة بيع مخصصة. المظهر يُضبط من الإعدادات الرئيسية.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.title, this.icon, this.scheme);

  final String title;
  final IconData icon;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.scheme, required this.children});

  final ColorScheme scheme;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: scheme.surface,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppShape.none),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class _PolicySwitch extends StatelessWidget {
  const _PolicySwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.35,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    );
  }
}
