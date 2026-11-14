/// نتيجة تشغيل [CloudSyncService.syncNowDetailed] — للمسارات الحرجة (استعادة
/// مساحة عمل بعد مسح SQLite).
enum CloudSyncPullStatus {
  notAttempted,
  noRemoteSnapshot,
  imported,
  skippedAlreadyCurrent,
  blockedSchema,
  blockedPayload,
  blockedChunks,
  failed,
}

/// ملخص دورة مزامنة واحدة.
class CloudSyncRunResult {
  const CloudSyncRunResult({
    this.pullStatus = CloudSyncPullStatus.notAttempted,
    this.pullAttempted = false,
    this.pushAttempted = false,
    this.pushSucceeded = false,
    this.errorMessage,
  });

  final CloudSyncPullStatus pullStatus;
  final bool pullAttempted;
  final bool pushAttempted;
  final bool pushSucceeded;
  final String? errorMessage;

  bool get pulledCloudData =>
      pullStatus == CloudSyncPullStatus.imported ||
      pullStatus == CloudSyncPullStatus.skippedAlreadyCurrent;

  /// بعد مسح القاعدة محلياً — يتحقق من وجود لقطة سحابية فعلاً.
  bool isMandatoryRestoreOk({required bool remoteSnapshotExists}) {
    if (!remoteSnapshotExists) {
      // حساب/جهاز جديد: لا لقطة على السحابة — مسموح المتابعة حتى لو فشل السحب.
      return true;
    }
    return pulledCloudData;
  }

  String? get userMessageAr {
    if ((errorMessage ?? '').trim().isNotEmpty) return errorMessage;
    return switch (pullStatus) {
      CloudSyncPullStatus.blockedSchema =>
        'نسخة لقطة السحابة لا تطابق هذا الإصدار من التطبيق. حدّث التطبيق ثم أعد المحاولة.',
      CloudSyncPullStatus.blockedPayload ||
      CloudSyncPullStatus.blockedChunks =>
        'تعذّر قراءة لقطة السحابة. تحقق من الاتصال ثم أعد المحاولة.',
      CloudSyncPullStatus.failed =>
        'تعذّر استرجاع بيانات النشاط من السحابة. تحقق من الإنترنت ثم أعد المحاولة.',
      CloudSyncPullStatus.notAttempted =>
        'لم تُنفَّذ عملية السحب من السحابة بعد مسح البيانات المحلية.',
      _ => null,
    };
  }
}
