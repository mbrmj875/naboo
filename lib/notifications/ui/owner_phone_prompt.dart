import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../navigation/app_root_navigator_key.dart';
import '../../providers/auth_provider.dart';
import '../../services/system_notification_service.dart';
import '../../verticals/oil_change/widgets/oil_change_owner_pin_confirm_dialog.dart';
import '../push_device_registry.dart';

/// بطاقة «هل هذا هاتفك الشخصي؟» وشاشة شرح الإذن وبطاقة البطارية
/// (خطة الإشعارات، خامسا البندان 6 و8). كلها لمرة واحدة على الجهاز.
abstract final class OwnerPhonePrompt {
  OwnerPhonePrompt._();

  static bool _running = false;
  static bool _doneThisRun = false;
  static Timer? _pending;

  /// بعد الدخول بثوانٍ (حتى تستقر الشاشة الأولى)، مرة واحدة في كل تشغيل للتطبيق.
  static void scheduleAfterLogin() {
    if (_doneThisRun || _pending != null || !PushDeviceRegistry.isPhone) return;
    _pending = Timer(const Duration(seconds: 4), () {
      _pending = null;
      final ctx = appRootNavigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      _doneThisRun = true;
      unawaited(maybeShow(ctx));
    });
  }

  static Future<String> _key(String name) async {
    final uid = Supabase.instance.client.auth.currentUser?.id ?? 'local';
    return 'notif_$name:$uid';
  }

