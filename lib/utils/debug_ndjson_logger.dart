import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

class DebugNdjsonLogger {
  DebugNdjsonLogger._();

  static const String sessionId = 'd6439a';
  static const String logPath =
      '/Users/mohamed123/Development/projict/basra_store_manager/.cursor/debug-d6439a.log';

  static void log({
    required String runId,
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, Object?>? data,
  }) {
    if (!kDebugMode) return;
    if (kIsWeb) return;
    try {
      final payload = <String, Object?>{
        'sessionId': sessionId,
        'runId': runId,
        'hypothesisId': hypothesisId,
        'location': location,
        'message': message,
        'data': data ?? const <String, Object?>{},
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      final file = File(logPath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // ignore
    }
  }
}

