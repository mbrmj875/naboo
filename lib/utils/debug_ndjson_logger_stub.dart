class DebugNdjsonLogger {
  DebugNdjsonLogger._();

  static const String sessionId = 'd6439a';
  static const String logPath = '';

  static void log({
    required String runId,
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, Object?>? data,
  }) {
    // لا كتابة ملفات على الويب.
  }
}
