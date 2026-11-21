import 'dart:async';

import 'package:sqflite/sqflite.dart';

/// معاملة واحدة مشتركة لعدة مستودعات.
///
/// كل مستودع يفتح معاملته الخاصة، وsqflite لا يقبل معاملة داخل معاملة. داخل
/// [SharedDbTransaction.run] يُرجع `DatabaseHelper().database` غلافاً يمرّر
/// كل قراءة وكتابة إلى المعاملة المفتوحة، و`transaction()` المتداخلة تنضم
/// إليها. فإن رمى أي جزء خطأً تُلغى كل الكتابات معاً: إما ينجح الكل أو لا شيء.
///
/// لا يُفتح داخلها أي حوار ينتظر المستخدم؛ القاعدة مقفلة حتى تنتهي.
class SharedDbTransaction {
  SharedDbTransaction._();

  static final Object _zoneKey = Object();

  /// الغلاف النشط في هذه السلسلة، أو `null` خارج معاملة مشتركة.
  static Database? current() {
    final holder = Zone.current[_zoneKey];
    if (holder is! _Holder) return null;
    return holder.joined;
  }

  static bool get isActive => current() != null;

  /// ينفّذ [action] في معاملة واحدة على [db]. داخل معاملة مشتركة أخرى ينضم
  /// إليها بدل فتح جديدة.
  static Future<T> run<T>(Database db, Future<T> Function() action) {
    if (isActive) return action();
    final holder = _Holder();
    return db.transaction<T>((txn) async {
      holder.joined = _JoinedTransactionDatabase(db, txn);
      try {
        return await runZoned(action, zoneValues: {_zoneKey: holder});
      } finally {
        // عمل مؤجَّل بدأ داخل المعاملة (مؤقت مزامنة مثلاً) يعود للقاعدة نفسها
        // بعد انتهائها، لا لمعاملة مغلقة.
        holder.joined = null;
      }
    });
  }
}

class _Holder {
  Database? joined;
}

/// [Database] يمرّر كل شيء إلى [txn]، و`transaction()` تنضم إليها.
class _JoinedTransactionDatabase implements Database {
  _JoinedTransactionDatabase(this._db, this._txn);

  final Database _db;
  final Transaction _txn;

  @override
  String get path => _db.path;

  @override
  bool get isOpen => _db.isOpen;

  @override
  Database get database => this;

  @override
  Future<void> close() =>
      throw StateError('لا يُغلق الاتصال داخل معاملة مشتركة');

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => action(_txn);

  @override
  Future<T> readTransaction<T>(Future<T> Function(Transaction txn) action) =>
      action(_txn);

  @override
  Batch batch() => _txn.batch();

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) =>
      _txn.execute(sql, arguments);

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) =>
      _txn.rawInsert(sql, arguments);

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _txn.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => _txn.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) => _txn.rawQuery(sql, arguments);

  @override
  Future<QueryCursor> rawQueryCursor(
    String sql,
    List<Object?>? arguments, {
    int? bufferSize,
  }) => _txn.rawQueryCursor(sql, arguments, bufferSize: bufferSize);

  @override
  Future<QueryCursor> queryCursor(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
    int? bufferSize,
  }) => _txn.queryCursor(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
    bufferSize: bufferSize,
  );

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) =>
      _txn.rawUpdate(sql, arguments);

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => _txn.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) =>
      _txn.rawDelete(sql, arguments);

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) =>
      _txn.delete(table, where: where, whereArgs: whereArgs);

  @override
  // ignore: deprecated_member_use
  Future<T> devInvokeMethod<T>(String method, [Object? arguments]) =>
      // ignore: deprecated_member_use
      _db.devInvokeMethod<T>(method, arguments);

  @override
  // ignore: deprecated_member_use
  Future<T> devInvokeSqlMethod<T>(
    String method,
    String sql, [
    List<Object?>? arguments,
  ]) =>
      // ignore: deprecated_member_use
      _db.devInvokeSqlMethod<T>(method, sql, arguments);
}
