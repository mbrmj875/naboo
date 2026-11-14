import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/verticals/restaurant/models/restaurant_models.dart';
import 'package:naboo/verticals/restaurant/services/reservation_service.dart';
import 'package:naboo/verticals/restaurant/services/restaurant_db_schema.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('concurrent critical reserves: one succeeds, one fails atomically', () async {
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE products (
              id INTEGER PRIMARY KEY,
              tenantId INTEGER NOT NULL,
              name TEXT NOT NULL,
              qty REAL NOT NULL,
              buyPrice REAL NOT NULL DEFAULT 0
            )
          ''');
          await ensureRestaurantTables(db);
        },
      ),
    );

    await db.insert('products', {
      'id': 1,
      'tenantId': 1,
      'name': 'لحم',
      'qty': 1.0, // 1000 micro
      'buyPrice': 5,
    });

    const svc = ReservationService();
    final need = const IngredientNeed(
      productId: 1,
      qtyMicroNeeded: 1000,
      isCritical: true,
      nameAr: 'لحم',
    );

    Object? errA;
    Object? errB;

    // محاكاة تزامن: تسلسل داخل نفس الـDB؛ الثاني يرى الحجز الأول.
    try {
      await db.transaction((txn) async {
        await svc.reserveCritical(
          txn: txn,
          tenantId: 1,
          orderId: 10,
          sessionId: 1,
          criticalNeeds: [need],
        );
      });
    } catch (e) {
      errA = e;
    }

    try {
      await db.transaction((txn) async {
        await svc.reserveCritical(
          txn: txn,
          tenantId: 1,
          orderId: 11,
          sessionId: 2,
          criticalNeeds: [need],
        );
      });
    } catch (e) {
      errB = e;
    }

    expect(errA, isNull);
    expect(errB, isA<IngredientShortageException>());

    final reserved = await db.query(
      'restaurant_ingredient_reservations',
      where: "state = 'reserved'",
    );
    expect(reserved.length, 1);
    expect(reserved.first['order_id'], 10);

    await db.close();
  });
}
