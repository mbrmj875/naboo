import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/auth_provider.dart';
import '../utils/screen_layout.dart';

/// بطاقة «بيانات المستخدم» — تخطيط عمودي واضح + نسخ لكل حقل أو للكل.
class UserInfoDialog extends StatelessWidget {
  const UserInfoDialog({super.key, required this.auth});

  final AuthProvider auth;

  static Future<void> show(BuildContext context, AuthProvider auth) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => UserInfoDialog(auth: auth),
    );
  }

  String _v(String raw) {
    final t = raw.trim();
    return t.isEmpty ? '—' : t;
  }

  String _allAsText() {
    final buf = StringBuffer()
      ..writeln('الاسم المعروض: ${_v(auth.displayName)}')
      ..writeln('اسم الدخول: ${_v(auth.username)}')
      ..writeln('الصلاحية: ${_v(auth.role)}')
      ..writeln('البريد الإلكتروني: ${_v(auth.email)}');
    return buf.toString().trim();
  }

  Future<void> _copy(BuildContext context, String text, {String? hint}) async {
    if (text.trim().isEmpty || text == '—') return;
    await Clipboard.setData(ClipboardData(text: text.trim()));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(hint ?? 'تم النسخ'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final layout = context.screenLayout;
    final dialogW = math.min(
      420.0,
      layout.size.width - layout.pageHorizontalGap * 2,
    );

    final fields = <_FieldData>[
      _FieldData(
        label: 'الاسم المعروض',
        value: _v(auth.displayName),
      ),
      _FieldData(
        label: 'اسم الدخول',
        value: _v(auth.username),
        ltr: auth.username.contains('@'),
      ),
      _FieldData(
        label: 'الصلاحية',
        value: _v(auth.role),
      ),
      _FieldData(
        label: 'البريد الإلكتروني',
        value: _v(auth.email),
        ltr: true,
      ),
    ];

    return Center(
      child: SizedBox(
        width: dialogW,
        child: AlertDialog(
          backgroundColor: cs.surface,
          surfaceTintColor: cs.surfaceTint,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: EdgeInsets.symmetric(
            horizontal: layout.pageHorizontalGap,
            vertical: 24,
          ),
          titlePadding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 0),
          title: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: cs.primaryContainer,
                child: Icon(Icons.person_rounded, color: cs.onPrimaryContainer),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'بيانات المستخدم',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface,
                      ),
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
          contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 0),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < fields.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _UserInfoFieldTile(data: fields[i]),
                ],
              ],
            ),
          ),
          actionsPadding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12),
          actions: [
            TextButton.icon(
              onPressed: () => _copy(
                context,
                _allAsText(),
                hint: 'تم نسخ كل البيانات',
              ),
              icon: Icon(Icons.copy_all_rounded, size: 20, color: cs.primary),
              label: Text(
                'نسخ الكل',
                style: TextStyle(
                  color: cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldData {
  const _FieldData({
    required this.label,
    required this.value,
    this.ltr = false,
  });

  final String label;
  final String value;
  final bool ltr;
}

class _UserInfoFieldTile extends StatelessWidget {
  const _UserInfoFieldTile({required this.data});

  final _FieldData data;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              data.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 4),
            SelectableText(
              data.value,
              textAlign: TextAlign.start,
              textDirection: data.ltr ? TextDirection.ltr : null,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    height: 1.35,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
