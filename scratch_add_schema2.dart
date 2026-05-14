import 'dart:io';

void main() {
  final f = File('lib/services/database_helper.dart');
  var content = f.readAsStringSync();
  
  if (content.contains('ALTER TABLE supplier_bills ADD COLUMN supplier_global_id TEXT')) {
    print('already added');
    return;
  }
  
  final additions = '''
    if (!await _tableHasColumn(db, 'supplier_bills', 'supplier_global_id')) {
        await db.execute('ALTER TABLE supplier_bills ADD COLUMN supplier_global_id TEXT');
    }
    if (!await _tableHasColumn(db, 'supplier_payouts', 'supplier_global_id')) {
        await db.execute('ALTER TABLE supplier_payouts ADD COLUMN supplier_global_id TEXT');
    }
    
    // update supplier_global_id in bills
    await db.execute(\'\'\'
      UPDATE supplier_bills
      SET supplier_global_id = (SELECT global_id FROM suppliers WHERE suppliers.id = supplier_bills.supplierId)
      WHERE supplierId IS NOT NULL AND (supplier_global_id IS NULL OR supplier_global_id = '')
    \'\'\');
    
    // update supplier_global_id in payouts
    await db.execute(\'\'\'
      UPDATE supplier_payouts
      SET supplier_global_id = (SELECT global_id FROM suppliers WHERE suppliers.id = supplier_payouts.supplierId)
      WHERE supplierId IS NOT NULL AND (supplier_global_id IS NULL OR supplier_global_id = '')
    \'\'\');
  }
''';

  content = content.replaceFirst(
    "UPDATE customer_debt_payments\n      SET customer_global_id = (SELECT global_id FROM customers WHERE customers.id = customer_debt_payments.customerId)\n      WHERE customerId IS NOT NULL AND (customer_global_id IS NULL OR customer_global_id = '')\n    \'\'\');\n  }",
    "UPDATE customer_debt_payments\n      SET customer_global_id = (SELECT global_id FROM customers WHERE customers.id = customer_debt_payments.customerId)\n      WHERE customerId IS NOT NULL AND (customer_global_id IS NULL OR customer_global_id = '')\n    \'\'\');\n" + additions
  );
  
  f.writeAsStringSync(content);
  print('Done additions');
}
