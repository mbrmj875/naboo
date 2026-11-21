/// معرض 28 تصميماً جاهزاً — بطاقة واحدة لكل إلهام Figma (هيكل مميز، بلا إعادة تلوين وهمية).
library;

import 'presets/presets.dart';

class MenuGalleryEntry {
  const MenuGalleryEntry({
    required this.id,
    required this.labelAr,
    required this.familyId,
    required this.familyLabelAr,
    required this.preset,
    this.figmaKey,
    this.colorOverride,
  });

  final String id;
  final String labelAr;
  final String familyId;
  final String familyLabelAr;
  final RestaurantPresetKey preset;
  /// مفتاح ملف Figma Community/Design (إلهام فقط).
  final String? figmaKey;
  final Map<String, String>? colorOverride;
}

/// صف واحد لكل رابط إلهام ≈ 28 — بدون تضخيم لوني فوق نفس الهيكل.
const kMenuGalleryEntries = <MenuGalleryEntry>[
  MenuGalleryEntry(
    id: 'thai_paper',
    labelAr: 'ورق تايلندي',
    familyId: 'paper',
    familyLabelAr: 'ورق وصور',
    preset: RestaurantPresetKey.classic,
    figmaKey: '3b022JEFQ5AoO2B88dN6nV',
  ),
  MenuGalleryEntry(
    id: 'qr_order_kit',
    labelAr: 'طقم طلب QR',
    familyId: 'app',
    familyLabelAr: 'تطبيق طلب',
    preset: RestaurantPresetKey.modern,
    figmaKey: 'kKj2x61LVRNSM3SGM1GTh1',
  ),
  MenuGalleryEntry(
    id: 'night_ink',
    labelAr: 'حبر ليلي',
    familyId: 'editorial',
    familyLabelAr: 'تحريري',
    preset: RestaurantPresetKey.dark,
    figmaKey: '1359993',
  ),
  MenuGalleryEntry(
    id: 'cafe_paper',
    labelAr: 'مقهى ورقي',
    familyId: 'paper',
    familyLabelAr: 'ورق وصور',
    preset: RestaurantPresetKey.cafe,
    figmaKey: '1210424',
  ),
  MenuGalleryEntry(
    id: 'magazine_fine',
    labelAr: 'مجلّة فاخرة',
    familyId: 'magazine',
    familyLabelAr: 'مجلّة',
    preset: RestaurantPresetKey.elegant,
    figmaKey: '1156774',
  ),
  MenuGalleryEntry(
    id: 'split_minimal',
    labelAr: 'صف نظيف',
    familyId: 'row',
    familyLabelAr: 'صف أفقي',
    preset: RestaurantPresetKey.minimal,
    figmaKey: '1280892',
  ),
  MenuGalleryEntry(
    id: 'royal_board',
    labelAr: 'لوحة ملكية',
    familyId: 'board',
    familyLabelAr: 'لوحة قائمة',
    preset: RestaurantPresetKey.royal,
    figmaKey: '1205630',
  ),
  MenuGalleryEntry(
    id: 'garden_soft',
    labelAr: 'حديقة ناعمة',
    familyId: 'soft',
    familyLabelAr: 'بطاقات ظل',
    preset: RestaurantPresetKey.garden,
    figmaKey: '1412705',
  ),
  MenuGalleryEntry(
    id: 'ocean_rail',
    labelAr: 'بحري بشريط',
    familyId: 'rail',
    familyLabelAr: 'شريط جانبي',
    preset: RestaurantPresetKey.ocean,
    figmaKey: '1457659',
  ),
  MenuGalleryEntry(
    id: 'bazaar_banner',
    labelAr: 'بازار شريطي',
    familyId: 'banner',
    familyLabelAr: 'شريط تصنيفات',
    preset: RestaurantPresetKey.bazaar,
    figmaKey: '1415899',
  ),
  MenuGalleryEntry(
    id: 'thai_hero',
    labelAr: 'بطل تايلندي',
    familyId: 'hero',
    familyLabelAr: 'غلاف بطل',
    preset: RestaurantPresetKey.thaiQr,
    figmaKey: '1340375',
  ),
  MenuGalleryEntry(
    id: 'order_tiles',
    labelAr: 'بلاطات طلب',
    familyId: 'tiles',
    familyLabelAr: 'بلاطات كثيفة',
    preset: RestaurantPresetKey.foodOrder,
    figmaKey: '1278025',
  ),
  MenuGalleryEntry(
    id: 'steak_cover',
    labelAr: 'ستيك ثم قائمة',
    familyId: 'cover',
    familyLabelAr: 'غلاف ثم قائمة',
    preset: RestaurantPresetKey.steakhouse,
    figmaKey: '1148211',
  ),
  MenuGalleryEntry(
    id: 'sushi_paper',
    labelAr: 'سوشي ورقي',
    familyId: 'paper',
    familyLabelAr: 'ورق وصور',
    preset: RestaurantPresetKey.sushiBar,
    figmaKey: '1303823',
  ),
  MenuGalleryEntry(
    id: 'pizza_soft',
    labelAr: 'بيتزا ناعمة',
    familyId: 'soft',
    familyLabelAr: 'بطاقات ظل',
    preset: RestaurantPresetKey.pizzeria,
    figmaKey: '1279449',
  ),
  MenuGalleryEntry(
    id: 'bakery_cover',
    labelAr: 'مخبز بطل',
    familyId: 'cover',
    familyLabelAr: 'غلاف ثم قائمة',
    preset: RestaurantPresetKey.bakery,
    figmaKey: '1430970',
  ),
  MenuGalleryEntry(
    id: 'juice_banner',
    labelAr: 'عصائر شريطية',
    familyId: 'banner',
    familyLabelAr: 'شريط تصنيفات',
    preset: RestaurantPresetKey.juiceBar,
    figmaKey: '1258746',
  ),
  MenuGalleryEntry(
    id: 'fine_board',
    labelAr: 'Fine لوحة',
    familyId: 'board',
    familyLabelAr: 'لوحة قائمة',
    preset: RestaurantPresetKey.fineDining,
    figmaKey: '1557830',
  ),
  MenuGalleryEntry(
    id: 'street_split',
    labelAr: 'شارع صفوف',
    familyId: 'row',
    familyLabelAr: 'صف أفقي',
    preset: RestaurantPresetKey.streetFood,
    figmaKey: '9848125',
  ),
  MenuGalleryEntry(
    id: 'vegan_story',
    labelAr: 'نباتي قصصي',
    familyId: 'story',
    familyLabelAr: 'قصة عمودية',
    preset: RestaurantPresetKey.veganGreen,
    figmaKey: '1548225',
  ),
  MenuGalleryEntry(
    id: 'dessert_soft',
    labelAr: 'حلويات ناعمة',
    familyId: 'soft',
    familyLabelAr: 'بطاقات ظل',
    preset: RestaurantPresetKey.dessertPastel,
    figmaKey: '1319184',
  ),
  MenuGalleryEntry(
    id: 'bbq_hero',
    labelAr: 'شواء بطل',
    familyId: 'hero',
    familyLabelAr: 'غلاف بطل',
    preset: RestaurantPresetKey.smokeBbq,
    figmaKey: '1576541',
  ),
  MenuGalleryEntry(
    id: 'med_rail',
    labelAr: 'متوسطي بشريط',
    familyId: 'rail',
    familyLabelAr: 'شريط جانبي',
    preset: RestaurantPresetKey.mediterranean,
    figmaKey: '1554784',
  ),
  MenuGalleryEntry(
    id: 'lacquer_mag',
    labelAr: 'لاكيه مجلّة',
    familyId: 'magazine',
    familyLabelAr: 'مجلّة',
    preset: RestaurantPresetKey.lacquerRed,
    figmaKey: '1229997',
  ),
  MenuGalleryEntry(
    id: 'pasta_stack',
    labelAr: 'باستا صور',
    familyId: 'paper',
    familyLabelAr: 'ورق وصور',
    preset: RestaurantPresetKey.pastaHouse,
    figmaKey: '1403768',
  ),
  MenuGalleryEntry(
    id: 'brunch_story',
    labelAr: 'برانش قصصي',
    familyId: 'story',
    familyLabelAr: 'قصة عمودية',
    preset: RestaurantPresetKey.brunchAir,
    figmaKey: '1641115',
  ),
  MenuGalleryEntry(
    id: 'night_banner',
    labelAr: 'سوق ليلي',
    familyId: 'banner',
    familyLabelAr: 'شريط تصنيفات',
    preset: RestaurantPresetKey.nightMarket,
    figmaKey: '1541987',
  ),
  MenuGalleryEntry(
    id: 'mezze_board',
    labelAr: 'مزة لوحة',
    familyId: 'board',
    familyLabelAr: 'لوحة قائمة',
    preset: RestaurantPresetKey.mezzeTable,
    figmaKey: '1231521',
  ),
];
