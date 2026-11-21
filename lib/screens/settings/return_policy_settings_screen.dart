import 'package:flutter/material.dart';

import '../../models/store_policy.dart';
import '../../services/store_policy_settings_repository.dart';
import 'policy_settings_save.dart';

/// سياسة الاسترجاع — للمالك فقط، والحفظ برمزه.
class ReturnPolicySettingsScreen extends StatefulWidget {
  const ReturnPolicySettingsScreen({super.key});

  @override
  State<ReturnPolicySettingsScreen> createState() =>
      _ReturnPolicySettingsScreenState();
}

class _ReturnPolicySettingsScreenState
    extends State<ReturnPolicySettingsScreen> {
  StorePolicy? _saved;
  late ReturnPolicy _p;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await StorePolicySettingsRepository.instance.load();
    if (!mounted) return;
    setState(() {
      _saved = s;
      _p = s.returns;
    });
  }

  Future<void> _save() async {
    final before = _saved!;
    setState(() => _saving = true);
    final ok = await saveStorePolicyWithOwnerPin(
      context,
      before: before,
      after: before.copyWith(returns: _p),
      eventType: 'return_policy_changed',
      sectionTitle: 'سياسة الاسترجاع',
      slice: (s) => s.returns.toJson(),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final saved = _saved;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سياسة الاسترجاع')),
        body: saved == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SwitchListTile(
                    value: _p.enabled,
                    title: const Text('السماح بالاسترجاع'),
                    subtitle: const Text(
                      'عند الإطفاء: مسح إيصال البيع يعرض التفاصيل فقط',
                    ),
                    onChanged: (v) =>
                        setState(() => _p = _p.copyWith(enabled: v)),
                  ),
                  const Divider(),
                  ListTile(
                    enabled: _p.enabled,
                    title: const Text('مدة الاسترجاع'),
                    subtitle: Text('${_p.windowDays} يوم من تاريخ الفاتورة'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'إنقاص',
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: !_p.enabled || _p.windowDays <= 1
                              ? null
                              : () => setState(
                                  () => _p = _p.copyWith(
                                    windowDays: _p.windowDays - 1,
                                  ),
                                ),
                        ),
                        Text(
                          '${_p.windowDays}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        IconButton(
                          tooltip: 'زيادة',
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: !_p.enabled || _p.windowDays >= 365
                              ? null
                              : () => setState(
                                  () => _p = _p.copyWith(
                                    windowDays: _p.windowDays + 1,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'بعد انتهاء المدة',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  RadioGroup<ReturnAfterWindow>(
                    groupValue: _p.afterWindow,
                    onChanged: (v) {
                      if (!_p.enabled || v == null) return;
                      setState(() => _p = _p.copyWith(afterWindow: v));
                    },
                    child: const Column(
                      children: [
                        RadioListTile<ReturnAfterWindow>(
                          value: ReturnAfterWindow.approval,
                          title: Text('مسموح بموافقة'),
                          subtitle: Text('المالك أو موظف كامل الصلاحية برمزه'),
                        ),
                        RadioListTile<ReturnAfterWindow>(
                          value: ReturnAfterWindow.forbidden,
                          title: Text('ممنوع'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  SwitchListTile(
                    value: _p.blockSelfApproval,
                    title: const Text('منع الموافقة الذاتية'),
                    subtitle: const Text(
                      'الموظف لا يوافق على استرجاعه بنفسه (المالك مستثنى)',
                    ),
                    onChanged: _p.enabled
                        ? (v) => setState(
                            () => _p = _p.copyWith(blockSelfApproval: v),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    color: cs.surfaceContainerHighest,
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text(
                        'قواعد ثابتة لا تُطفأ:\n'
                        '• لا استرجاع بدون إنترنت أو بدون وردية مفتوحة.\n'
                        '• سبب إلزامي، وتأكيد أن المواد سليمة وغير مفتوحة.\n'
                        '• المواد ترجع للمخزن، والآجل يُخصم من الدين.\n'
                        '• الإيصال القديم بلا رمز موثّق يحتاج موافقة دائماً.\n'
                        '• لا تُسترجع المادة مرتين من أي جهاز.',
                        style: TextStyle(height: 1.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _saving || _p == saved.returns ? null : _save,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('حفظ برمز المالك'),
                  ),
                ],
              ),
      ),
    );
  }
}
