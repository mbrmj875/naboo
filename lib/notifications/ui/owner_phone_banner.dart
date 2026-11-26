import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../push_device_registry.dart';
import 'push_settings_screen.dart';

/// «الإشعارات متوقفة. حدّد هاتف المالك لتصلك» (قاعدة الحجب، خامسا البند 8).
///
/// يظهر فقط حين يعرف الخادم أن الحساب بلا هاتف مالك (القيمة false، لا null).
/// المالك يضغط فيذهب إلى مكان التحديد، والموظف يرى سطرا يشرح فقط.
class OwnerPhoneBanner extends StatelessWidget {
  const OwnerPhoneBanner({
    super.key,
    this.margin = const EdgeInsets.fromLTRB(12, 8, 12, 4),
  });

  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final reg = PushDeviceRegistry.instance;
    return ValueListenableBuilder<bool?>(
      valueListenable: reg.accountHasOwnerPhone,
      builder: (context, has, _) {
        if (has != false) return const SizedBox.shrink();
        final isOwner = context.select<AuthProvider, bool>((a) => a.isOwner);
        final cs = Theme.of(context).colorScheme;
        final text = isOwner
            ? 'الإشعارات متوقفة. حدّد هاتف المالك لتصلك'
            : 'الإشعارات متوقفة حتى يحدّد المالك هاتفه';
        return Padding(
          padding: margin,
          child: Material(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: isOwner
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const PushSettingsScreen(),
                      ),
                    )
                  : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_off_rounded,
                      color: cs.onErrorContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          color: cs.onErrorContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (isOwner)
                      Icon(
                        Icons.chevron_left_rounded,
                        color: cs.onErrorContainer,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
