import 'package:flutter/widgets.dart' show BuildContext;

import '../../models/expense.dart';
import '../../printing/receipt_builders.dart';
import '../../printing/receipt_printer.dart';

/// سند صرف المصروف بقالب «سند صرف» من قسم الطباعة: طابعة الجهاز مباشرة،
/// وإلا نافذة طباعة النظام بنفس صورة السند (لا PDF منفصل بشكل آخر).
class ExpenseReceiptPrinter {
  ExpenseReceiptPrinter._();

  static Future<void> show(ExpenseEntry entry, {required BuildContext context}) =>
      ReceiptPrinter.printOrSystemDialog(
        context,
        ReceiptBuilders.expense(entry),
      );
}
