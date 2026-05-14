import 'package:flutter/widgets.dart';

import '../services/screen_security_service.dart';

/// غلاف خفيف يفعّل `FLAG_SECURE` على Android طوال عمر الشاشة، ويلغيه عند
/// الـ dispose.
///
/// طريقة الاستعمال:
///
/// ```dart
/// @override
/// Widget build(BuildContext context) {
///   return SecureScreen(
///     child: Scaffold(
///       appBar: AppBar(title: Text('شاشة حسّاسة')),
///       body: ...,
///     ),
///   );
/// }
/// ```
///
/// ✅ يعمل بنفس الفعالية مع `StatelessWidget` و `StatefulWidget`، فلا حاجة
/// لتحويل الشاشات الموجودة.
///
/// ⚠️ على iOS و macOS لا يفعل شيئاً (Apple لا تدعم `FLAG_SECURE`؛ الحماية
/// المكافئة تتطلّب تخصيص `SceneDelegate`/snapshot — في sprint منفصل).
class SecureScreen extends StatefulWidget {
  const SecureScreen({super.key, required this.child});

  final Widget child;

  @override
  State<SecureScreen> createState() => _SecureScreenState();
}

class _SecureScreenState extends State<SecureScreen> {
  @override
  void initState() {
    super.initState();
    // fire-and-forget: لا نحجز البناء على عملية المنصّة. التوقيت كافٍ لأن
    // النظام يطبّق العَلم قبل أوّل لقطة قابلة للتسجيل.
    ScreenSecurityService.instance.enable();
  }

  @override
  void dispose() {
    // مهمّ: لا نضع `await` لأن `dispose()` متزامن. التنفيذ الفعلي يحدث
    // في الميكروTask التالي.
    ScreenSecurityService.instance.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
