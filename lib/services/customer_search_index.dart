import 'dart:async';
import 'dart:isolate';

import '../models/customer_record.dart';
import '../utils/app_logger.dart';
import '../utils/arabic_search_match.dart';
import 'database_helper.dart';

/// صف عميل مهيّأ للبحث: النص مطبَّع والكلمات مقسّمة مسبقاً.
class CustomerSearchEntry {
  const CustomerSearchEntry({
    required this.id,
    required this.name,
    required this.phone,
    required this.normalizedName,
    required this.nameTokens,
    required this.phoneKeys,
  });

  final int id;
  final String name;
  final String? phone;
  final String normalizedName;
  final List<String> nameTokens;

  /// مفاتيح كل أرقام العميل (الأساسي والإضافية) بصيغة موحّدة.
  final List<String> phoneKeys;
}

/// نتيجة بحث مرتّبة.
class CustomerSearchHit {
  const CustomerSearchHit(this.entry, this.score);
  final CustomerSearchEntry entry;
  final int score;
}

/// بحث فوري في العملاء من الذاكرة.
///
/// الاستعلام السابق كان يمرّ على جدول الفواتير كاملاً (مجموع المشتريات) لكل
/// ضغطة مفتاح رغم أن الاقتراحات لا تعرض المشتريات، فكان البحث يتأخّر كلما كبر
/// المحل. هنا تُقرأ أسماء العملاء مرة واحدة وتُطابَق داخل الإطار نفسه.
class CustomerSearchIndex {
  CustomerSearchIndex._();

  static final CustomerSearchIndex instance = CustomerSearchIndex._();

  List<CustomerSearchEntry> _entries = const [];

  /// بادئة حرف أو حرفين → فهارس الصفوف. البحث يمسّ هذه السلة فقط.
  Map<String, List<int>> _prefix = const {};
  String _signature = '';
  Future<void>? _building;

  bool get isReady => _signature.isNotEmpty;
  int get length => _entries.length;

  /// تُستدعى بعد إضافة أو تعديل عميل لإجبار إعادة البناء عند البحث التالي.
  void invalidate() {
    _signature = '';
  }

  /// للاختبارات: تعبئة الفهرس مباشرة دون قاعدة بيانات.
  void seedForTest(List<CustomerSearchEntry> entries) {
    _install(entries);
    _signature = 'test';
  }

  /// يبني الفهرس أو يعيد بناءه إن تغيّر جدول العملاء. تُستدعى عند فتح الحقل
  /// لا عند كل حرف.
  Future<void> ensureFresh() {
    final pending = _building;
    if (pending != null) return pending;
    final job = _refresh();
    _building = job;
    return job.whenComplete(() {
      if (identical(_building, job)) _building = null;
    });
  }

  Future<void> _refresh() async {
    try {
      final db = await DatabaseHelper().database;
      // توقيع بسيط مستقر — بدون أعمدة قد تختلف بين النسخ.
      final sigRows = await db.rawQuery(
        'SELECT COUNT(*) AS c, IFNULL(MAX(id), 0) AS mx FROM customers',
      );
      final sig = sigRows.isEmpty
          ? '0|0'
          : '${sigRows.first['c']}|${sigRows.first['mx']}';
      if (sig == _signature && _entries.isNotEmpty) return;

      final rows = await db.query(
        'customers',
        columns: ['id', 'name', 'phone'],
      );
      // الأرقام الإضافية تحسين لا شرط؛ غياب الجدول في نسخة قديمة لا يعطّل البحث.
      var extra = const <Map<String, Object?>>[];
      try {
        extra = await db.query(
          'customer_extra_phones',
          columns: ['customerId', 'phone'],
        );
      } catch (_) {}

      _install(await _buildEntriesMaybeOffThread(rows, extra));
      _signature = sig;
    } catch (e, st) {
      AppLogger.error('CustomerSearchIndex', 'فشل بناء فهرس البحث', e, st);
    }
  }

  static Future<List<CustomerSearchEntry>> _buildEntriesMaybeOffThread(
    List<Map<String, Object?>> rows,
    List<Map<String, Object?>> extraPhones,
  ) async {
    final payload = CustomerSearchIndexInput(rows, extraPhones);
    // بدء العزلة أغلى من بناء بضعة آلاف اسم على الخيط نفسه،
    // وهو ما كان يجعل أول بحث بطيئاً بشكل متقطّع.
    if (rows.length > 6000) {
      return Isolate.run(() => buildCustomerSearchEntries(payload));
    }
    return buildCustomerSearchEntries(payload);
  }

  void _install(List<CustomerSearchEntry> entries) {
    _entries = List.unmodifiable(entries);
    _prefix = _prefixesFor(entries);
  }

