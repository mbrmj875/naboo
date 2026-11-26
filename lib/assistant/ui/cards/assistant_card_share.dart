import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../assistant_view_models.dart';
import 'assistant_cards.dart';

/// مشاركة بطاقة المساعد كصورة (ق64، م2-20).
///
/// البطاقة تُصوَّر كما تظهر، وتُرسل في صفحة PDF واحدة عبر قائمة المشاركة نفسها
/// التي تشارك بها الإيصالات، فلا حزمة جديدة. ما لا يُشارك أبداً: بطاقة الزبون
/// (فيها هاتفه)، والمسودات، والذاكرة. والبطاقات المالية للمالك وحده.
abstract final class AssistantCardShare {
  static bool canShare(AssistantCardData c, {required bool financialAllowed}) => switch (c) {
    AssistantCustomerCard() ||
    AssistantDraftCard() ||
    AssistantConfirmCard() ||
    AssistantMemoryCard() ||
    AssistantNoticeCard() => false,
    AssistantFactsCard(:final kind) when const {'sales', 'cash', 'debts'}.contains(kind) => financialAllowed,
    AssistantProductCard(:final details) when details.any((d) => d.$1 == 'سعر الشراء') => financialAllowed,
    _ => true,
  };

  static Future<bool> share(GlobalKey boundaryKey, {String name = 'naboo-card'}) async {
    final ro = boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderRepaintBoundary) return false;
    final image = await ro.toImage(pixelRatio: 3);
    final w = image.width / 3.0;
    final h = image.height / 3.0;
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (png == null) return false;
    final doc = pw.Document();
    final img = pw.MemoryImage(png.buffer.asUint8List());
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(w + 24, h + 24, marginAll: 12),
        build: (_) => pw.Image(img, width: w, height: h),
      ),
    );
    return Printing.sharePdf(bytes: await doc.save(), filename: '$name.pdf');
  }
}

/// بطاقة قابلة للمشاركة: إطار تصوير وزر صغير في زاويتها.
class AssistantShareableCard extends StatefulWidget {
  const AssistantShareableCard(this.data, {super.key, this.onOpen, this.financialAllowed = false});

  final AssistantCardData data;
  final VoidCallback? onOpen;
  final bool financialAllowed;

  @override
  State<AssistantShareableCard> createState() => _AssistantShareableCardState();
}

class _AssistantShareableCardState extends State<AssistantShareableCard> {
  final _key = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final ok = await AssistantCardShare.share(_key);
      if (!ok && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('ما گدرت أجهز صورة البطاقة.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('ما گدرت أفتح المشاركة.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = RepaintBoundary(
      key: _key,
      child: AssistantCard(widget.data, onOpen: widget.onOpen),
    );
    if (!AssistantCardShare.canShare(widget.data, financialAllowed: widget.financialAllowed)) return card;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        card,
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            onPressed: _busy ? null : () => unawaited(_share()),
            icon: Icon(Icons.ios_share_rounded, size: 16, color: cs.onSurfaceVariant),
            label: Text('شارك البطاقة', style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        ),
      ],
    );
  }
}
