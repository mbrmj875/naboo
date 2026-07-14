/// تحويل طوابع زمنية من SQLite/ISO إلى الوقت المحلي للعرض.
DateTime parseActivityTimestamp(String? raw) {
  if (raw == null || raw.trim().isEmpty) return DateTime.now();
  final parsed = DateTime.tryParse(raw.trim());
  if (parsed == null) return DateTime.now();
  return parsed.toLocal();
}
