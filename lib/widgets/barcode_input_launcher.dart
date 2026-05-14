import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/screen_layout.dart';
import '../utils/target_platform_helpers.dart';

class BarcodeInputLauncher {
  /// كاميرا المسح: **Android / iOS** فقط؛ على **Windows / macOS / Linux** يُستخدم قارئ
  /// الباركود عبر لوحة المفاتيح. على **الويب** يُفعَّل للشاشات بعرض هاتف تقريباً.
  static bool useCamera(BuildContext context) {
    if (isMobileOsBuild) return true;
    if (kIsWeb) {
      return MediaQuery.sizeOf(context).shortestSide < 600;
    }
    return false;
  }

  static Future<String?> captureBarcode(
    BuildContext context, {
    String title = 'التقاط باركود',
    /// على **Android / iOS** مع `phoneXS`/`phoneSM`: نافذة صغيرة فوق البيع
    /// بدل استبدال الشاشة بالكامل — أسرع ولا يفقد سياق السلة.
    bool preferCompactHandsetOverlay = false,
  }) async {
    if (useCamera(context)) {
      final compact = preferCompactHandsetOverlay &&
          isMobileOsBuild &&
          ScreenLayout.of(context).isPhoneVariant;
      if (compact) {
        // لوحة مسح قابلة للرفع/الخفض (مثل الصورة المطلوبة) بدون إغلاق بالسحب/الضغط خارجها.
        return showModalBottomSheet<String>(
          context: context,
          isScrollControlled: true,
          useSafeArea: false,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: 0.35),
          isDismissible: false,
          enableDrag: false, // منع سحب الأسفل للإغلاق (نستخدم DraggableScrollableSheet للتمديد)
          builder: (ctx) {
            final bottomInset = MediaQuery.viewPaddingOf(ctx).bottom;
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: _HandsetScannerSheet(title: title),
            );
          },
        );
      }
      return Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (_) => _CameraBarcodePage(title: title),
        ),
      );
    }
    return _captureFromKeyboardDevice(context, title: title);
  }

  static Future<String?> _captureFromKeyboardDevice(
    BuildContext context, {
    required String title,
  }) async {
    final ctrl = TextEditingController();
    final focus = FocusNode();
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'وجّه المؤشر إلى الحقل ثم مرّر الباركود عبر جهاز القراءة المتصل.',
              ),
              const SizedBox(height: 12),
              KeyboardListener(
                focusNode: focus,
                onKeyEvent: (event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter) {
                    final v = ctrl.text.trim();
                    if (v.isNotEmpty) {
                      Navigator.of(ctx).pop(v);
                    }
                  }
                },
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (v) {
                    final t = v.trim();
                    if (t.isNotEmpty) {
                      Navigator.of(ctx).pop(t);
                    }
                  },
                  decoration: const InputDecoration(
                    hintText: 'قارئ الباركود سيكتب هنا',
                    prefixIcon: Icon(Icons.keyboard_alt_rounded),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (v.isNotEmpty) {
                  Navigator.of(ctx).pop(v);
                }
              },
              child: const Text('تأكيد'),
            ),
          ],
        );
      },
    );
  }
}

/// لوحة مسح سفلية قابلة للرفع/الخفض (لا تُغلق بالسحب للأسفل).
class _HandsetScannerSheet extends StatefulWidget {
  const _HandsetScannerSheet({required this.title});

  final String title;

  @override
  State<_HandsetScannerSheet> createState() => _HandsetScannerSheetState();
}

class _HandsetScannerSheetState extends State<_HandsetScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue?.trim();
    if (code == null || code.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final outline = cs.outline;
    final topPad = MediaQuery.viewPaddingOf(context).top;

    return WillPopScope(
      onWillPop: () async => false, // لا تُغلق بالزر الخلفي على الهاتف
      child: DraggableScrollableSheet(
        initialChildSize: 0.34,
        minChildSize: 0.22,
        maxChildSize: 0.92,
        snap: true,
        snapSizes: const [0.22, 0.34, 0.6, 0.92],
        builder: (context, scrollController) {
          return Material(
            color: cs.surface,
            elevation: 14,
            shadowColor: Colors.black.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              side: BorderSide(color: outline.withValues(alpha: 0.45), width: 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Handle + header
                Padding(
                  padding: EdgeInsets.only(top: topPad > 0 ? 6 : 10),
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'إغلاق',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'تشغيل/إيقاف الفلاش',
                        onPressed: () => _controller.toggleTorch(),
                        icon: const Icon(Icons.flash_on_rounded),
                      ),
                      IconButton(
                        tooltip: 'تبديل الكاميرا',
                        onPressed: () => _controller.switchCamera(),
                        icon: const Icon(Icons.cameraswitch_rounded),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: LayoutBuilder(
                        builder: (context, c) {
                          final pad = 10.0;
                          final rect = Rect.fromLTWH(
                            pad,
                            pad,
                            (c.maxWidth - 2 * pad).clamp(1.0, c.maxWidth),
                            (c.maxHeight - 2 * pad).clamp(1.0, c.maxHeight),
                          );
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              MobileScanner(
                                controller: _controller,
                                scanWindow: rect,
                                onDetect: _onDetect,
                              ),
                              IgnorePointer(
                                child: CustomPaint(
                                  painter: _ScanOverlayPainter(scanRect: rect),
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 10,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text(
                                      'وجّه الباركود داخل الإطار',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CameraBarcodePage extends StatefulWidget {
  const _CameraBarcodePage({required this.title});

  final String title;

  @override
  State<_CameraBarcodePage> createState() => _CameraBarcodePageState();
}

class _CameraBarcodePageState extends State<_CameraBarcodePage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final boxSize = (size.width * 0.68).clamp(220.0, 340.0);
    final left = (size.width - boxSize) / 2;
    final top = (size.height - boxSize) / 2 - 40;
    final scanRect = Rect.fromLTWH(left, top, boxSize, boxSize);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            scanWindow: scanRect,
            onDetect: (capture) {
              if (_handled) return;
              if (capture.barcodes.isEmpty) return;
              final code = capture.barcodes.first.rawValue?.trim();
              if (code == null || code.isEmpty) return;
              _handled = true;
              Navigator.of(context).pop(code);
            },
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ScanOverlayPainter(scanRect: scanRect),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 40,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.zero,
                ),
                child: const Text(
                  'وجّه الكاميرا إلى QR أو Barcode داخل الإطار',
                  style: TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({required this.scanRect});

  final Rect scanRect;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()..color = Colors.black.withValues(alpha: 0.45);
    final clearPaint = Paint()..blendMode = BlendMode.clear;
    final borderPaint = Paint()
      ..color = const Color(0xFF22D3EE)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final layerRect = Offset.zero & size;
    canvas.saveLayer(layerRect, Paint());
    canvas.drawRect(layerRect, overlayPaint);
    canvas.drawRect(scanRect, clearPaint);
    canvas.drawRect(scanRect, borderPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) {
    return oldDelegate.scanRect != scanRect;
  }
}
