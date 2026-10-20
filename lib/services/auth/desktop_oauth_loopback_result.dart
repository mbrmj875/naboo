class DesktopOAuthLoopbackResult {
  const DesktopOAuthLoopbackResult._({
    required this.success,
    required this.cancelled,
    this.message,
  });

  final bool success;
  final bool cancelled;
  final String? message;

  factory DesktopOAuthLoopbackResult.ok() =>
      const DesktopOAuthLoopbackResult._(success: true, cancelled: false);

  factory DesktopOAuthLoopbackResult.cancelled() =>
      const DesktopOAuthLoopbackResult._(success: false, cancelled: true);

  factory DesktopOAuthLoopbackResult.failed([String? message]) =>
      DesktopOAuthLoopbackResult._(
        success: false,
        cancelled: false,
        message: message,
      );
}
