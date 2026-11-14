import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// يحفظ بايتات تحت مجلد المستندات ويعيد مسار الملف.
Future<String> persistLocalBytes({
  required Uint8List bytes,
  required String relativeDir,
  required String fileName,
}) async {
  final base = await getApplicationDocumentsDirectory();
  final dir = Directory(p.join(base.path, relativeDir));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final dest = File(p.join(dir.path, fileName));
  await dest.writeAsBytes(bytes, flush: true);
  return dest.path;
}
