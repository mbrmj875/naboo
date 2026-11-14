import 'package:naboo/services/app_remote_config_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppRemoteConfigService.compareVersions', () {
    test('equal versions', () {
      expect(AppRemoteConfigService.compareVersions('2.2.27', '2.2.27'), 0);
    });

    test('installed behind latest', () {
      expect(AppRemoteConfigService.compareVersions('2.2.26', '2.2.27'), lessThan(0));
    });

    test('installed ahead of latest', () {
      expect(AppRemoteConfigService.compareVersions('2.2.28', '2.2.27'), greaterThan(0));
    });

    test('strips build number suffix', () {
      expect(
        AppRemoteConfigService.compareVersions('2.2.27+250', '2.2.27'),
        0,
      );
    });
  });

  group('AppRemoteConfigService.isUpdateAvailable', () {
    test('true when installed < latest', () {
      expect(
        AppRemoteConfigService.isUpdateAvailable(
          installedVersion: '2.2.26',
          latestVersion: '2.2.27',
        ),
        isTrue,
      );
    });

    test('false when versions match', () {
      expect(
        AppRemoteConfigService.isUpdateAvailable(
          installedVersion: '2.2.27',
          latestVersion: '2.2.27',
        ),
        isFalse,
      );
    });

    test('false when installed matches latest with build suffix', () {
      expect(
        AppRemoteConfigService.isUpdateAvailable(
          installedVersion: '2.2.35+258',
          latestVersion: '2.2.35',
        ),
        isFalse,
      );
    });

    test('false when installed is newer than server', () {
      expect(
        AppRemoteConfigService.isUpdateAvailable(
          installedVersion: '2.2.36',
          latestVersion: '2.2.35',
        ),
        isFalse,
      );
    });

    test('false when server fallback 0.0.0', () {
      expect(
        AppRemoteConfigService.isUpdateAvailable(
          installedVersion: '2.2.27',
          latestVersion: '0.0.0',
        ),
        isFalse,
      );
    });
  });

  group('AppRemoteConfigData.downloadUrlForPlatform', () {
    const cfg = AppRemoteConfigData(
      maintenanceMode: false,
      maintenanceMessageAr: '',
      syncPausedGlobally: false,
      syncPausedMessageAr: '',
      minSupportedVersion: '1.0.0',
      latestVersion: '2.2.35',
      updateMessageAr: '',
      forceUpdate: false,
      updateDownloadUrl: 'https://example.com/naboo.apk',
      updateDownloadUrlWindows: 'https://example.com/naboo-windows-setup.exe',
      announcementTitleAr: '',
      announcementBodyAr: '',
      announcementUrl: '',
    );

    test('windows uses setup exe only', () {
      expect(
        cfg.downloadUrlForPlatform(isWindows: true),
        'https://example.com/naboo-windows-setup.exe',
      );
    });

    test('android uses apk only', () {
      expect(
        cfg.downloadUrlForPlatform(isWindows: false),
        'https://example.com/naboo.apk',
      );
    });

    test('windows does not fall back to apk', () {
      const emptyWin = AppRemoteConfigData(
        maintenanceMode: false,
        maintenanceMessageAr: '',
        syncPausedGlobally: false,
        syncPausedMessageAr: '',
        minSupportedVersion: '1.0.0',
        latestVersion: '2.2.35',
        updateMessageAr: '',
        forceUpdate: false,
        updateDownloadUrl: 'https://example.com/naboo.apk',
        updateDownloadUrlWindows: '',
        announcementTitleAr: '',
        announcementBodyAr: '',
        announcementUrl: '',
      );
      expect(emptyWin.downloadUrlForPlatform(isWindows: true), isEmpty);
    });
  });
}