  /// يُستدعى بعد دخول ناجح (من الشاشة الرئيسية). لا يفعل شيئا لغير المالك أو على غير الهاتف.
  static Future<void> maybeShow(BuildContext context) async {
    if (_running || !PushDeviceRegistry.isPhone) return;
    final auth = context.read<AuthProvider>();
    if (!auth.isLoggedIn || !auth.isOwner) return;
    if (Supabase.instance.client.auth.currentUser == null) return;
    _running = true;
    try {
      final p = await SharedPreferences.getInstance();
      final cardKey = await _key('owner_phone_card_done_v1');
      if (p.getBool(cardKey) != true) {
        final reg = PushDeviceRegistry.instance;
        await reg.syncNow();
        if (!context.mounted) return;
        if (reg.thisDeviceIsOwnerPhone.value) {
          await p.setBool(cardKey, true);
        } else {
          final answer = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => const _OwnerPhoneCard(),
          );
          if (!context.mounted) return;
          if (answer == false) {
            await p.setBool(
              cardKey,
              true,
            ); // «لا، هذا جهاز المحل»: لا تعود البطاقة.
          } else if (answer == true) {
            final ok = await confirmAndSetOwnerPhone(context, enable: true);
            if (ok) await p.setBool(cardKey, true);
          }
        }
      }
      if (!context.mounted) return;
      await maybeAskPermission(context);
      if (!context.mounted) return;
      await maybeShowBatteryGuide(context);
    } finally {
      _running = false;
    }
  }

  /// تعليم هذا الجهاز أو إزالة علامته بعد رمز المالك. يعيد true عند النجاح.
  static Future<bool> confirmAndSetOwnerPhone(
    BuildContext context, {
    required bool enable,
    String? deviceId,
    String? deviceName,
  }) async {
    final reg = PushDeviceRegistry.instance;
    final target = deviceId ?? await reg.deviceId();
    final isThis = target == await reg.deviceId();
    if (!context.mounted) return false;

    var warn = '';
    if (!enable) {
      await reg.refreshOwnerPhoneStatus();
      // الإزالة عن آخر هاتف معلَّم تعيد الحجب (خامسا، البند 8).
      final flagged = await _flaggedCount();
      if (flagged <= 1) warn = '\n\nلن تصلك إشعارات المحل بعد هذا.';
    }
    if (!context.mounted) return false;
    final pinOk = await confirmOwnerPinForSensitiveAction(
      context,
      title: enable ? 'تأكيد هاتف المالك' : 'إزالة هاتف المالك',
      message: enable
          ? 'أدخل رمز المالك ليصبح ${isThis ? 'هذا الهاتف' : (deviceName ?? 'الجهاز')} هاتف المالك ويستلم إشعارات المحل.'
          : 'أدخل رمز المالك لإزالة العلامة عن ${isThis ? 'هذا الهاتف' : (deviceName ?? 'الجهاز')}.$warn',
      confirmLabel: enable ? 'تأكيد' : 'إزالة',
      destructive: !enable,
    );
    if (!pinOk || !context.mounted) return false;
    final err = await reg.setOwnerPhone(deviceId: target, enabled: enable);
    if (!context.mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              (enable
                  ? 'تم. هذا الهاتف يستلم إشعارات المحل الآن.'
                  : 'أُزيلت العلامة.'),
        ),
      ),
    );
    return err == null;
  }

  static Future<int> _flaggedCount() async {
    try {
      final c = Supabase.instance.client;
      final rows = await c
          .from('account_devices')
          .select('device_id')
          .eq('user_id', c.auth.currentUser!.id)
          .eq('owner_notify', true);
      return (rows as List).length;
    } catch (_) {
      return 0;
    }
  }

  /// شاشة قصيرة تشرح الفائدة بمثال حقيقي، ثم طلب الإذن. مرة واحدة إن لم يكن مسموحا.
  static Future<void> maybeAskPermission(
    BuildContext context, {
    bool force = false,
  }) async {
    final enabled = await SystemNotificationService.instance
        .areNotificationsEnabled();
    if (enabled == true && !force) return;
    final p = await SharedPreferences.getInstance();
    final key = await _key('permission_explained_v1');
    if (!force && p.getBool(key) == true) return;
    if (!context.mounted) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _PermissionExplainer(),
    );
    await p.setBool(key, true);
    if (go != true) return;
    await SystemNotificationService.instance.requestPermission();
    if (Firebase.apps.isNotEmpty) {
      try {
        await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}
    }
    unawaited(PushDeviceRegistry.instance.syncNow());
  }

  static const _aggressiveMakers = {
    'xiaomi',
    'redmi',
    'poco',
    'huawei',
    'honor',
    'oppo',
    'realme',
    'oneplus',
    'vivo',
    'samsung',
  };

  /// بطاقة لمرة واحدة على الهواتف التي توقف التطبيقات في الخلفية.
  static Future<void> maybeShowBatteryGuide(
    BuildContext context, {
    bool force = false,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final p = await SharedPreferences.getInstance();
    const key = 'notif_battery_guide_done_v1';
    if (!force && p.getBool(key) == true) return;
    String maker = '';
    try {
      maker = (await DeviceInfoPlugin().androidInfo).manufacturer.toLowerCase();
    } catch (_) {}
    if (!force && !_aggressiveMakers.contains(maker)) {
      await p.setBool(key, true);
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (d) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حتى لا تتأخر الإشعارات'),
          content: const Text(
            'بعض الهواتف توقف التطبيقات المغلقة لتوفير البطارية، فتتأخر الإشعارات أو لا تصل.\n\n'
            '1. افتح إعدادات الهاتف ← التطبيقات ← نابو.\n'
            '2. البطارية: اختر «بلا قيود» أو «السماح بالنشاط في الخلفية».\n'
            '3. إن وُجد «التشغيل التلقائي» فشغّله.\n\n'
            'تُضبط مرة واحدة فقط.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('فهمت'),
            ),
          ],
        ),
      ),
    );
    await p.setBool(key, true);
  }
}

class _OwnerPhoneCard extends StatelessWidget {
  const _OwnerPhoneCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        icon: const Icon(Icons.phone_iphone_rounded, size: 36),
        title: const Text('هل هذا هاتفك الشخصي؟'),
        content: Text(
          'إن كان هذا الهاتف معك دائما، تصلك عليه إشعارات المحل: إغلاق الوردية، '
          'فرق الصندوق، البيع بالدين، والمرتجعات.\n\n'
          'جهاز المحل الذي يعمل عليه الموظفون لا تصله هذه الإشعارات.',
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsOverflowDirection: VerticalDirection.down,
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('نعم، أرسل لي إشعارات المحل'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('لا، هذا جهاز المحل'),
          ),
        ],
      ),
    );
  }
}

class _PermissionExplainer extends StatelessWidget {
  const _PermissionExplainer();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'اعرف ما يحدث في محلك وأنت بعيد',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text('مثال لما سيصلك:', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.notifications_active_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'علي أغلق الوردية',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'في الصندوق 450,000 د.ع، والمسحوب 100,000 د.ع',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'ونصلك أيضا بفرق الصندوق، والبيع بالدين، والمرتجعات، والنواقص، وملخص المساء. '
                'تتحكم بكل نوع من الإعدادات، ولا يصلك شيء في ساعات الهدوء إلا العاجل.',
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('السماح بالإشعارات'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ليس الآن'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
