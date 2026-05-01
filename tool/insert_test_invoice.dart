import 'package:flutter/widgets.dart';
import 'package:naboo/models/invoice.dart';
import 'package:naboo/services/database_helper.dart';
import 'package:naboo/services/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
    authOptions: const FlutterAuthClientOptions(
      autoRefreshToken: false,
    ),
  );

  final db = DatabaseHelper();
  final invoice = Invoice(
    customerName: 'عميل تجريبي',
    date: DateTime.now(),
    type: InvoiceType.cash,
    items: [
      InvoiceItem(
        productName: 'بند تجريبي',
        quantity: 1,
        price: 10.0,
        total: 10.0,
      ),
    ],
    discount: 0,
    tax: 0,
    advancePayment: 0,
    total: 10.0,
    isReturned: false,
    createdByUserName: 'test_runner',
  );

  final id = await db.insertInvoiceWithPolicy(
    invoice,
    enforceStockNonZero: false,
  );
  debugPrint('Inserted test invoice id=$id');
}
