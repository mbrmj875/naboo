import 'package:flutter/material.dart';

/// ألوان هوية الشعار — كحلي ملكي، ذهبي، عاجي (شاشة البيع عند تفعيل «هوية الشعار»).
abstract final class SaleBrandColors {
  SaleBrandColors._();

  static const Color navy = Color(0xFF152B47);
  static const Color gold = Color(0xFFC9A85C);
  static const Color ivory = Color(0xFFF7F4EF);
  static const Color ivoryDark = Color(0xFF1A2433);
}

/// تباين نصوص وأيقونات أزرار وشرائح شاشة البيع — كحلي مع أبيض/ذهبي، فاتح مع كحلي/ذهبي.
///
/// يمرَّر إليه `navy` و`gold` من لوحة ألوان البيع ([SalePalette] أو ثابتات [SaleBrandColors]).
abstract final class SaleAccessibleButtonColors {
  SaleAccessibleButtonColors._();

  static Color filledOnNavyLabel() => Colors.white;

  static Color filledOnNavyIcon(Color gold) => gold;

  static Color outlinedOnAppSurfaceText(Color navy, Brightness b) =>
      b == Brightness.dark ? const Color(0xFFF1F5F9) : navy;

  static Color outlinedOnSalePanelText(Color navy, Brightness b) =>
      b == Brightness.dark ? const Color(0xFFE8E4DC) : navy;

  static Color outlinedAccentIcon(Color gold) => gold;

  static Color choiceChipUnselectedLabel(Color navy, Color gold, Brightness b) =>
      b == Brightness.dark ? gold : navy;

  static Color choiceChipSelectedLabel() => Colors.white;
}
