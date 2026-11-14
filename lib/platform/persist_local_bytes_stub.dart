import 'dart:convert';
import 'dart:typed_data';

/// على الويب: data-URI قابل للتخزين في SQLite والمزامنة.
Future<String> persistLocalBytes({
  required Uint8List bytes,
  required String relativeDir,
  required String fileName,
}) async {
  final lower = fileName.toLowerCase();
  final mime = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
  return 'data:$mime;base64,${base64Encode(bytes)}';
}
