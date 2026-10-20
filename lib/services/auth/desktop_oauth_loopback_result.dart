class DesktopOAuthLoopbackResult {
  const DesktopOAuthLoopbackResult._({
    required this.success,
    required this.cancelled,
  });

  final bool success;
  final bool cancelled;

  factory DesktopOAuthLoopbackResult.ok() =>
      const DesktopOAuthLoopbackResult._(success: true, cancelled: false);

  factory DesktopOAuthLoopbackResult.cancelled() =>
      const DesktopOAuthLoopbackResult._(success: false, cancelled: true);

  factory DesktopOAuthLoopbackResult.failed() =>
      const DesktopOAuthLoopbackResult._(success: false, cancelled: false);
}
