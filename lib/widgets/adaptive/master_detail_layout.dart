import 'package:flutter/material.dart';
import '../../utils/screen_layout.dart';

/// تخطيط متجاوب لنمط Master-Detail.
///
/// على الهواتف: يعرض القائمة (Master) فقط، وعند اختيار عنصر 
/// يجب على المطور استخدام Navigator لفتح صفحة الـ Detail.
/// 
/// على التابلت والكمبيوتر: يعرض القائمة والتفاصيل جنباً إلى جنب.
class MasterDetailLayout<T> extends StatelessWidget {
  const MasterDetailLayout({
    super.key,
    required this.masterBuilder,
    required this.detailBuilder,
    this.selectedItemId,
    this.masterWidth = 320.0,
  });

  /// بناء قائمة العناصر (Master)
  final Widget Function(BuildContext context, bool isSideBySide) masterBuilder;

  /// بناء تفاصيل العنصر (Detail)
  final Widget Function(BuildContext context) detailBuilder;

  /// المعرف الحالي للعنصر المختار (null إذا لم يُختر شيء)
  final T? selectedItemId;

  /// عرض قسم القائمة في وضع Side-by-Side
  final double masterWidth;

  @override
  Widget build(BuildContext context) {
    final variant = context.screenLayout.layoutVariant;
    
    // الموبايل يعرض Master فقط
    if (variant == DeviceVariant.phoneXS || variant == DeviceVariant.phoneSM) {
      return masterBuilder(context, false);
    }

    // التابلت والديسكتوب يعرض الاثنين معاً.
    // `stretch` يضمن أن الـ panels تملأ كل ارتفاع الـ Row (لتعمل الـ Scrollables داخلها).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: masterWidth,
          child: masterBuilder(context, true),
        ),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: selectedItemId == null
              ? const Center(child: Text('الرجاء اختيار عنصر لعرض تفاصيله'))
              : detailBuilder(context),
        ),
      ],
    );
  }
}
