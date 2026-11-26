/// أشكال العرض لصفحة المساعد (م2-3، م2-4).
///
/// الصفحة لا ترسم من نص النموذج: البطاقات تُبنى من نتائج الأدوات المحفوظة في
/// الهاتف، والمبالغ تصل هنا منسّقة جاهزة. هذه الأشكال بلا منطق حتى تُختبر
/// الواجهة وتُصوَّر بلا شبكة.
library;

import 'dart:typed_data';
import 'assistant_activity_icons.dart';

enum AssistantMarkState { idle, listening, thinking, speaking }

/// صف في بطاقة المخزون.
class AssistantStockRow {
  const AssistantStockRow({required this.name, required this.qty, this.unit = '', this.price, this.low = false});

  final String name;
  final num qty;
  final String unit;

  /// منسّق مسبقاً بدالة الشاشات، أو null لمن لا يرى الأسعار.
  final String? price;
  final bool low;

  bool get out => qty <= 0;
}

/// حقل في بطاقة تجهيز. [missing] يعني أن المستخدم يكمله في الشاشة.
class AssistantDraftField {
  const AssistantDraftField(this.label, this.value, {this.missing = false});
  final String label;
  final String value;
  final bool missing;
}

class AssistantSource {
  const AssistantSource(this.title, this.host);
  final String title;
  final String host;
}

enum AssistantConfidence { verified, singleSource }

sealed class AssistantCardData {
  const AssistantCardData();

  /// الشاشة التي يفتحها زر البطاقة (معرّف الخريطة)، أو null.
  String? get routeId => null;
}

/// صف عام في بطاقة قائمة: عنوان، وصف، وقيمة في الطرف.
class AssistantListRow {
  const AssistantListRow(this.title, {this.subtitle, this.trailing, this.flag});
  final String title;
  final String? subtitle;
  final String? trailing;

  /// شارة اختيارية: pending | out | low | ok
  final String? flag;
}

/// بطاقة حقائق وقوائم: المبيعات، الصندوق، الديون، الفنيون، البطاقات، سجل
/// السيارة. [kind] يحدد الأيقونة: sales | cash | debts | staff | oil_card |
/// car_history | generic.
class AssistantFactsCard extends AssistantCardData {
  const AssistantFactsCard({
    required this.kind,
    required this.title,
    this.facts = const [],
    this.rows = const [],
    this.total,
    this.openLabel,
    this.route,
  });
  final String kind;
  final String title;
  final List<(String, String)> facts;
  final List<AssistantListRow> rows;
  final int? total;
  final String? openLabel;
  final String? route;

  @override
  String? get routeId => route;
}

class AssistantStockCard extends AssistantCardData {
  const AssistantStockCard({required this.title, required this.rows, this.total, this.openLabel = 'افتح المخزون'});
  final String title;
  final List<AssistantStockRow> rows;
  final int? total;
  final String openLabel;

  @override
  String? get routeId => 'app_inventory';
}

class AssistantCarSpecCard extends AssistantCardData {
  const AssistantCarSpecCard({
    required this.title,
    required this.subtitle,
    required this.specs,
    required this.confidence,
    this.available = const [],
    this.sources = const [],
  });
  final String title;
  final String subtitle;
  final List<(String, String)> specs;
  final AssistantConfidence confidence;
  final List<AssistantStockRow> available;
  final List<AssistantSource> sources;

  @override
  String? get routeId => available.isEmpty ? null : 'app_inventory';
}

class AssistantDraftCard extends AssistantCardData {
  const AssistantDraftCard({
    required this.title,
    required this.fields,
    this.openLabel = 'افتح وراجع',
    this.route,
    this.actionId,
    this.warnings = const [],
    this.choices = const [],
    this.choicesLabel,
  });
  final String title;
  final List<AssistantDraftField> fields;
  final String openLabel;
  final String? route;

  /// الاقتراح الحي في `AssistantActions`. موجود = الزر يفتح النموذج المعبّأ.
  final String? actionId;

  /// تنبيه قبل الفتح، مثل نقص الزيت المطلوب (م4-12).
  final List<String> warnings;

  /// بدائل يختار منها المستخدم قبل الفتح (زيت بنفس اللزوجة).
  final List<String> choices;
  final String? choicesLabel;

  @override
  String? get routeId => actionId == null ? route : null;
}

/// بطاقة «قبل ← بعد» بزرّي تأكيد وإلغاء (م4-4). لا تغيير قبل الضغط.
class AssistantConfirmCard extends AssistantCardData {
  const AssistantConfirmCard({
    required this.title,
    required this.actionId,
    this.changes = const [],
    this.facts = const [],
    this.warnings = const [],
    this.confirmLabel = 'تأكيد',
    this.doneText = 'تم.',
  });

