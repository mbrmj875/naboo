import 'package:flutter/foundation.dart';

/// مصدر الحقيقة لمعرّف المستأجر (`tenant_id`) المرتبط بالجلسة الحالية.
///
/// يُضبط بعد تسجيل دخول ناجح ويُمسح عند تسجيل الخروج. كل DAO أو RPC أو
/// استعلام Supabase يجب أن ينادي [requireTenantId] قبل أي قراءة/كتابة،
/// فيمنع IDOR وتسرّب البيانات بين المستأجرين على نفس الجهاز.
///
/// السياق هنا قائم على [String] ليتطابق مع UUID الذي يستخدمه Supabase
/// JWT/RLS. الـ tenant_id العددي (`int`) لجداول SQLite متعدّدة المستأجرين
/// يبقى مُداراً عبر [TenantContextService] في طبقة قاعدة البيانات المحلية.
class TenantContext extends ChangeNotifier {
  TenantContext._internal();

  /// النسخة العامة المستخدمة في كود التطبيق (singleton).
  static final TenantContext instance = TenantContext._internal();

  /// مُنشئ خاص بالاختبارات لإنشاء instance مستقلّة في كل اختبار حتى لا
  /// تتسرّب الحالة بين الاختبارات.
  @visibleForTesting
  static TenantContext newForTesting() => TenantContext._internal();

  String? _tenantId;

  /// قيمة `tenant_id` الحالية، أو `null` إن لم تُضبط بعد.
  String? get tenantId => _tenantId;

  /// `true` إذا كان [tenantId] مضبوطاً وغير فارغ.
  bool get hasTenant => (_tenantId ?? '').isNotEmpty;

  /// يفرض وجود `tenant_id` قبل أي عملية بيانات. يرمي [StateError] إذا لم
  /// تُستدعَ [set] بعد. هذه هي البوابة التي يجب على كل DAO المرور بها لمنع
  /// التشغيل بـ tenantId مفترض.
  String requireTenantId() {
    final id = _tenantId;
    if (id == null || id.isEmpty) {
      throw StateError(
        'TenantContext غير مضبوط. يجب تسجيل الدخول قبل استدعاء أي عملية بيانات.',
      );
    }
    return id;
  }

  /// يضبط `tenant_id` بعد تسجيل دخول ناجح. يقصّ المسافات حول القيمة، ويرمي
  /// [ArgumentError] إذا كانت فارغة فعلياً. لا يطلق إشعاراً للمستمعين إذا
  /// لم تتغيّر القيمة (تجنّباً لإعادة بناء الواجهات بلا داعٍ).
  void set(String tenantId) {
    final clean = tenantId.trim();
    if (clean.isEmpty) {
      throw ArgumentError.value(
        tenantId,
        'tenantId',
        'tenantId يجب ألّا يكون فارغاً',
      );
    }
    if (_tenantId == clean) return;
    _tenantId = clean;
    notifyListeners();
  }

  /// يمسح `tenant_id` عند تسجيل الخروج. لا يطلق إشعاراً إن كان فارغاً.
  void clear() {
    if (_tenantId == null) return;
    _tenantId = null;
    notifyListeners();
  }
}
