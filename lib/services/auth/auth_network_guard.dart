import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../connectivity_resume_sync.dart';

/// فحص سريع لوجود رابط شبكة قبل عمليات المصادقة السحابية.
abstract final class AuthNetworkGuard {
  AuthNetworkGuard._();

  static Future<bool> hasNetworkLink() async {
    try {
      final results = await Connectivity()
          .checkConnectivity()
          .timeout(const Duration(seconds: 3));
      return connectivityResultsOnline(results);
    } catch (_) {
      return false;
    }
  }
}
