import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../providers/auth_provider.dart';

/// يؤكد قفل الجلسة ثم يعيد المستخدم إلى بوابة الموظفين.
Future<void> confirmAndLockSession(
  BuildContext context,
  AuthProvider auth,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('قفل الجلسة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ستعود إلى بوابة الموظفين. حساب Gmail يبقى مفعّلاً '
                'وهذا الجهاز يبقى نشطاً على السيرفر.\n\n'
                'لفصل الجهاز نهائياً: بوابة الموظفين ← «خروج نهائي من الحساب».',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('تأكيد'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (ok != true || !context.mounted) return;
  await auth.lockSession();
  if (!context.mounted) return;
  unawaited(Navigator.of(context).pushReplacementNamed('/employee-gate'));
}
