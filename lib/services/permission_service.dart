import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';
import 'tenant_context_service.dart';

/// مفاتيح صلاحيات النظام — تُخزَّن في [user_permissions] / [role_permissions].
abstract class PermissionKeys {
  // ── تطبيق ──
  static const appDashboard = 'app.dashboard';

  // ── عملاء وولاء ──
  static const customersView = 'customers.view';
  static const customersManage = 'customers.manage';
  static const customersContacts = 'customers.contacts';
  static const loyaltyAccess = 'loyalty.access';

  // ── مبيعات ──
  static const salesPos = 'sales.pos';
  static const salesParked = 'sales.parked';
  static const salesReturns = 'sales.returns';

  // ── مخزون (كما في الإصدارات السابقة) ──
  static const inventoryView = 'inventory.view';
  static const inventoryProductsManage = 'inventory.products.manage';
  static const inventoryVoucherIn = 'inventory.vouchers.in';
  static const inventoryVoucherOut = 'inventory.vouchers.out';
  static const inventoryVoucherTransfer = 'inventory.vouchers.transfer';
  static const inventoryStocktakingManage = 'inventory.stocktaking.manage';
  static const inventoryPoliciesManage = 'inventory.policies.manage';

  // ── صندوق ──
  static const cashView = 'cash.view';
  static const cashManual = 'cash.manual';

  // ── ديون ──
  static const debtsPanel = 'debts.panel';
  static const debtsSettings = 'debts.settings';

  // ── أقساط ──
  static const installmentsPlans = 'installments.plans';
  static const installmentsSettings = 'installments.settings';

  // ── تقارير وطباعة ──
  static const reportsAccess = 'reports.access';
  static const printingAccess = 'printing.access';

  // ── مستخدمون وورديات ──
  static const usersView = 'users.view';
  static const usersManage = 'users.manage';
  static const shiftsAccess = 'shifts.access';
  static const absencesAccess = 'absences.access';

  // ── إعدادات عامة ──
  static const settingsApp = 'settings.app';

  static const List<String> allKeys = [
    appDashboard,
    customersView,
    customersManage,
    customersContacts,
    loyaltyAccess,
    salesPos,
    salesParked,
    salesReturns,
    inventoryView,
    inventoryProductsManage,
    inventoryVoucherIn,
    inventoryVoucherOut,
    inventoryVoucherTransfer,
    inventoryStocktakingManage,
    inventoryPoliciesManage,
    cashView,
    cashManual,
    debtsPanel,
    debtsSettings,
    installmentsPlans,
    installmentsSettings,
    reportsAccess,
    printingAccess,
    usersView,
    usersManage,
    shiftsAccess,
    absencesAccess,
    settingsApp,
  ];
}

class PermissionService {
  PermissionService._();
  static final PermissionService instance = PermissionService._();

  final DatabaseHelper _dbHelper = DatabaseHelper();
  final TenantContextService _tenant = TenantContextService.instance;

  static final Set<String> _adminAll = PermissionKeys.allKeys.toSet();

  /// افتراضات الموظف عند عدم وجود صفوف في [user_permissions].
  static final Set<String> _staffDefault = {
    PermissionKeys.appDashboard,
    PermissionKeys.customersView,
    PermissionKeys.salesPos,
    PermissionKeys.cashView,
    PermissionKeys.inventoryView,
    PermissionKeys.inventoryVoucherIn,
    PermissionKeys.inventoryVoucherOut,
    PermissionKeys.debtsPanel,
    PermissionKeys.installmentsPlans,
    PermissionKeys.shiftsAccess,
  };

  int get _tenantId => _tenant.activeTenantId;

  Set<String> _defaultsForRole(String roleKey) {
    if (roleKey == 'admin') return _adminAll;
    return _staffDefault;
  }

  /// عند وجود وردية مفتوحة مع [shiftStaffUserId]، تُحتسب الصلاحيات لمستخدم الوردية لا لمستخدم تسجيل الدخول فقط.
  Future<({int? userId, String roleKey})> resolveEffectivePermissionSubject({
    required int? sessionUserId,
    required String sessionRoleKey,
    Map<String, dynamic>? activeShift,
  }) async {
    final raw = activeShift?['shiftStaffUserId'];
    int? sid;
    if (raw is int) {
      sid = raw;
    } else if (raw is num) {
      sid = raw.toInt();
    }
    if (sid != null && sid > 0) {
      final row = await _dbHelper.getUserById(sid);
      if (row != null && (row['isActive'] == 1)) {
        final rk = (row['role'] as String?) ?? 'staff';
        return (userId: sid, roleKey: rk);
      }
    }
    return (userId: sessionUserId, roleKey: sessionRoleKey);
  }

