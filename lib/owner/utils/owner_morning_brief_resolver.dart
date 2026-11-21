import '../models/owner_command_center_snapshot.dart';
import '../../verticals/oil_change/owner/oil_change_morning_brief_builder.dart';
import 'clothing_morning_brief_builder.dart';
import 'supermarket_morning_brief_builder.dart';

/// يبني سطر «ملخص الصباح» حسب تخصص لوحة المالك.
abstract final class OwnerMorningBriefResolver {
  OwnerMorningBriefResolver._();

  static String? resolve({
    required String? builderId,
    required OwnerCommandCenterSnapshot snapshot,
  }) {
    final id = (builderId ?? '').trim();
    if (id.isEmpty) return null;
    return switch (id) {
      'oil_change_morning_brief' =>
        OilChangeMorningBriefBuilder.build(snapshot),
      'supermarket_morning_brief' =>
        SupermarketMorningBriefBuilder.build(snapshot),
      'clothing_morning_brief' =>
        ClothingMorningBriefBuilder.build(snapshot),
      _ => null,
    };
  }
}
