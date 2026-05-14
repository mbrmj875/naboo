import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/license_service.dart';

class RestrictedModeBannerController extends StatefulWidget {
  const RestrictedModeBannerController({super.key, required this.child});
  final Widget child;

  @override
  State<RestrictedModeBannerController> createState() =>
      _RestrictedModeBannerControllerState();
}

class _RestrictedModeBannerControllerState
    extends State<RestrictedModeBannerController> {
  MaterialBanner? _lastBanner;
  bool _retrying = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBanner();
  }

  @override
  void didUpdateWidget(covariant RestrictedModeBannerController oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBanner();
  }

  void _syncBanner() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        final lic = context.read<LicenseService>();
        final messenger = ScaffoldMessenger.of(context);

        final restricted = lic.state.status == LicenseStatus.restricted;
        if (!restricted) {
          if (_lastBanner != null) {
            messenger.clearMaterialBanners();
            _lastBanner = null;
          }
          return;
        }

        final cs = Theme.of(context).colorScheme;
        final banner = MaterialBanner(
          backgroundColor: cs.errorContainer,
          leading: Icon(
            Icons.warning_amber_rounded,
            color: cs.onErrorContainer,
          ),
          content: Text(
            lic.state.message?.trim().isNotEmpty == true
                ? lic.state.message!
                : 'وضع مقيّد — اتصل بالإنترنت للتحقق',
            style: TextStyle(color: cs.onErrorContainer),
          ),
          actions: [
            TextButton(
              onPressed: _retrying
                  ? null
                  : () async {
                      _retrying = true;
                      try {
                        await LicenseService.instance.checkLicense(
                          forceRemote: true,
                        );
                      } finally {
                        if (mounted) {
                          setState(() {
                            _retrying = false;
                          });
                        }
                      }
                    },
              child: const Text('إعادة المحاولة'),
            ),
          ],
        );

        // Avoid re-showing same banner every rebuild.
        if (_lastBanner != null) return;
        _lastBanner = banner;
        messenger.hideCurrentMaterialBanner();
        messenger.showMaterialBanner(banner);
      } catch (_) {
        // أول إطار أو سياق بلا ScaffoldMessenger — لا نُسقط الشجرة بأكملها.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild triggers via Provider in parent; controller only shows banner.
    context.watch<LicenseService>();
    return widget.child;
  }
}
