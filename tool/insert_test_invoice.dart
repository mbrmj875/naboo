
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/models/invoice.dart';
import '../lib/services/database_helper.dart';
import '../lib/services/supabase_config.dart';

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

  final id = await db.insertInvoice(invoice);
  debugPrint('Inserted test invoice id=$id');
}
