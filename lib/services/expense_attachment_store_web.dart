import 'dart:convert';
import 'dart:typed_data';

/// على الويب: نحفظ المرفق كـ data-URI داخل قاعدة البيانات (يتزامن مع snapshot).
class ExpenseAttachmentStore {
  ExpenseAttachmentStore._();
  static final ExpenseAttachmentStore instance = ExpenseAttachmentStore._();

  Future<String> saveBytes(
    Uint8List bytes, {
    String extension = '.jpg',
  }) async {
    final mime = extension.toLowerCase().contains('png')
        ? 'image/png'
        : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<void> delete(String path) async {
    // data-URI يُحذف بإزالة المرجع من السجل — لا ملفات لحذفها.
  }
}
