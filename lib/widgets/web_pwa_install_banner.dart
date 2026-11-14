import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../platform/web_pwa_install.dart';

/// بانر بسيط لتثبيت نابو على الشاشة الرئيسية (ويب فقط).
class WebPwaInstallBanner extends StatefulWidget {
  const WebPwaInstallBanner({
    super.key,
    this.compact = false,
    this.margin = const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
  });

  final bool compact;
  final EdgeInsetsGeometry margin;

  @override
  State<WebPwaInstallBanner> createState() => _WebPwaInstallBannerState();
}

class _WebPwaInstallBannerState extends State<WebPwaInstallBanner> {
  bool _visible = false;
  bool _busy = false;
  bool _canNativeInstall = false;
  WebPwaPlatformHint _hint = WebPwaPlatformHint.desktop;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb || !WebPwaInstall.isWebSupported) return;
    _refresh();
    WebPwaInstall.listenInstallable(_refresh);
    WebPwaInstall.listenInstalled(() {
      if (!mounted) return;
      setState(() => _visible = false);
    });
  }

  void _refresh() {
    if (!mounted) return;
    final standalone = WebPwaInstall.isStandalone();
    final dismissed = WebPwaInstall.isBannerDismissed();
    setState(() {
      _hint = WebPwaInstall.platformHint();
      _canNativeInstall = WebPwaInstall.canInstall();
      _visible = !standalone && !dismissed;
    });
  }

  void _dismiss() {
    WebPwaInstall.dismissBannerForDays(14);
    setState(() => _visible = false);
  }

  Future<void> _install() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await WebPwaInstall.promptInstall();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.ok) {
      setState(() => _visible = false);
      return;
    }
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || !_visible) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final isIos = _hint == WebPwaPlatformHint.ios;
    final showInstallButton =
        _canNativeInstall || _hint == WebPwaPlatformHint.android
            || _hint == WebPwaPlatformHint.desktop;

    return Padding(
      padding: widget.margin,
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.95),
        elevation: 2,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            14,
            widget.compact ? 10 : 14,
            10,
            widget.compact ? 10 : 14,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: const Color(0xFF071A36),
                        alignment: Alignment.center,
                        child: const Text(
                          'NB',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ثبّت نابو على الشاشة الرئيسية',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isIos
                              ? 'يفتح مثل التطبيق بدون شريط المتصفح — من Safari فقط.'
                              : 'أيقونة نابو على الشاشة الرئيسية، مثل التطبيق العادي.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.35,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'إخفاء لمدة أسبوعين',
                    onPressed: _dismiss,
                    icon: const Icon(Icons.close_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (isIos) ...[
                const SizedBox(height: 10),
                _IosSteps(compact: widget.compact),
              ] else ...[
                const SizedBox(height: 12),
                if (_canNativeInstall)
                  FilledButton.icon(
                    onPressed: _busy ? null : _install,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_to_home_screen_rounded),
                    label: Text(_busy ? 'جاري التثبيت…' : 'تثبيت الآن'),
                  )
                else if (showInstallButton)
                  Text(
                    _hint == WebPwaPlatformHint.desktop
                        ? 'من قائمة المتصفح اختر «تثبيت التطبيق» أو أيقونة التثبيت بجانب شريط العنوان.'
                        : 'افتح الصفحة في Chrome ثم اضغط «تثبيت» من قائمة المتصفح.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.35,
                        ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _IosSteps extends StatelessWidget {
  const _IosSteps({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final steps = <(IconData, String)>[
      (Icons.ios_share_rounded, 'اضغط زر المشاركة في أسفل Safari'),
      (Icons.add_box_outlined, 'اختر «إضافة إلى الشاشة الرئيسية»'),
      (Icons.check_circle_outline, 'اضغط «إضافة»'),
    ];
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) SizedBox(height: compact ? 6 : 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: const Color(0xFF071A36),
                child: Text(
                  '${i + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(steps[i].$1, size: 20, color: const Color(0xFF071A36)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  steps[i].$2,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// يلف المحتوى ويُظهر بانر التثبيت في الأعلى على الويب فقط.
class WebPwaInstallHost extends StatelessWidget {
  const WebPwaInstallHost({
    super.key,
    required this.child,
    this.compact = false,
  });

  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WebPwaInstallBanner(compact: compact),
        Expanded(child: child),
      ],
    );
  }
}
