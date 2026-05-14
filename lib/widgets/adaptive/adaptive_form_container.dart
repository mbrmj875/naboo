import 'package:flutter/material.dart';
import '../../utils/screen_layout.dart';

/// يقيّد عرض المحتوى على الشاشات الواسعة (`tabletLG+`) لمنع امتداد حقول
/// النماذج عبر شاشات الديسكتوب الضخمة (لقابلية القراءة + مسح العين).
///
/// - `phoneXS` / `phoneSM` / `tabletSM`: المحتوى يملأ العرض كاملاً (لا قيود).
/// - `tabletLG` / `desktopSM` / `desktopLG`: المحتوى متمركز ضمن `maxWidth`
///   (افتراضي 720dp — مناسب للنماذج متوسطة الحجم).
///
/// راجع §9.3 Form Pattern في `docs/screen_migration_playbook.md`.
///
/// مثال:
/// ```dart
/// Scaffold(
///   appBar: AppBar(title: const Text('إضافة عميل')),
///   body: AdaptiveFormContainer(
///     child: Form(key: _formKey, child: ...),
///   ),
/// )
/// ```
class AdaptiveFormContainer extends StatelessWidget {
  const AdaptiveFormContainer({
    super.key,
    required this.child,
    this.maxWidth = 720,
  });

  /// المحتوى المراد تقييد عرضه على الشاشات الواسعة.
  final Widget child;

  /// أقصى عرض على الشاشات الواسعة (`tabletLG+`).
  /// - 720dp مناسب لنماذج إدخال قياسية (عمود واحد).
  /// - 960dp مناسب لنماذج فيها أعمدة جانبية أو محتوى مساعد.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    if (!context.screenLayout.isWideVariant) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
