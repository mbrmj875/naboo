import 'package:flutter/material.dart';

import '../services/app_in_app_update_service.dart';
import '../utils/app_logger.dart';

/// حوار تحديث: تنزيل في الخلفية + تثبيت + انتظار إعادة الفتح.
Future<void> showAppUpdateAndInstallDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String downloadUrl,
  bool force = false,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !force,
    builder: (ctx) => _AppUpdateInstallDialog(
      title: title,
      message: message,
      downloadUrl: downloadUrl,
      force: force,
    ),
  );
}

class _AppUpdateInstallDialog extends StatefulWidget {
  const _AppUpdateInstallDialog({
    required this.title,
    required this.message,
    required this.downloadUrl,
    required this.force,
  });

  final String title;
  final String message;
  final String downloadUrl;
  final bool force;

  @override
  State<_AppUpdateInstallDialog> createState() =>
      _AppUpdateInstallDialogState();
}

class _AppUpdateInstallDialogState extends State<_AppUpdateInstallDialog> {
  bool _busy = false;
  double _progress = 0;
  String _status = '';
  String? _error;

  Future<void> _start() async {
    if (_busy) return;
    final update = AppInAppUpdateService.instance;
    if (!update.isAndroidInAppUpdateSupported) {
      setState(() {
        _error = 'التحديث التلقائي متاح على أندرويد فقط.';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _progress = 0;
      _status = 'جاري التحضير…';
    });

    try {
      await update.downloadAndInstall(
        downloadUrl: widget.downloadUrl,
        onProgress: (p) {
          if (!mounted) return;
          setState(() => _progress = p);
        },
        onStatus: (s) {
          if (!mounted) return;
          setState(() => _status = s);
        },
      );
    } catch (e, st) {
      AppLogger.error('InAppUpdate', 'downloadAndInstall failed', e, st);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is StateError
            ? e.message
            : 'تعذر التحديث. حاول مرة أخرى.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !widget.force && !_busy,
      child: AlertDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.message),
              if (_busy) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: _progress <= 0 || _progress >= 1 ? null : _progress,
                ),
                const SizedBox(height: 8),
                Text(
                  _status.isEmpty
                      ? 'جاري العمل…'
                      : '$_status${_progress > 0 && _progress < 1 ? ' (${(_progress * 100).round()}%)' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (!widget.force && !_busy)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('لاحقاً'),
            ),
          FilledButton(
            onPressed: _busy ? null : _start,
            child: Text(_busy ? 'جاري التحديث…' : 'تحديث التطبيق الآن'),
          ),
        ],
      ),
    );
  }
}
