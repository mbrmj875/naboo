// ─────────────────────────────────────────────────────────────────────────────
// هذا الملف يُولَّد تلقائياً بواسطة FlutterFire CLI.
// بعد تشغيل: flutterfire configure
// سيُستبدل هذا الملف بالقيم الصحيحة من مشروع Firebase الخاص بك.
//
// الخطوات:
//   1. اذهب إلى https://console.firebase.google.com
//   2. أنشئ مشروعاً جديداً باسم naboo-licenses
//   3. فعّل Firestore و Authentication (Anonymous)
//   4. شغّل في Terminal: flutterfire configure
//   5. اختر مشروعك → سيُنشئ هذا الملف تلقائياً بالقيم الصحيحة
// ─────────────────────────────────────────────────────────────────────────────

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:  return android;
      case TargetPlatform.iOS:      return ios;
      case TargetPlatform.macOS:    return macos;
      case TargetPlatform.windows:  return windows;
      case TargetPlatform.linux:    throw UnsupportedError('Linux not supported');
      default:                      throw UnsupportedError('Unknown platform');
    }
  }

  // ── استبدل القيم أدناه بقيم مشروعك من Firebase Console ──────────────────
  // ستجدها في: Project Settings → Your apps → Config

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyCMSTANLVf-VkWZiM8SnqrKXZdqc4EXhVY',
    appId: '1:281392172783:web:b78a05dd0c8f311818151a',
    messagingSenderId: '281392172783',
    projectId: 'naboo-93580',
    authDomain: 'naboo-93580.firebaseapp.com',
    storageBucket: 'naboo-93580.firebasestorage.app',
    measurementId: 'G-TMWVPDJSEP',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCzHzbSN54H4ou58XAh-Yv2kW_ADsct9L4',
    appId: '1:281392172783:android:86018c680e01403a18151a',
    messagingSenderId: '281392172783',
    projectId: 'naboo-93580',
    storageBucket: 'naboo-93580.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB52IFcUaQ-uCVjLMJT2z2OONP8I9xMENI',
    appId: '1:281392172783:ios:7c9ee1fd5470a6e918151a',
    messagingSenderId: '281392172783',
    projectId: 'naboo-93580',
    storageBucket: 'naboo-93580.firebasestorage.app',
    iosBundleId: 'com.basra.storemanager',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyB52IFcUaQ-uCVjLMJT2z2OONP8I9xMENI',
    appId: '1:281392172783:ios:7c9ee1fd5470a6e918151a',
    messagingSenderId: '281392172783',
    projectId: 'naboo-93580',
    storageBucket: 'naboo-93580.firebasestorage.app',
    iosBundleId: 'com.basra.storemanager',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyCMSTANLVf-VkWZiM8SnqrKXZdqc4EXhVY',
    appId: '1:281392172783:web:5f582b1d6152783218151a',
    messagingSenderId: '281392172783',
    projectId: 'naboo-93580',
    authDomain: 'naboo-93580.firebaseapp.com',
    storageBucket: 'naboo-93580.firebasestorage.app',
    measurementId: 'G-052T7Z1NZR',
  );
}
