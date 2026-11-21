import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/print_settings_data.dart';
import 'receipt_model.dart';
import 'receipt_renderer.dart';

/// معاينة الإيصال بالصورة نفسها التي تُرسل للطابعة.
class ReceiptPreview extends StatefulWidget {
  const ReceiptPreview({
    super.key,
    required this.document,
    required this.settings,
    required this.template,
    required this.paper,
    this.style = const ReceiptStyle(),
    this.monochrome = true,
    this.maxWidth = 340,
  });

  final ReceiptDocument document;
  final PrintSettingsData settings;
  final ReceiptTemplate template;
  final ReceiptPaper paper;
  final ReceiptStyle style;

  /// طابعة حرارية: المعاينة بالأسود مثل الورق.
  final bool monochrome;
  final double maxWidth;

  @override
  State<ReceiptPreview> createState() => _ReceiptPreviewState();
}

class _ReceiptPreviewState extends State<ReceiptPreview> {
  ui.Image? _image;
  Object? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _render();
  }

  @override
  void didUpdateWidget(covariant ReceiptPreview old) {
    super.didUpdateWidget(old);
    if (old.document != widget.document ||
        old.settings != widget.settings ||
        old.template != widget.template ||
        old.paper != widget.paper ||
        old.style != widget.style ||
        old.monochrome != widget.monochrome) {
      _render();
    }
  }

  Future<void> _render() async {
    final gen = ++_generation;
    try {
      final r = await ReceiptRenderer.render(
        widget.document,
        settings: widget.settings,
        template: widget.template,
        paper: widget.paper,
        style: widget.style,
        monochrome: widget.monochrome,
      );
      if (!mounted || gen != _generation) {
        r.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = r.image;
        _error = null;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text('تعذر رسم المعاينة: $_error'),
      );
    }
    final img = _image;
    // 58 مم أضيق فعلاً من 80 مم في المعاينة أيضاً.
    final paperWidth =
        widget.maxWidth * (widget.paper == ReceiptPaper.mm58 ? 0.75 : 1);
    return Semantics(
      label: 'معاينة ${widget.document.title} على ورق ${widget.paper.label}',
      image: true,
      child: Center(
        child: LayoutBuilder(
          builder: (context, c) {
            final w = paperWidth.clamp(160.0, c.maxWidth);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: w,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: cs.outlineVariant),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: img == null
                  ? const SizedBox(
                      height: 240,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : RawImage(
                      image: img,
                      width: w,
                      fit: BoxFit.fitWidth,
                      filterQuality: FilterQuality.medium,
                    ),
            );
          },
        ),
      ),
    );
  }
}
