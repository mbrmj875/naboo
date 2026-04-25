import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// تخزين مرفقات المصروفات (صور الفواتير) داخل مجلد التطبيق الخاص.
class ExpenseAttachmentStore {
  ExpenseAttachmentStore._();
  static final ExpenseAttachmentStore instance = ExpenseAttachmentStore._();

  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'expenses_attachments'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// ينسخ الملف المصدر إلى مجلد التطبيق ويُرجع مسارًا مستقرًا داخل المجلد.
  Future<String> save(File source) async {
    final dir = await _dir();
    final ext = p.extension(source.path).isEmpty
        ? '.jpg'
        : p.extension(source.path);
    final name = 'exp_${DateTime.now().millisecondsSinceEpoch}$ext';
    final target = File(p.join(dir.path, name));
    await source.copy(target.path);
    return target.path;
  }

  Future<void> delete(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // Ignored: it's ok if the file doesn't exist anymore.
    }
  }
}
