import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/system_notification_service.dart';
import '../../services/tenant_context_service.dart';
import '../push_device_registry.dart';
import '../server_notifications_repository.dart';
import 'owner_phone_prompt.dart';
import 'push_recipients_screen.dart';

/// مجموعة أنواع يطفئها مفتاح واحد.
class PushTypeGroup {
  const PushTypeGroup(this.title, this.subtitle, this.types);
  final String title;
  final String subtitle;
  final List<String> types;
}

/// أنواع الإشعارات كما يراها المالك (جدول الأنواع، خامسا البند 3).
const pushTypeGroups = <PushTypeGroup>[
  PushTypeGroup('فتح الوردية وإغلاقها', 'من فتح أو أغلق، وما في الصندوق', [
    'shift_open',
    'shift_close',
  ]),
  PushTypeGroup('فرق في الصندوق', 'نقص أو زيادة عند الإغلاق', [
    'cash_difference',
  ]),
  PushTypeGroup('المرتجعات', 'كل مرتجع ومبلغه', ['sale_return']),
  PushTypeGroup('بيع صنف غير متوفر', 'بيع بكمية أكبر من المخزون', [
    'negative_stock_sale',
  ]),
  PushTypeGroup('البيع بالدين والتقسيط', 'لمن ومبلغه', [
    'debt_sale',
    'installment_sale',
  ]),
  PushTypeGroup('النواقص', 'أصناف وصلت حد الطلب', [
    'oil_stock_shortage',
    'retail_stock_shortage',
    'clothing_variant_shortage',
  ]),
  PushTypeGroup('الأقساط', 'متأخرة أو تستحق اليوم', [
    'installment_overdue',
    'installment_due_today',
  ]),
  PushTypeGroup('ديون الزبائن', 'زبائن تأخروا في السداد', ['debt_customers']),
  PushTypeGroup('سيارات في الكراج', 'سيارة بقيت طويلا بلا إغلاق', [
    'oil_garage_stale',
    'oil_active_garage',
  ]),
  PushTypeGroup('بطيء الحركة', 'أصناف لم تُبع منذ مدة', [
    'clothing_slow_movers',
  ]),
  PushTypeGroup('طلبات السوق والمطعم', 'طلب جديد من السوق أو طاولة', [
    'market_order',
    'restaurant_order',
  ]),
  PushTypeGroup('ملخص اليوم', 'رسالة واحدة في المساء', ['daily_summary']),
  PushTypeGroup('عروض وأخبار نابو', 'إشعارات حسابك واشتراكك تصل دائما', [
    'naboo_ads',
  ]),
];

/// شاشة «إشعارات المحل»: هاتف المالك، الإذن، الأنواع، الهدوء، الملخص، التجربة.
class PushSettingsScreen extends StatefulWidget {
  const PushSettingsScreen({super.key});

  @override
  State<PushSettingsScreen> createState() => _PushSettingsScreenState();
}

