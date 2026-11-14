/// إعدادات حملة واتساب جماعية — قيم افتراضية آمنة ضد الحظر.
class OilChangeCampaignSettings {
  const OilChangeCampaignSettings({
    this.maxMessages = 100,
    this.intervalSeconds = 30,
    this.restEveryMessages = 25,
    this.restMinutes = 5,
    this.maxMessageLength = 1000,
  });

  static const int defaultMaxMessages = 100;
  static const int defaultIntervalSeconds = 30;
  static const int defaultRestEveryMessages = 25;
  static const int defaultRestMinutes = 5;
  static const int defaultMaxMessageLength = 1000;

  final int maxMessages;
  final int intervalSeconds;
  final int restEveryMessages;
  final int restMinutes;
  final int maxMessageLength;

  int estimatedSecondsForCount(int recipientCount) {
    final n = recipientCount.clamp(0, maxMessages);
    if (n <= 0) return 0;
    final intervals = n > 1 ? n - 1 : 0;
    final restBlocks = restEveryMessages > 0 ? (n ~/ restEveryMessages) : 0;
    return intervals * intervalSeconds + restBlocks * restMinutes * 60;
  }

  OilChangeCampaignSettings copyWith({
    int? maxMessages,
    int? intervalSeconds,
    int? restEveryMessages,
    int? restMinutes,
  }) {
    return OilChangeCampaignSettings(
      maxMessages: maxMessages ?? this.maxMessages,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      restEveryMessages: restEveryMessages ?? this.restEveryMessages,
      restMinutes: restMinutes ?? this.restMinutes,
      maxMessageLength: maxMessageLength,
    );
  }
}
