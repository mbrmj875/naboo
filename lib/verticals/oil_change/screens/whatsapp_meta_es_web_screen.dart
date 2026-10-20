import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/design_tokens.dart';
import '../widgets/oil_change_form_theme.dart';

/// إكمال Embedded Signup عبر متصفح النظام / Custom Tabs.
/// لا نستخدم WebView هنا — يسبب أعطال تسجيل المنصة على بعض الأجهزة.
class WhatsappMetaEsWebScreen extends StatefulWidget {
  const WhatsappMetaEsWebScreen({
    super.key,
    required this.pageUrl,
  });

  final String pageUrl;

  @override
  State<WhatsappMetaEsWebScreen> createState() =>
      _WhatsappMetaEsWebScreenState();
}

class _WhatsappMetaEsWebScreenState extends State<WhatsappMetaEsWebScreen>
    with WidgetsBindingObserver {
  var _opening = false;
  String? _error;
  String? _hint;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openMetaPage());
      unawaited(_listenDeepLinks());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_linkSub?.cancel() ?? Future<void>.value());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {
        _hint =
            'إذا أنهيت التأكيد في فيسبوك ولم ترجع تلقائياً: اضغط «تم» ثم «تحديث حالة التجهيز».';
      });
    }
  }

  Future<void> _listenDeepLinks() async {
    try {
      final links = AppLinks();
      _linkSub = links.uriLinkStream.listen((uri) {
        if (!mounted) return;
        if (uri.host == 'whatsapp-es-complete' ||
            uri.path.contains('whatsapp-es-complete')) {
          Navigator.of(context).maybePop();
        }
      });
    } catch (_) {
      /* ignore — الشاشة تعمل بدون deep link */
    }
  }

  Future<void> _openMetaPage() async {
    final uri = Uri.tryParse(widget.pageUrl.trim());
    if (uri == null) {
      setState(() => _error = 'رابط الربط غير صالح.');
      return;
    }

    setState(() {
      _opening = true;
      _error = null;
    });

    try {
      var ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!ok) {
        ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!ok && mounted) {
        setState(() => _error = 'تعذّر فتح صفحة Meta. حاول مرة أخرى.');
      }
    } catch (_) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!ok && mounted) {
          setState(() => _error = 'تعذّر فتح صفحة Meta.');
        }
      } catch (_) {
        if (mounted) {
          setState(() => _error = 'تعذّر فتح صفحة Meta على هذا الجهاز.');
        }
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Theme(
      data: OilChangeFormTheme.wrap(context, Theme.of(context)),
      child: Scaffold(
        appBar: OilChangeFormTheme.appBar(
          context: context,
          title: 'إكمال الربط عبر Meta',
          actions: const [],
        ),
        body: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(20, 20, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: [
                    AppColors.primary,
                    AppColors.primary.withValues(alpha: 0.88),
                    OilChangeFormTheme.gold.withValues(alpha: 0.35),
                  ],
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                      border: Border.all(
                        color: OilChangeFormTheme.gold.withValues(alpha: 0.55),
                      ),
                    ),
                    child: const Icon(
                      Icons.verified_rounded,
                      size: 36,
                      color: OilChangeFormTheme.gold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'أكمل التسجيل في Meta',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'سيفتح فيسبوك في نفس الصفحة ثم يعود لنابو بعد التأكيد.\n'
                    'لا تغلق المتصفح حتى تظهر رسالة النجاح.\n'
                    'إن ظهرت «الحافظة لا تحتوي حسابات واتساب»: عودة → أنشئ حساب واتساب من Business Suite → أعد من هنا.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_opening)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (_hint != null) ...[
              Material(
                color: OilChangeFormTheme.gold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(_hint!, style: const TextStyle(height: 1.4)),
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_error != null) ...[
              Material(
                color: cs.errorContainer.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _error!,
                    style: TextStyle(color: cs.onErrorContainer, height: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
            ],
            FilledButton.icon(
              onPressed: _opening ? null : () => unawaited(_openMetaPage()),
              icon: const Icon(Icons.open_in_browser_rounded),
              label: Text(_opening ? 'جاري الفتح…' : 'فتح تسجيل Meta'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.check_rounded),
              label: const Text('تم — رجعت من Meta'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: OilChangeFormTheme.gold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'مهم: لا تغلق تبويب فيسبوك يدوياً أثناء الربط. بعد النجاح ستعود هذه الشاشة للتطبيق تلقائياً.',
              style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
