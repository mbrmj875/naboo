import 'dart:typed_data';

import 'assistant_name_match.dart';
import 'assistant_prefill.dart';

/// ما ينتج عن فتح نموذج معبّأ: حُفظ أم أُغلق بلا حفظ.
class AssistantFormOutcome {
  const AssistantFormOutcome({required this.saved, this.entityId});
  const AssistantFormOutcome.closed() : saved = false, entityId = null;

  final bool saved;
  final String? entityId;
}

/// سطر في قائمة مراجعة الفاتورة أو الجرد (م4-9، م4-14).
class AssistantReviewLine {
  AssistantReviewLine({
    required this.readName,
    required this.qty,
    this.unitPriceFils,
    required this.match,
    this.currentQty,
  }) : productId = match.grade == AssistantMatchGrade.matched
           ? match.productId
           : null;

  /// الاسم كما قُرئ من الصورة أو الصوت، لا يتغير.
  final String readName;
  double qty;
  int? unitPriceFils;
  AssistantMatch match;

  /// المنتج المعتمد. null = غير محسوم بعد.
  int? productId;
  String? productName;

  /// الكمية الحالية بالمخزون، للجرد (الفرق = المعدود − الحالي).
  double? currentQty;

  /// حذفه المستخدم من القائمة.
  bool removed = false;

  bool get resolved => removed || (productId != null && qty > 0);
}

/// مسودة جدول مراجعة: فاتورة مورّد (intake) أو جرد (count).
class AssistantReviewDraft {
  AssistantReviewDraft({
    required this.mode,
    required this.lines,
    this.supplier,
    this.image,
    this.turnId,
  });

  /// intake | count
  final String mode;
  final List<AssistantReviewLine> lines;
  final String? supplier;

  /// صورة الفاتورة كما أرسلها المستخدم، ليقارن الأرقام بعينه.
  final Uint8List? image;
  final String? turnId;

  /// لا سند وفيه صف غير محسوم (4.5).
  bool get canCommit =>
      lines.any((l) => !l.removed) && lines.every((l) => l.resolved);
}

/// حركة مخزون واحدة: موجبة إدخال، سالبة صرف.
typedef AssistantStockMove = ({
  int productId,
  double delta,
  double unitPriceIqd,
});

/// كل ما تحتاجه أدوات التنفيذ من التطبيق. منفصل حتى تُختبر الأدوات
/// والبطاقات بلا واجهة ولا قاعدة.
///
/// القاعدة (4.5): لا دالة هنا تُستدعى من الأداة مباشرة. الأداة تسجّل اقتراحاً،
/// والتنفيذ يبدأ من زر البطاقة بضغطة المستخدم، عبر دوال التطبيق الموجودة.
abstract class AssistantExecPort {
  /// يفتح النموذج الحقيقي معبّأً وينتظر إغلاقه.
  Future<AssistantFormOutcome> openForm(AssistantPrefill prefill);

  /// تغيير سعر البيع بدالة التعديل الموجودة. null نجاح، وإلا الرسالة.
  Future<String?> applyPriceChange({
    required int productId,
    required int newSellFils,
  });

  /// سند واحد لكل اتجاه: الموجب إذن إضافة، والسالب إذن صرف.
  Future<String?> applyStockMoves({
    required List<AssistantStockMove> moves,
    required String reason,
    required String sourceType,
    String? supplier,
  });

  /// يفتح جدول المراجعة، والجدول نفسه يستدعي [applyStockMoves] عند التأكيد.
  Future<bool> openReview(AssistantReviewDraft draft);

  /// يفتح معاينة الطباعة الموجودة. الطباعة بضغطة المستخدم.
  Future<String?> openPrintPreview({required String kind, String? ref});

  /// يحفظ التذكير محلياً ويجدول إشعاره.
  Future<String?> setReminder({required String text, required DateTime when});

  /// ع4: إيقاف منتج (إخفاؤه من البيع والقوائم) بدالة التطبيق نفسها. لا مسح.
  Future<String?> deactivateProduct(int productId);

  /// المخازن الفعّالة بالترتيب، الأول هو الرئيسي.
  Future<List<({int id, String name})>> listWarehouses();

  /// سند تحويل واحد بين مخزنين.
  Future<String?> transferStock({
    required int productId,
    required double qty,
    required int fromWarehouseId,
    required int toWarehouseId,
    required double unitPriceIqd,
    String? note,
  });

  /// تسديد دين زبون بنفس منطق شاشة الديون (الأقدم أولاً، سند قبض، قيد صندوق)،
  /// ثم يعرض الوصل. يرفض إن كانت الوردية المفتوحة باسم غير المستخدم.
  Future<AssistantDebtPaymentOutcome> recordDebtPayment({
    required int customerId,
    required String customerName,
    required int amountFils,
    required String userName,
    String? note,
  });
}

/// نتيجة تسديد الدين: [error] رسالة للمستخدم، أو المبالغ بعد التسديد.
class AssistantDebtPaymentOutcome {
  const AssistantDebtPaymentOutcome({
    this.error,
    this.appliedFils = 0,
    this.debtAfterFils = 0,
  });
  const AssistantDebtPaymentOutcome.failed(String this.error)
    : appliedFils = 0,
      debtAfterFils = 0;

  final String? error;
  final int appliedFils;
  final int debtAfterFils;
}
