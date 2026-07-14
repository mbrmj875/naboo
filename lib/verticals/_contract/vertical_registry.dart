import '../../services/business_setup_settings.dart';
import 'vertical_manifest.dart';

/// سجل manifests التخصصات — singleton يُحمَّل عند الإقلاع.
abstract final class VerticalRegistry {
  VerticalRegistry._();

  static final VerticalRegistry instance = _VerticalRegistryImpl();

  /// تسجيل manifest — يُستدعى مرة لكل vertical عند تهيئة التطبيق.
  void register(VerticalManifest manifest);

  /// manifest مسجّل لمعرّف نشاط — `null` إن لم يُسجَّل.
  VerticalManifest? manifestFor(String verticalId);

  /// النشاط التجاري الحالي — يُحدَّث من [BusinessFeaturesProvider].
  String get activeVerticalId;

  /// مزامنة النشاط من إعدادات المتجر.
  void syncActiveVertical(BusinessSetupSettingsData features);

  /// manifest النشاط الحالي — fallback إلى [BusinessVertical.generalRetail].
  VerticalManifest get activeManifest;
}

final class _VerticalRegistryImpl implements VerticalRegistry {
  final Map<String, VerticalManifest> _manifests = {};
  String _activeVerticalId = BusinessVertical.generalRetail;

  @override
  void register(VerticalManifest manifest) {
    final id = manifest.id.trim();
    if (id.isEmpty) {
      throw ArgumentError.value(manifest.id, 'manifest.id', 'must not be empty');
    }
    _manifests[id] = manifest;
  }

  @override
  VerticalManifest? manifestFor(String verticalId) {
    final id = verticalId.trim();
    if (id.isEmpty) return null;
    return _manifests[id];
  }

  @override
  String get activeVerticalId => _activeVerticalId;

  @override
  void syncActiveVertical(BusinessSetupSettingsData features) {
    final v = features.routingVertical.trim();
    _activeVerticalId = BusinessVertical.isKnown(v)
        ? v
        : BusinessVertical.generalRetail;
  }

  @override
  VerticalManifest get activeManifest {
    final direct = _manifests[_activeVerticalId];
    if (direct != null) return direct;

    final fallback = _manifests[BusinessVertical.generalRetail];
    if (fallback != null) return fallback;

    if (_manifests.length == 1) {
      return _manifests.values.first;
    }

    throw StateError(
      'VerticalRegistry: no manifest for "$_activeVerticalId" '
      'and no ${BusinessVertical.generalRetail} fallback registered',
    );
  }
}
