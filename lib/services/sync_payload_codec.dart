import 'dart:convert';
import 'package:archive/archive.dart';

class SyncPayloadCodec {
  static String encode(Map<String, dynamic> payload) {
    final raw = utf8.encode(jsonEncode(payload));
    return base64Encode(const GZipEncoder().encodeBytes(raw));
  }

  static Map<String, dynamic> decode(String text) {
    final gz = base64Decode(text);
    final decodedBytes = const GZipDecoder().decodeBytes(gz);
    final decoded = utf8.decode(decodedBytes);
    final data = jsonDecode(decoded);
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Decoded payload is not a map');
    }
    return data;
  }

  static List<String> splitText(String text, int partSize) {
    if (text.isEmpty) return const [];
    final out = <String>[];
    for (var i = 0; i < text.length; i += partSize) {
      final end = (i + partSize < text.length) ? i + partSize : text.length;
      out.add(text.substring(i, end));
    }
    return out;
  }

  static String joinText(List<String> chunks) => chunks.join();

  static DateTime? rowDate(dynamic v) {
    final s = v?.toString();
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s)?.toUtc();
  }

  static DateTime? bestTimestamp(Map<String, dynamic> row) {
    return rowDate(row['updatedAt']) ??
        rowDate(row['updated_at']) ??
        rowDate(row['createdAt']) ??
        rowDate(row['created_at']) ??
        rowDate(row['date']);
  }

  static bool incomingWins(
    Map<String, dynamic> current,
    Map<String, dynamic> incoming,
  ) {
    final currTs = bestTimestamp(current);
    final inTs = bestTimestamp(incoming);
    if (currTs == null && inTs == null) return false;
    if (currTs == null) return true;
    if (inTs == null) return false;
    return inTs.isAfter(currTs);
  }

  static String? pickDeltaColumn(Set<String> cols) {
    const options = [
      'updatedAt',
      'updated_at',
      'createdAt',
      'created_at',
      'date',
      'id',
    ];
    for (final c in options) {
      if (cols.contains(c)) return c;
    }
    return null;
  }
}
