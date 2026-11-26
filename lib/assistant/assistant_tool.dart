import 'dart:typed_data';

import 'assistant_access.dart';
import 'assistant_tool_result.dart';

/// سياق تنفيذ أداة: من يسأل وماذا يملك (خطة المساعد 4.2).
///
/// منفصل عن Provider حتى تُختبر الأدوات والحارس بلا واجهة.
class AssistantToolContext {
  const AssistantToolContext({
    required this.isOwner,
    required this.can,
    required this.level,
    this.tenantId,
    this.userId,
    this.userName,
    this.now,
    this.turnId,
    this.image,
  });

  /// نفس السياق لسؤال محدد: معرّفه وصورته إن وُجدت (لأدوات التنفيذ).
  AssistantToolContext forTurn(String turnId, {Uint8List? image}) => AssistantToolContext(
    isOwner: isOwner,
    can: can,
    level: level,
    tenantId: tenantId,
    userId: userId,
    userName: userName,
    now: now,
    turnId: turnId,
    image: image,
  );

  /// السؤال الجاري، لتسجيل ما حُفظ عبر المساعد عليه (م4-5).
  final String? turnId;

  /// صورة السؤال (فاتورة مورّد) لتظهر بجانب جدول المراجعة.
  final Uint8List? image;

  final bool isOwner;
  final bool Function(String key) can;
  final AssistantLevel level;
  final String? tenantId;
  final String? userId;

  /// اسم المستخدم كما يُكتب في البطاقات (الفني)، لأداة «أدائي» فقط.
  final String? userName;
  final DateTime? now;

  DateTime get clock => now ?? DateTime.now();

  /// المالك يملك كل شيء. غيره يحتاج المفتاح نفسه.
  bool has(String key) => isOwner || can(key);
}

/// نوع معطى في مخطط الأداة. التحقق مقصود بسيط: النوع والإلزام فقط.
enum AssistantArgType { string, integer, number, boolean, list, map }

class AssistantArgSpec {
  const AssistantArgSpec(this.type, {this.required = false, this.allowed});

  final AssistantArgType type;
  final bool required;

  /// قيم مسموحة لنص (enum).
  final Set<String>? allowed;
}

/// أداة يستدعيها النموذج وتُنفَّذ على الجهاز.
abstract class AssistantTool {
  const AssistantTool();

  /// الاسم كما في `assistant-chat/tools.ts`.
  String get name;

  /// يكفي أن يملك المستخدم واحداً منها. فارغة = لا شرط غير مستوى المساعد.
  List<String> get requiredPermissions;

  /// أدوات الإرشاد مسموحة لمستوى «إرشاد فقط». غيرها يحتاج «كامل».
  bool get guideLevel => false;

  /// حقول تُحذف من الصفوف لمن لا يملك `owner.kpi.financial` (سعر الشراء، الربح…).
  Set<String> get financialFields => const {};

  Map<String, AssistantArgSpec> get args => const {};

  /// القراءة فقط. لا أداة قراءة تكتب.
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx);
}