  Future<bool> canForSession({
    required int? sessionUserId,
    required String sessionRoleKey,
    Map<String, dynamic>? activeShift,
    required String permissionKey,
  }) async {
    final sub = await resolveEffectivePermissionSubject(
      sessionUserId: sessionUserId,
      sessionRoleKey: sessionRoleKey,
      activeShift: activeShift,
    );
    return can(
      userId: sub.userId,
      roleKey: sub.roleKey,
      permissionKey: permissionKey,
    );
  }

  Future<bool> can({
    required int? userId,
    required String roleKey,
    required String permissionKey,
  }) async {
    final db = await _dbHelper.database;
    final tid = _tenantId;

    if (userId != null && userId > 0) {
      final userRows = await db.query(
        'user_permissions',
        columns: ['isAllowed'],
        where: 'tenantId = ? AND userId = ? AND permissionKey = ?',
        whereArgs: [tid, userId, permissionKey],
        limit: 1,
      );
      if (userRows.isNotEmpty) {
        return ((userRows.first['isAllowed'] as num?)?.toInt() ?? 0) == 1;
      }
    }

    final roleRows = await db.query(
      'role_permissions',
      columns: ['isAllowed'],
      where: 'tenantId = ? AND roleKey = ? AND permissionKey = ?',
      whereArgs: [tid, roleKey, permissionKey],
      limit: 1,
    );
    if (roleRows.isNotEmpty) {
      return ((roleRows.first['isAllowed'] as num?)?.toInt() ?? 0) == 1;
    }

    final fallback = _defaultsForRole(roleKey);
    return fallback.contains(permissionKey);
  }

  /// خريطة صلاحيات للتحرير في نموذج المستخدم (موظف: صفوف + افتراضات).
  Future<Map<String, bool>> getUserPermissionMapForEdit({
    required int userId,
    required String roleKey,
  }) async {
    if (roleKey == 'admin') {
      return {for (final k in PermissionKeys.allKeys) k: true};
    }
    final db = await _dbHelper.database;
    final tid = _tenantId;
    final rows = await db.query(
      'user_permissions',
      columns: ['permissionKey', 'isAllowed'],
      where: 'tenantId = ? AND userId = ?',
      whereArgs: [tid, userId],
    );
    final byKey = <String, bool>{
      for (final r in rows)
        r['permissionKey'] as String:
            ((r['isAllowed'] as num?)?.toInt() ?? 0) == 1,
    };
    final defaults = _defaultsForRole(roleKey);
    return {
      for (final k in PermissionKeys.allKeys)
        k: byKey.containsKey(k) ? byKey[k]! : defaults.contains(k),
    };
  }

  /// افتراضات الموظف لحساب جديد (قبل إدراج صفوف).
  Map<String, bool> defaultStaffPermissionMap() {
    final d = _staffDefault;
    return {for (final k in PermissionKeys.allKeys) k: d.contains(k)};
  }

  Future<void> clearUserPermissionOverrides(int userId) async {
    final db = await _dbHelper.database;
    await db.delete(
      'user_permissions',
      where: 'tenantId = ? AND userId = ?',
      whereArgs: [_tenantId, userId],
    );
  }

  /// يستبدل كل صلاحيات المستخدم الصريحة (للموظفين).
  Future<void> replaceUserPermissions({
    required int userId,
    required Map<String, bool> permissions,
  }) async {
    final db = await _dbHelper.database;
    final tid = _tenantId;
    final batch = db.batch();
    batch.delete(
      'user_permissions',
      where: 'tenantId = ? AND userId = ?',
      whereArgs: [tid, userId],
    );
    final now = DateTime.now().toIso8601String();
    for (final e in permissions.entries) {
      batch.insert(
        'user_permissions',
        {
          'tenantId': tid,
          'userId': userId,
          'permissionKey': e.key,
          'isAllowed': e.value ? 1 : 0,
          'updatedAt': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> setRolePermission({
    required String roleKey,
    required String permissionKey,
    required bool isAllowed,
  }) async {
    final db = await _dbHelper.database;
    final tid = _tenantId;
    await db.insert('role_permissions', {
      'tenantId': tid,
      'roleKey': roleKey,
      'permissionKey': permissionKey,
      'isAllowed': isAllowed ? 1 : 0,
      'updatedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> setUserPermission({
    required int userId,
    required String permissionKey,
    required bool isAllowed,
  }) async {
    final db = await _dbHelper.database;
    final tid = _tenantId;
    await db.insert('user_permissions', {
      'tenantId': tid,
      'userId': userId,
      'permissionKey': permissionKey,
      'isAllowed': isAllowed ? 1 : 0,
      'updatedAt': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