  static Map<String, List<int>> _prefixesFor(List<CustomerSearchEntry> entries) {
    final map = <String, List<int>>{};
    void add(String key, int index) {
      if (key.isEmpty) return;
      (map[key] ??= <int>[]).add(index);
    }

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      void addText(String text) {
        if (text.isEmpty) return;
        add(text.substring(0, 1), i);
        if (text.length >= 2) add(text.substring(0, 2), i);
      }

      addText(entry.normalizedName);
      for (final token in entry.nameTokens) {
        addText(token);
      }
      for (final phone in entry.phoneKeys) {
        if (phone.length < 2) continue;
        add('☎${phone.substring(0, 2)}', i);
      }
    }
    return map;
  }

  List<CustomerSearchEntry> _candidates({
    required List<String> queryTokens,
    required String queryPhoneKey,
  }) {
    if (_prefix.isEmpty) return _entries;
    final indexes = <int>{};
    if (queryTokens.isNotEmpty) {
      final token = queryTokens.first;
      final key = token.length >= 2 ? token.substring(0, 2) : token.substring(0, 1);
      final bucket = _prefix[key];
      if (bucket != null) indexes.addAll(bucket);
    }
    if (queryPhoneKey.length >= 2) {
      final bucket = _prefix['☎${queryPhoneKey.substring(0, 2)}'];
      if (bucket != null) indexes.addAll(bucket);
    }
    if (indexes.isEmpty) return const [];
    return [for (final i in indexes) _entries[i]];
  }

  /// بحث متزامن — لا انتظار ولا قاعدة بيانات.
  List<CustomerSearchHit> search(String rawQuery, {int limit = 8}) {
    final normalizedQuery = normalizeArabicSearchText(rawQuery);
    final queryTokens = splitSearchTokens(normalizedQuery);
    final queryDigits = digitsOnly(rawQuery);
    final queryPhoneKey = queryDigits.length >= 2 ? phoneMatchKey(rawQuery) : '';
    if (queryTokens.isEmpty && queryPhoneKey.isEmpty) return const [];

    final hits = <CustomerSearchHit>[];
    for (final entry in _candidates(
      queryTokens: queryTokens,
      queryPhoneKey: queryPhoneKey,
    )) {
      var score = 0;
      if (queryTokens.isNotEmpty) {
        score = scoreNameMatchTokens(
          normalizedName: entry.normalizedName,
          nameTokens: entry.nameTokens,
          normalizedQuery: normalizedQuery,
          queryTokens: queryTokens,
        );
      }
      if (queryPhoneKey.isNotEmpty) {
        for (final key in entry.phoneKeys) {
          final phoneScore = scorePhoneMatch(
            phoneKey: key,
            queryDigits: queryPhoneKey,
          );
          if (phoneScore > score) score = phoneScore;
        }
      }
      if (score > 0) hits.add(CustomerSearchHit(entry, score));
    }

    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.entry.name.compareTo(b.entry.name);
    });
    if (hits.length <= limit) return hits;
    return hits.sublist(0, limit);
  }

  List<CustomerRecord> searchRecords(String rawQuery, {int limit = 8}) {
    return search(rawQuery, limit: limit)
        .map(
          (h) => CustomerRecord(
            id: h.entry.id,
            name: h.entry.name,
            phone: h.entry.phone,
            balance: 0,
            loyaltyPoints: 0,
          ),
        )
        .toList(growable: false);
  }
}

/// مدخلات بناء الفهرس — نوع عام لأنه يُرسل إلى عزلة أخرى.
class CustomerSearchIndexInput {
  const CustomerSearchIndexInput(this.rows, this.extraPhones);
  final List<Map<String, Object?>> rows;
  final List<Map<String, Object?>> extraPhones;
}

/// دالة نقية (تعمل داخل عزلة أيضاً) لبناء صفوف الفهرس.
List<CustomerSearchEntry> buildCustomerSearchEntries(
  CustomerSearchIndexInput payload,
) {
  final extraByCustomer = <int, List<String>>{};
  for (final row in payload.extraPhones) {
    final cid = (row['customerId'] as num?)?.toInt();
    if (cid == null) continue;
    final key = phoneMatchKey((row['phone'] ?? '').toString());
    if (key.isEmpty) continue;
    (extraByCustomer[cid] ??= <String>[]).add(key);
  }

  final out = <CustomerSearchEntry>[];
  for (final row in payload.rows) {
    final id = (row['id'] as num?)?.toInt();
    if (id == null) continue;
    final name = (row['name'] ?? '').toString().trim();
    final phoneRaw = (row['phone'] ?? '').toString().trim();
    final normalized = normalizeArabicSearchText(name);
    final keys = <String>[];
    final mainKey = phoneMatchKey(phoneRaw);
    if (mainKey.isNotEmpty) keys.add(mainKey);
    final extras = extraByCustomer[id];
    if (extras != null) keys.addAll(extras);

    out.add(
      CustomerSearchEntry(
        id: id,
        name: name,
        phone: phoneRaw.isEmpty ? null : phoneRaw,
        normalizedName: normalized,
        nameTokens: splitSearchTokens(normalized),
        phoneKeys: keys,
      ),
    );
  }
  return out;
}
