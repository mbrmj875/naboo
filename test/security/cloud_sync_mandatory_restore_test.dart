import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/services/cloud_sync_run_result.dart';

void main() {
  group('CloudSyncRunResult.isMandatoryRestoreOk', () {
    test('no remote snapshot — new account may proceed even if pull failed', () {
      const failed = CloudSyncRunResult(
        pullStatus: CloudSyncPullStatus.failed,
        pullAttempted: true,
      );
      expect(
        failed.isMandatoryRestoreOk(remoteSnapshotExists: false),
        isTrue,
      );
    });

    test('remote snapshot exists — must import or skip as current', () {
      const failed = CloudSyncRunResult(
        pullStatus: CloudSyncPullStatus.failed,
        pullAttempted: true,
      );
      expect(
        failed.isMandatoryRestoreOk(remoteSnapshotExists: true),
        isFalse,
      );

      const imported = CloudSyncRunResult(
        pullStatus: CloudSyncPullStatus.imported,
        pullAttempted: true,
      );
      expect(
        imported.isMandatoryRestoreOk(remoteSnapshotExists: true),
        isTrue,
      );
    });
  });
}
