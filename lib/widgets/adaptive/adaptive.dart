/// Barrel export لكل ودجتس الـ Adaptive UI.
///
/// الاستخدام:
/// ```dart
/// import 'package:basra_store_manager/widgets/adaptive/adaptive.dart';
/// ```
library;

export 'adaptive_destination.dart';
export 'adaptive_scaffold.dart';
export 'master_detail_layout.dart';
export 'adaptive_search_bar.dart';
export 'shift_permission_banner.dart';
export 'home_user_menu.dart';
export 'adaptive_form_container.dart';

// تصدير صريح للمقاسات ليستخدمها المطور مع هذه المكونات بدون استيراد مزدوج
export '../../utils/screen_layout.dart'
    show DeviceVariant, ScreenLayout, ScreenLayoutX;
