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
    apiKey:            'YOUR-WEB-API-KEY',
    appId:             'YOUR-WEB-APP-ID',
    messagingSenderId: 'YOUR-SENDER-ID',
    projectId:         'YOUR-PROJECT-ID',
    authDomain:        'YOUR-PROJECT-ID.firebaseapp.com',
    storageBucket:     'YOUR-PROJECT-ID.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBJb21mA_icY3P0ykAhajKcfiLBRapgpYE',
    appId: '1:201331038467:android:d59414d912d42bb8703136',
    messagingSenderId: '201331038467',
    projectId: 'naboo-m',
    storageBucket: 'naboo-m.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCtCKHs_MMz9Kw-aKQd68EFAIBKzv2DZO8',
    appId: '1:201331038467:ios:0cb65ac76b68dcce703136',
    messagingSenderId: '201331038467',
    projectId: 'naboo-m',
    storageBucket: 'naboo-m.firebasestorage.app',
    iosBundleId: 'com.yourdomain.yourAppName',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyCtCKHs_MMz9Kw-aKQd68EFAIBKzv2DZO8',
    appId: '1:201331038467:ios:e3e419a05339268c703136',
    messagingSenderId: '201331038467',
    projectId: 'naboo-m',
    storageBucket: 'naboo-m.firebasestorage.app',
    iosBundleId: 'com.basra.storemanager',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDFGkfcqxeWJEab63TyLxuyPtBs8sbVZa0',
    appId: '1:201331038467:web:cbe2a07852068cc2703136',
    messagingSenderId: '201331038467',
    projectId: 'naboo-m',
    authDomain: 'naboo-m.firebaseapp.com',
    storageBucket: 'naboo-m.firebasestorage.app',
    measurementId: 'G-BQN14KZLZQ',
  );

}