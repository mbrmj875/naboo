/// خريطة الشاشات: ما يعرفه المساعد عن كل شاشة (م3-2).
///
/// الخريطة بيانات ثابتة فقط. منها يقرأ النموذج أسماء الأزرار الحقيقية عبر
/// `ui_describe`، ومنها يرفض المنفّذ أي مسار أو مرساة غير موجودة، ومنها يعمل
/// «اشرح لي هذه الشاشة» بلا إنترنت.
library;

/// مجموعة الشاشة، تُستعمل في الاقتراحات والدورة والفيديوهات.
enum ScreenGroup { home, oil, wash, whatsapp, inventory, customers, money, reports, staff, settings }

/// عنصر في الشاشة يستطيع المساعد الإشارة إليه أو شرحه.
class ScreenElement {
  const ScreenElement(this.anchorId, this.label, this.does);

  /// مرساة في [OilGuideAnchors]. فارغة لعنصر يُشرح ولا يُؤشَّر عليه.
  final String? anchorId;
  final String label;
  final String does;

  Map<String, Object?> toJson() => {if (anchorId != null) 'anchor_id': anchorId, 'label': label, 'does': does};
}

class AppScreenSpec {
  const AppScreenSpec({
    required this.routeId,
    required this.title,
    required this.group,
    required this.purpose,
    required this.howToReach,
    this.parentRouteId,
    this.entryAnchor,
    this.direct = true,
    this.elements = const [],
    this.tasks = const [],
    this.isForm = false,
    this.saveAnchor,
    this.tourIds = const [],
    this.tips = const [],
  });

  final String routeId;
  final String title;
  final ScreenGroup group;

  /// جملة واحدة: لماذا توجد الشاشة.
  final String purpose;

  /// الطريق إليها كما يراه المستخدم: «القائمة ← المخزون ← المنتجات».
  final String howToReach;

  /// الشاشة التي تُفتح أولاً ليعود إليها الرجوع، أو التي يُضغط فيها [entryAnchor].
  final String? parentRouteId;

  /// زر في [parentRouteId] يفتح هذه الشاشة، للشاشات التي لا تُفتح مباشرة.
  final String? entryAnchor;

  /// تُفتح بمعرّفها مباشرة. `false` لشاشة تحتاج سجلاً (بطاقة، موظف) أو تُفتح من بند.
  final bool direct;

  final List<ScreenElement> elements;

  /// ما يُنجز فيها، بلغة المستخدم.
  final List<String> tasks;

  final bool isForm;
  final String? saveAnchor;

  /// جولات جاهزة تبدأ من هذه الشاشة.
  final List<String> tourIds;

  /// معلومات قصيرة ثابتة تُقال عند الشرح (منقولة من ملفات المعرفة القديمة).
  final List<String> tips;

  Iterable<String> get anchorIds sync* {
    if (entryAnchor != null) yield entryAnchor!;
    if (saveAnchor != null) yield saveAnchor!;
    for (final e in elements) {
      if (e.anchorId != null) yield e.anchorId!;
    }
  }

  /// ما يُرسل للنموذج من `ui_describe`.
  Map<String, Object?> toToolJson() => {
    'route_id': routeId,
    'title': title,
    'purpose': purpose,
    'how_to_reach': howToReach,
    if (!direct) 'opens_from': {'route_id': parentRouteId, if (entryAnchor != null) 'anchor_id': entryAnchor},
    'elements': [for (final e in elements) e.toJson()],
    if (tasks.isNotEmpty) 'tasks': tasks,
    if (saveAnchor != null) 'save_anchor': saveAnchor,
    if (tourIds.isNotEmpty) 'tours': tourIds,
    if (tips.isNotEmpty) 'tips': tips,
  };

  /// نص «اشرح لي هذه الشاشة» (م3-13): يُبنى على الجهاز من الوصف وحده.
  String explainText() {
    final b = StringBuffer('$title: $purpose');
    final named = elements.where((e) => e.does.isNotEmpty).take(6).toList();
    if (named.isNotEmpty) {
      b.write('\n\nأهم ما فيها:');
      for (final e in named) {
        b.write('\n• ${e.label}: ${e.does}');
      }
    }
    if (tasks.isNotEmpty) b.write('\n\nتقدر منها: ${tasks.join('، ')}.');
    if (tips.isNotEmpty) b.write('\n\n${tips.first}');
    return b.toString();
  }
}
