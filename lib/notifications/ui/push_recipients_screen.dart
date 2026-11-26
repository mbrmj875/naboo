import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/permission_service.dart';

/// «من يستلم ماذا» (المرحلة 5): قراءة فقط.
/// هاتف المالك يستلم كل شيء، والموظف يستلم ما تسمح به صلاحيته على الجهاز الذي دخل منه.
class PushRecipientsScreen extends StatefulWidget {
  const PushRecipientsScreen({super.key});

  @override
  State<PushRecipientsScreen> createState() => _PushRecipientsScreenState();
}

class _Route {
  const _Route(this.title, this.permKey);
  final String title;
  final String? permKey; // null = هاتف المالك فقط
}

const _routes = <_Route>[
  _Route('الورديات وفرق الصندوق', null),
  _Route('المرتجعات', null),
  _Route('البيع بالدين والتقسيط', null),
  _Route('ملخص اليوم', null),
  _Route('بيع صنف غير متوفر والنواقص', PermissionKeys.inventoryView),
  _Route('طلبات السوق والمطعم وسيارات الكراج', PermissionKeys.salesPos),
  _Route('الأقساط المتأخرة', PermissionKeys.installmentsPlans),
  _Route('ديون الزبائن', PermissionKeys.debtsPanel),
];

class _Device {
  _Device(this.name, this.ownerPhone, this.role, this.perms);
  final String name;
  final bool ownerPhone;
  final String? role;
  final List<String> perms;
}

class _PushRecipientsScreenState extends State<PushRecipientsScreen> {
  List<_Device>? _devices;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = Supabase.instance.client;
      final uid = c.auth.currentUser!.id;
      final acc = await c
          .from('account_devices')
          .select('device_id, device_name, owner_notify, access_status')
          .eq('user_id', uid);
      final push = await c
          .from('push_devices')
          .select('device_id, role_key, permission_keys, enabled')
          .eq('user_id', uid)
          .eq('enabled', true);
      final pushById = {
        for (final r in (push as List).whereType<Map<String, dynamic>>())
          r['device_id'].toString(): r,
      };
      final out = <_Device>[];
      for (final r in (acc as List).whereType<Map<String, dynamic>>()) {
        if ((r['access_status'] ?? 'active').toString() != 'active') continue;
        final p = pushById[r['device_id'].toString()];
        if (p == null) continue; // لا يستلم إشعارات أصلا
        out.add(
          _Device(
            (r['device_name'] ?? 'جهاز').toString(),
            r['owner_notify'] == true,
            p['role_key']?.toString(),
            ((p['permission_keys'] as List?) ?? const [])
                .map((e) => '$e')
                .toList(),
          ),
        );
      }
      if (mounted) setState(() => _devices = out);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذر التحميل. تحقق من الاتصال.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = _devices;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('من يستلم ماذا')),
        body: _error != null
            ? Center(child: Text(_error!))
            : devices == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'هاتف المالك يستلم كل الأنواع. الموظف يستلم النوع إذا كانت عنده صلاحيته '
                    'وكان داخلا على جهاز يقبل الإشعارات. تغيّر الصلاحيات من إدارة المستخدمين.',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  for (final r in _routes) ...[
                    Text(
                      r.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._recipients(r, devices).map((t) => Text('• $t')),
                    const SizedBox(height: 14),
                  ],
                ],
              ),
      ),
    );
  }

  List<String> _recipients(_Route r, List<_Device> devices) {
    final out = <String>[];
    for (final d in devices) {
      if (d.ownerPhone) {
        out.add('${d.name} (هاتف المالك)');
      } else if (r.permKey != null &&
          d.role != null &&
          d.role != 'owner' &&
          d.perms.contains(r.permKey)) {
        out.add('${d.name} (موظف داخل الآن)');
      }
    }
    if (out.isEmpty) out.add('لا أحد الآن');
    return out;
  }
}
