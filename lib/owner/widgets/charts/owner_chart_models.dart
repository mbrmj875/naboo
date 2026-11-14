import 'package:flutter/material.dart';

/// ارتفاع/عرض منطقة الرسم — موحّد بين الأعمدة والدائرة في لوحة المالك.
const double kOwnerAnalyticsChartPlotSize = 168;

/// ارتفاع مضغوط للهاتف (Stitch: ≤180px).
const double kOwnerAnalyticsChartPlotSizeCompact = 140;

/// ارتفاع محتوى المخطط (رسم + محور + ملخص) — للمحاذاة بين البطاقتين.
const double kOwnerAnalyticsChartBodyHeight =
    kOwnerAnalyticsChartPlotSize + 52 + 24;

const double kOwnerAnalyticsChartBodyHeightCompact =
    kOwnerAnalyticsChartPlotSizeCompact + 52 + 24;

/// ارتفاع كامل لمحتوى مخطط الأعمدة (رسم + محور + ملخص).
double ownerAnalyticsBarChartBodyHeight(double plotSize) => plotSize + 52 + 24;

/// شريحة واحدة لرسم دائري أو وسيلة إيضاح.
class OwnerChartSlice {
  const OwnerChartSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;
}
