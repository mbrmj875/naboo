import 'package:flutter/material.dart';

import '../../../theme/design_tokens.dart';

/// قانون ثابت لشاشات تطبيقات الزيوت (بطاقة / سجل / أزواج حقول / ظلال / انتقالات).
///
/// تحت هذا العرض (Poco-class ~360dp وما دونه):
/// - الحقول الزوجية عمود واحد
/// - ظل بطاقة واحد خفيف (بدون glow ذهبي مزدوج)
/// فوقه: الصف المزدوج + ظلال كاملة كما صُمّمت.
///
/// انتقالات الصفحات: استخدم [FastContentPageRoute] (Fade+Slide، 250/220ms)
/// من `lib/navigation/content_navigation.dart` — لا MaterialPageRoute مباشر.
const double kOilChangeStackFieldsMaxWidth = 400;

/// `true` عندما يجب طي أزواج الحقول / تخفيف الرسم.
bool oilChangePreferStackedFields(double width) =>
    width <= kOilChangeStackFieldsMaxWidth;

bool oilChangePreferStackedFieldsOf(BuildContext context) =>
    oilChangePreferStackedFields(MediaQuery.sizeOf(context).width);

/// ظل واحد خفيف — مسار الهاتف الضيق (≤400dp).
const List<BoxShadow> kOilChangeCardShadowsLite = [
  BoxShadow(
    color: Color(0x14000000),
    blurRadius: 6,
    offset: Offset(0, 2),
  ),
];

/// ظل مزدوج + توهج ذهبي — تابلت / حاسب / هاتف أعرض من 400dp.
const List<BoxShadow> kOilChangeCardShadowsFull = [
  BoxShadow(
    color: AppGlass.goldGlow,
    blurRadius: 14,
    offset: Offset(0, 3),
  ),
  BoxShadow(
    color: Color(0x0A000000),
    blurRadius: 10,
    offset: Offset(0, 4),
  ),
];

/// ظلال [OilChangeRoyalCard] حسب قانون ≤400dp.
List<BoxShadow> oilChangeCardShadowsOf(BuildContext context) =>
    oilChangePreferStackedFieldsOf(context)
        ? kOilChangeCardShadowsLite
        : kOilChangeCardShadowsFull;

/// توهج ذهبي منفرد (شيتات / CTA) — تحت 400dp يُستبدل بظل خفيف.
List<BoxShadow> oilChangeGoldGlowOf(
  BuildContext context, {
  double blurRadius = 14,
  Offset offset = const Offset(0, 4),
}) {
  if (oilChangePreferStackedFieldsOf(context)) {
    return kOilChangeCardShadowsLite;
  }
  return [
    BoxShadow(
      color: AppGlass.goldGlow,
      blurRadius: blurRadius,
      offset: offset,
    ),
  ];
}

/// زوج حقول: عمود تحت [kOilChangeStackFieldsMaxWidth]، صف جنباً إلى جنب فوقه.
Widget oilChangeFieldPair({
  required BuildContext context,
  required Widget start,
  required Widget end,
  int startFlex = 1,
  int endFlex = 1,
  double gap = 8,
}) {
  if (oilChangePreferStackedFieldsOf(context)) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        start,
        SizedBox(height: gap),
        end,
      ],
    );
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: startFlex, child: start),
      SizedBox(width: gap),
      Expanded(flex: endFlex, child: end),
    ],
  );
}

/// زوج حقول + زر فعل (مثل + كتالوج): تحت الحد يُصفّ الزر بجانب الحقل الثاني.
Widget oilChangeFieldPairWithAction({
  required BuildContext context,
  required Widget start,
  required Widget end,
  required Widget action,
  int startFlex = 2,
  int endFlex = 1,
  double gap = 6,
  double actionGap = 4,
}) {
  if (oilChangePreferStackedFieldsOf(context)) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        start,
        SizedBox(height: gap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: end),
            SizedBox(width: actionGap),
            action,
          ],
        ),
      ],
    );
  }
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(flex: startFlex, child: start),
      SizedBox(width: gap),
      Expanded(flex: endFlex, child: end),
      SizedBox(width: actionGap),
      action,
    ],
  );
}
