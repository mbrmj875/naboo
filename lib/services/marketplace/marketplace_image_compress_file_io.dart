import 'dart:io';
import 'dart:typed_data';

import 'marketplace_image_compress_core.dart';

Future<Uint8List?> compressImageFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return null;
  final raw = await file.readAsBytes();
  return MarketplaceImageCompressCore.compressBytes(raw);
}
