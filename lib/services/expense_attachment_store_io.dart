import 'dart:io';
import 'dart:typed_data';

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

  /// يحفظ بايتات الصورة ويُرجع مساراً مستقراً (ملف أو data-URI حسب المنصة).
  Future<String> saveBytes(
    Uint8List bytes, {
    String extension = '.jpg',
  }) async {
    final dir = await _dir();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final name = 'exp_${DateTime.now().millisecondsSinceEpoch}$ext';
    final target = File(p.join(dir.path, name));
    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }

  /// توافق مع الاستدعاءات القديمة التي تمرّر [File].
  Future<String> save(File source) async {
    final ext = p.extension(source.path).isEmpty
        ? '.jpg'
        : p.extension(source.path);
    final bytes = await source.readAsBytes();
    return saveBytes(bytes, extension: ext);
  }

  Future<void> delete(String path) async {
    final raw = path.trim();
    if (raw.isEmpty || raw.startsWith('data:')) return;
    try {
      final f = File(raw);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {
      // Ignored: it's ok if the file doesn't exist anymore.
    }
  }
}
