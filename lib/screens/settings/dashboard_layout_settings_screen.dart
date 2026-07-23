import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/business_features_provider.dart';
import '../../providers/dashboard_layout_provider.dart';

/// إعدادات إظهار أقسام الرئيسية وترتيبها (سحب وإفلات) + ميزات اختيارية.
class DashboardLayoutSettingsScreen extends StatelessWidget {
  const DashboardLayoutSettingsScreen({super.key});

  Future<void> _setCarWashEnabled(
    BuildContext context,
    bool enabled,
  ) async {
    final features = context.read<BusinessFeaturesProvider>();
    try {
      await features.setCarWashEnabledForActiveUser(enabled);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'تم تفعيل غسل السيارات لهذا المستخدم فقط'
                : 'تم إخفاء غسل السيارات لهذا المستخدم',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذر حفظ الإعداد. تأكد من تسجيل الدخول ثم أعد المحاولة.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = context.watch<DashboardLayoutProvider>();
    final features = context.watch<BusinessFeaturesProvider>();
    final showCarWashToggle = features.data.enableOilChange;
    final carWashOn = features.data.enableCarWash;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          title: const Text(
            'تخصيص الشاشة الرئيسية',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'فعّل أو عطّل كل قسم، ثم اسحب من أيقونة ⋮⋮ لترتيب الظهور من الأعلى إلى الأسفل.',
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'الترتيب على الرئيسية',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: layout.order.length,
              onReorder: layout.reorder,
              itemBuilder: (context, index) {
                final id = layout.order[index];
                final title = DashboardLayoutProvider.sectionTitleAr(id);
                final locked = id == 'header' && layout.isHeaderVisibilityLocked;
                final visible = layout.isVisible(id);

                return Card(
                  key: ValueKey<String>(id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    contentPadding: const EdgeInsetsDirectional.only(
                      start: 8,
                      end: 12,
                    ),
                    leading: ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 4),
                        child: Icon(
                          Icons.drag_handle_rounded,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    title: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: id == 'header'
                        ? const Text('ثابت في الأعلى — لا يُخفى')
                        : null,
                    trailing: Switch.adaptive(
                      value: visible,
                      onChanged: locked
                          ? null
                          : (v) => layout.setSectionVisible(id, v),
                    ),
                  ),
                );
              },
            ),
            if (showCarWashToggle) ...[
              const SizedBox(height: 20),
              Text(
                'خدمات اختيارية لهذا المستخدم',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  contentPadding: const EdgeInsetsDirectional.only(
                    start: 16,
                    end: 12,
                  ),
                  leading: Icon(
                    Icons.local_car_wash_rounded,
                    color: cs.primary,
                  ),
                  title: const Text(
                    'غسل السيارات',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    carWashOn
                        ? 'ظاهر لهذا المستخدم فقط — لا يظهر لباقي الموظفين'
                        : 'معطّل لهذا المستخدم. فعّله فقط إن كان يقدّم غسيل سيارات',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: Switch.adaptive(
                    value: carWashOn,
                    onChanged: (v) => _setCarWashEnabled(context, v),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('استعادة الافتراضي؟'),
                    content: const Text(
                      'سيتم إظهار كل الأقسام وترتيبها كما في التطبيق الأصلي. '
                      'إعداد غسل السيارات لهذا المستخدم لا يتغيّر.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('إلغاء'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('استعادة'),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  await layout.resetToDefaults();
                }
              },
              icon: const Icon(Icons.restore_rounded),
              label: const Text('استعادة الترتيب والظهور الافتراضيين'),
            ),
          ],
        ),
      ),
    );
  }
}
