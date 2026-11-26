import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/models/sale_pos_settings_data.dart';
import 'package:naboo/theme/app_theme_resolver.dart';

// الاختبار النهائي على الهاتف: في الداكن كانت الأزرار النصية كحلية على خلفية داكنة.
void main() {
  Color fgOf(ButtonStyle? s) => s!.foregroundColor!.resolve(<WidgetState>{})!;

  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  testWidgets('الأزرار النصية والمحدّدة تُقرأ على الخلفية الداكنة', (t) async {
    final dark = AppThemeResolver.dark(SalePosSettingsData.defaults());
    const bg = Color(0xFF1E293B); // خلفية النوافذ والبطاقات في الداكن
    expect(contrast(fgOf(dark.textButtonTheme.style), bg), greaterThanOrEqualTo(4.5));
    expect(contrast(fgOf(dark.outlinedButtonTheme.style), bg), greaterThanOrEqualTo(4.5));
  });

  testWidgets('الفاتح يبقى كحلياً', (t) async {
    final light = AppThemeResolver.light(SalePosSettingsData.defaults());
    expect(fgOf(light.textButtonTheme.style), light.colorScheme.primary);
  });
}