class _PushSettingsScreenState extends State<PushSettingsScreen> {
  ServerNotificationPrefs? _prefs;
  bool? _permission;
  bool _busy = false;
  Timer? _saveDebounce;
  late final int _tenant = TenantContextService.instance.activeTenantId;
  final _minCtrl = TextEditingController();
  final _branchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _minCtrl.dispose();
    _branchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final reg = PushDeviceRegistry.instance;
    unawaited(reg.syncNow());
    final prefs = await ServerNotificationsRepository.loadPrefs(_tenant);
    final perm = await SystemNotificationService.instance
        .areNotificationsEnabled();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _permission = perm;
      _minCtrl.text = prefs.amountMin <= 0
          ? ''
          : prefs.amountMin.toStringAsFixed(0);
      _branchCtrl.text = prefs.branchName ?? '';
    });
  }

  void _changed({bool immediate = false}) {
    setState(() {});
    _saveDebounce?.cancel();
    _saveDebounce = Timer(Duration(milliseconds: immediate ? 0 : 700), _save);
  }

  Future<void> _save() async {
    final p = _prefs;
    if (p == null) return;
    final err = await ServerNotificationsRepository.savePrefs(_tenant, p);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Future<void> _pickTime(String current, ValueChanged<String> onPicked) async {
    final parts = current.split(':');
    final initial = TimeOfDay(
      hour: int.tryParse(parts.first) ?? 22,
      minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
    );
    final t = await showTimePicker(context: context, initialTime: initial);
    if (t == null) return;
    onPicked(
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
    );
    _changed(immediate: true);
  }

  Future<void> _toggleOwnerPhone(bool enable) async {
    setState(() => _busy = true);
    await OwnerPhonePrompt.confirmAndSetOwnerPhone(context, enable: enable);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _sendTest() async {
    setState(() => _busy = true);
    final err = await PushDeviceRegistry.instance.sendTest();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          err ??
              'أُرسل. يصل خلال ثوانٍ. إن لم يصل فراجع إذن الإشعارات والبطارية.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = context.select<AuthProvider, bool>((a) => a.isOwner);
    final theme = Theme.of(context);
    final reg = PushDeviceRegistry.instance;
    final p = _prefs;
    final multiBranch = TenantContextService.instance.tenants.length > 1;

    Widget header(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        t,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إشعارات المحل')),
        body: p == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  // ─── هاتف المالك ───
                  header('هاتف المالك'),
                  ValueListenableBuilder<bool>(
                    valueListenable: reg.thisDeviceIsOwnerPhone,
                    builder: (_, mine, __) => SwitchListTile(
                      secondary: const Icon(Icons.phone_iphone_rounded),
                      title: const Text('هذا الهاتف هو هاتف المالك'),
                      subtitle: Text(
                        !PushDeviceRegistry.isPhone
                            ? 'يُعلَّم الهاتف فقط، لا الحاسوب.'
                            : (mine
                                  ? 'تصله إشعارات المحل. الإزالة تحتاج رمز المالك.'
                                  : 'شغّله ليستلم هذا الهاتف إشعارات المحل. يحتاج رمز المالك.'),
                      ),
                      value: mine,
                      onChanged:
                          (!isOwner || _busy || !PushDeviceRegistry.isPhone)
                          ? null
                          : (v) => _toggleOwnerPhone(v),
                    ),
                  ),
                  ValueListenableBuilder<bool?>(
                    valueListenable: reg.accountHasOwnerPhone,
                    builder: (_, has, __) => has == false
                        ? const ListTile(
                            leading: Icon(Icons.notifications_off_rounded),
                            title: Text('لا يوجد هاتف مالك في الحساب'),
                            subtitle: Text(
                              'لن تصل إشعارات المحل إلى أي جهاز حتى تحدّده.',
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  // ─── الإذن ───
                  header('هذا الجهاز'),
                  ListTile(
                    leading: Icon(
                      _permission == false
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_active_outlined,
                    ),
                    title: Text(
                      _permission == false
                          ? 'الإشعارات غير مسموحة'
                          : 'الإشعارات مسموحة',
                    ),
                    subtitle: _permission == false
                        ? const Text(
                            'اضغط للسماح. إن رُفض الإذن من قبل فافتحه من إعدادات الهاتف.',
                          )
                        : null,
                    onTap: _permission == false
                        ? () async {
                            await OwnerPhonePrompt.maybeAskPermission(
                              context,
                              force: true,
                            );
                            final perm = await SystemNotificationService
                                .instance
                                .areNotificationsEnabled();
                            if (mounted) setState(() => _permission = perm);
                          }
                        : null,
                  ),
                  ListTile(
                    leading: const Icon(Icons.send_rounded),
                    title: const Text('أرسل إشعارا تجريبيا'),
                    subtitle: const Text(
                      'يصل إلى هذا الجهاز فقط، للتأكد أن الإشعارات تعمل.',
                    ),
                    onTap: _busy ? null : _sendTest,
                  ),
                  ListTile(
                    leading: const Icon(Icons.battery_alert_rounded),
                    title: const Text('الإشعارات تتأخر؟'),
                    subtitle: const Text('إعداد البطارية على بعض الهواتف'),
                    onTap: () => OwnerPhonePrompt.maybeShowBatteryGuide(
                      context,
                      force: true,
                    ),
                  ),

                  if (isOwner) ...[
                    // ─── الأنواع ───
                    header('ماذا يصلك'),
                    for (final g in pushTypeGroups)
                      SwitchListTile(
                        title: Text(g.title),
                        subtitle: Text(g.subtitle),
                        value: !g.types.any(p.disabledTypes.contains),
                        onChanged: (on) {
                          if (on) {
                            p.disabledTypes.removeAll(g.types);
                          } else {
                            p.disabledTypes.addAll(g.types);
                          }
                          _changed(immediate: true);
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.group_outlined),
                      title: const Text('من يستلم ماذا'),
                      subtitle: const Text(
                        'الموظفون الذين تصلهم إشعارات حسب صلاحياتهم',
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PushRecipientsScreen(),
                        ),
                      ),
                    ),

                    // ─── الحد الأدنى ───
                    header('الحد الأدنى للمبلغ'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _minCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText:
                              'لا ترسل البيع بالدين والمرتجع إن كان أقل من (د.ع)',
                          hintText: 'فارغ = كل المبالغ',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) {
                          p.amountMin =
                              double.tryParse(v.replaceAll(',', '').trim()) ??
                              0;
                          _changed();
                        },
                      ),
                    ),

                    // ─── الهدوء والملخص ───
                    header('الأوقات'),
                    ListTile(
                      leading: const Icon(Icons.bedtime_outlined),
                      title: const Text('ساعات الهدوء'),
                      subtitle: Text(
                        'من ${p.quietStart} إلى ${p.quietEnd}. العاجل يصل دائما.',
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          TextButton(
                            onPressed: () => _pickTime(
                              p.quietStart,
                              (v) => p.quietStart = v,
                            ),
                            child: const Text('البداية'),
                          ),
                          TextButton(
                            onPressed: () =>
                                _pickTime(p.quietEnd, (v) => p.quietEnd = v),
                            child: const Text('النهاية'),
                          ),
                        ],
                      ),
                    ),
                    ListTile(
                      leading: const Icon(Icons.summarize_outlined),
                      title: const Text('وقت ملخص اليوم'),
                      subtitle: Text(p.summaryTime),
                      onTap: () =>
                          _pickTime(p.summaryTime, (v) => p.summaryTime = v),
                    ),

                    // ─── الخصوصية ───
                    header('شاشة القفل'),
                    SwitchListTile(
                      title: const Text('إخفاء التفاصيل على شاشة القفل'),
                      subtitle: const Text(
                        'يظهر «لديك إشعار جديد من المحل» فقط',
                      ),
                      value: p.hideLockDetails,
                      onChanged: (v) {
                        p.hideLockDetails = v;
                        _changed(immediate: true);
                      },
                    ),

                    if (multiBranch) ...[
                      header('هذا الفرع'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: _branchCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم الفرع في الإشعار',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            p.branchName = v.trim().isEmpty ? null : v.trim();
                            _changed();
                          },
                        ),
                      ),
                      SwitchListTile(
                        title: const Text('كتم إشعارات هذا الفرع'),
                        value: p.muted,
                        onChanged: (v) {
                          p.muted = v;
                          _changed(immediate: true);
                        },
                      ),
                    ],
                  ],
                ],
              ),
      ),
    );
  }
}
