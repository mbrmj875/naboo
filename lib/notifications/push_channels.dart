import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// قنوات أندرويد (خطة الإشعارات، خامسا البند 4). المعرّفات نفسها في
/// supabase/functions/notify-dispatch/decide.ts (channelFor)، فلا تُغيَّر إلا معا.
///
/// صوت القناة يُثبَّت عند إنشائها: تغيير صوت «عاجل» أو «طلبات» لاحقا يحتاج معرّف قناة جديدا.
class PushChannel {
  const PushChannel(
    this.id,
    this.name,
    this.description,
    this.importance, {
    this.customSound = false,
  });

  final String id;
  final String name;
  final String description;
  final Importance importance;
  final bool customSound;

  AndroidNotificationChannel toAndroid() => AndroidNotificationChannel(
    id,
    name,
    description: description,
    importance: importance,
    playSound: importance.value >= Importance.defaultImportance.value,
    sound: customSound
        ? const RawResourceAndroidNotificationSound('naboo_alert')
        : null,
    enableVibration: importance.value >= Importance.high.value,
    showBadge: true,
  );
}

abstract final class PushChannels {
  PushChannels._();

  static const orders = PushChannel(
    'naboo_orders',
    'طلبات',
    'طلب جديد من السوق أو من طاولة في المطعم.',
    Importance.max,
    customSound: true,
  );
  static const urgent = PushChannel(
    'naboo_urgent',
    'عاجل',
    'فرق في الصندوق، وبيع أدى إلى رصيد سالب. يصل حتى في ساعات الهدوء.',
    Importance.max,
    customSound: true,
  );
  static const shop = PushChannel(
    'naboo_shop',
    'حركة المحل',
    'فتح وإغلاق الوردية، المرتجعات، والبيع بالدين أو التقسيط.',
    Importance.high,
  );
  static const business = PushChannel(
    'naboo_business',
    'تنبيهات العمل',
    'نواقص، صلاحية، أقساط، ديون، وسيارات متأخرة في الورشة.',
    Importance.defaultImportance,
  );
  static const summary = PushChannel(
    'naboo_summary',
    'الملخص اليومي',
    'ملخص المبيعات في المساء.',
    Importance.defaultImportance,
  );
  static const ads = PushChannel(
    'naboo_ads',
    'إعلانات وعروض من نابو',
    'ميزات جديدة وعروض. يمكن إيقافها.',
    Importance.low,
  );
  static const account = PushChannel(
    'naboo_account',
    'حسابك واشتراكك',
    'قرب انتهاء الاشتراك والتحديث الإلزامي.',
    Importance.high,
  );

  static const all = [orders, urgent, shop, business, summary, ads, account];

  /// القناة القديمة: تبقى للتنبيهات المحلية وللنسخ القديمة من الخادم.
  static const legacyId = 'naboo_alerts';

  static PushChannel byId(String? id) =>
      all.firstWhere((c) => c.id == id, orElse: () => business);

  /// نفس قاعدة الخادم (channelFor) للعرض في المقدمة.
  static PushChannel forCategory(String category, String priority) {
    if (category == 'orders') return orders;
    if (priority == 'critical') return urgent;
    switch (category) {
      case 'shop_event':
        return shop;
      case 'summary':
        return summary;
      case 'naboo_ads':
        return ads;
      case 'naboo_account':
        return account;
      default:
        return business;
    }
  }
}