  final String title;
  final String actionId;

  /// (الحقل، قبل، بعد).
  final List<(String, String, String)> changes;
  final List<(String, String)> facts;
  final List<String> warnings;
  final String confirmLabel;
  final String doneText;
}

class AssistantProductCard extends AssistantCardData {
  const AssistantProductCard({required this.name, required this.details, this.openLabel = 'افتح المنتج'});
  final String name;
  final List<(String, String)> details;
  final String openLabel;

  @override
  String? get routeId => 'app_inventory';
}

/// بطاقة زبون (م2-18). الهاتف لا يأتي في النتيجة أبداً؛ تجلبه البطاقة من
/// الجهاز عند العرض لمن يملك صلاحية الزبائن، فلا يصل النموذج.
class AssistantCustomerCard extends AssistantCardData {
  const AssistantCustomerCard({required this.customerId, required this.name, this.facts = const []});
  final int customerId;
  final String name;
  final List<(String, String)> facts;

  @override
  String? get routeId => 'app_customers';
}

/// شريحة «حفظت: …» بعد memory_save، مع تراجع فوري (4.11).
class AssistantMemoryCard extends AssistantCardData {
  const AssistantMemoryCard({required this.id, required this.text});
  final int id;
  final String text;
}

/// سطر قصير بلا جدول: «وصلت مشكلتك لفريق نابو».
class AssistantNoticeCard extends AssistantCardData {
  const AssistantNoticeCard({required this.kind, required this.text});

  /// support | memory_full
  final String kind;
  final String text;
}

/// رسالة كما تعرضها الصفحة.
class AssistantViewMessage {
  const AssistantViewMessage({
    required this.fromUser,
    this.text = '',
    this.imageLabel,
    this.imageBytes,
    this.cards = const [],
    this.followups = const [],
    this.choices = const [],
    this.source,
    this.sourceDetails = const [],
    this.sourceRoute,
    this.status,
    this.actions = true,
    this.id,
    this.activity,
    this.animateText = false,
    this.complete = true,
  });

  final bool fromUser;
  final String text;

  /// صورة مرفقة بالسؤال (يُعرض وصفها المصغّر في الإطارات).
  final String? imageLabel;

  /// الصورة نفسها في الجلسة الحية (JPEG مضغوط).
  final Uint8List? imageBytes;
  final List<AssistantCardData> cards;
  final List<String> followups;

  /// أزرار اختيار للسؤال الغامض (ق78)، الضغط يرسل الاختيار كسؤال.
  final List<String> choices;

  /// سطر «من أين هذا؟» يكتبه الهاتف لا النموذج (ق68).
  final String? source;

  /// تفاصيل السطر عند فتحه، وشاشة «افتح التقرير نفسه» إن وُجدت.
  final List<String> sourceDetails;
  final String? sourceRoute;

  /// سطر الحالة الحي أثناء العمل: «أفحص المخزون…».
  final String? status;
  final bool actions;

  /// معرّف الرسالة، لحفظ ما ظهر من الكتابة التدريجية.
  final String? id;

  /// الأيقونة المتحركة مع سطر الحالة (ط3).
  final AssistantActivity? activity;

  /// يُكتب الجواب تدريجياً (ط5). false للأجوبة القديمة والمحلية.
  final bool animateText;

  /// وصل الجواب كله، فتظهر البطاقات بعد انتهاء الكتابة.
  final bool complete;
}

class AssistantThreadItem {
  const AssistantThreadItem(this.title, this.preview, this.when, {this.id = ''});
  final String id;
  final String title;
  final String preview;
  final String when;
}

class AssistantThreadGroup {
  const AssistantThreadGroup(this.label, this.items);
  final String label;
  final List<AssistantThreadItem> items;
}

/// يعزل كل مقطع لاتيني أو رقمي داخل نص عربي حتى لا ينقلب ترتيبه
/// («90915-YZZE1» لا «YZZE1-90915»، و«7–10» لا «10–7»). يُطبَّق على كل نص
/// يُعرض في الصفحة، من النموذج أو من الأدوات.
String isolateLtr(String s) {
  if (s.isEmpty) return s;
  return s.replaceAllMapped(_ltrRun, (m) => '\u2066${m.group(0)}\u2069');
}

final RegExp _ltrRun = RegExp(r'[A-Za-z0-9](?:[A-Za-z0-9\-–./:+,]|\s(?=[A-Za-z0-9/\-–]))*');
