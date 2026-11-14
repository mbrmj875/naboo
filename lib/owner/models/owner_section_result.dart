import 'owner_section_ttl.dart';

/// حالة قسم واحد في لوحة صاحب العمل — فشل جزئي بدون Riverpod.
enum OwnerSectionStatus { idle, loading, success, error, stale }

class OwnerSectionResult<T> {
  const OwnerSectionResult({
    required this.status,
    this.data,
    this.errorMessage,
    this.fetchedAt,
    this.isOffline = false,
  });

  const OwnerSectionResult.idle()
      : status = OwnerSectionStatus.idle,
        data = null,
        errorMessage = null,
        fetchedAt = null,
        isOffline = false;

  const OwnerSectionResult.loading()
      : status = OwnerSectionStatus.loading,
        data = null,
        errorMessage = null,
        fetchedAt = null,
        isOffline = false;

  factory OwnerSectionResult.success(
    T data,
    DateTime fetchedAt, {
    bool isOffline = false,
  }) {
    return OwnerSectionResult(
      status: OwnerSectionStatus.success,
      data: data,
      fetchedAt: fetchedAt,
      isOffline: isOffline,
    );
  }

  factory OwnerSectionResult.error(
    String message, {
    T? staleData,
    DateTime? fetchedAt,
    bool isOffline = false,
  }) {
    return OwnerSectionResult(
      status: OwnerSectionStatus.error,
      data: staleData,
      errorMessage: message,
      fetchedAt: fetchedAt,
      isOffline: isOffline,
    );
  }

  factory OwnerSectionResult.stale(
    T data,
    DateTime fetchedAt, {
    bool isOffline = false,
  }) {
    return OwnerSectionResult(
      status: OwnerSectionStatus.stale,
      data: data,
      fetchedAt: fetchedAt,
      isOffline: isOffline,
    );
  }

  final OwnerSectionStatus status;
  final T? data;
  final String? errorMessage;
  final DateTime? fetchedAt;

  /// true عند عرض cache أثناء انقطاع الشبكة (v1.1.2 §6).
  final bool isOffline;

  bool get isLoading => status == OwnerSectionStatus.loading;
  bool get isSuccess => status == OwnerSectionStatus.success;
  bool get isError => status == OwnerSectionStatus.error;

  /// stale صريح (offline/cache) أو status == stale.
  bool get isStale =>
      status == OwnerSectionStatus.stale || isOffline;

  bool get hasData => data != null;

  /// true إذا تجاوزت البيانات 3× TTL — يستدعى Skeleton (v1.1.2 §5).
  bool isAgeStale(String sectionId) =>
      OwnerSectionTtl.isVeryStale(sectionId, fetchedAt);

  OwnerSectionResult<T> copyWith({
    OwnerSectionStatus? status,
    T? data,
    String? errorMessage,
    DateTime? fetchedAt,
    bool? isOffline,
  }) {
    return OwnerSectionResult(
      status: status ?? this.status,
      data: data ?? this.data,
      errorMessage: errorMessage ?? this.errorMessage,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}

enum CommandCenterScreenStatus { idle, loading, ready, partial, offlineStale }

/// رسالة Empty عند offline بدون cache — v1.1.2 §6 ②.
const ownerKpiOfflineEmptyMessage =
    'لا يمكن جلب البيانات حالياً — تحقق من الاتصال';
