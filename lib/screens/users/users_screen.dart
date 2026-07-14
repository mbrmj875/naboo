import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../utils/screen_layout.dart';
import '../../theme/design_tokens.dart';
import 'employee_identity_screen.dart';
import 'user_form_screen.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final DatabaseHelper _db = DatabaseHelper();
  List<Map<String, dynamic>> _rows = [];
  Set<int> _protectedOwnerIds = const <int>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    CloudSyncService.instance.remoteImportGeneration.addListener(_onCloudImport);
    _load();
  }

  @override
  void dispose() {
    CloudSyncService.instance.remoteImportGeneration.removeListener(
      _onCloudImport,
    );
    super.dispose();
  }

  void _onCloudImport() {
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _db.listActiveUsers();
      if (!mounted) return;
      final protectedIds = <int>{};
      final activeOwners = list
          .where((e) => (e['role'] as String? ?? 'staff') == 'owner')
          .toList(growable: false);
      if (activeOwners.length <= 1 && activeOwners.isNotEmpty) {
        protectedIds.add((activeOwners.first['id'] as num).toInt());
      }
      setState(() {
        _rows = list.where((e) => (e['role'] as String? ?? 'staff') != 'owner').toList();
        _protectedOwnerIds = protectedIds;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = [];
        _protectedOwnerIds = const <int>{};
        _loading = false;
      });
    }
  }

  Future<void> _refreshFromServer() async {
    await CloudSyncService.instance.syncNow(
      forcePull: true,
      forcePush: true,
      forceImportOnPull: true,
    );
    if (!mounted) return;
    await _load();
  }

  String _roleAr(String? r) {
    switch (r) {
      case 'owner':
        return 'صاحب العمل';
      case 'admin':
        return 'مدير';
      default:
        return 'موظف';
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final auth = context.read<AuthProvider>();
    final canManageUsers = auth.isOwner || auth.isAdmin;
    final existingRole = (existing?['role'] as String? ?? 'staff').trim();
    if (!canManageUsers) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا صلاحية — هذا الإجراء متاح لصاحب العمل أو المدير'),
        ),
      );
      return;
    }
    if (auth.isAdmin && existing != null && existingRole != 'staff') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا يمكن للمدير تعديل حساب مدير أو صاحب عمل'),
        ),
      );
      return;
    }
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute(
        builder: (_) => UserFormScreen(
          existing: existing == null
              ? null
              : Map<String, dynamic>.from(existing),
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) {
      await _load();
    } else if (result is int) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EmployeeIdentityScreen(initialUserId: result),
        ),
      );
      await _load();
    }
  }

  Future<void> _openIdentity(int userId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => EmployeeIdentityScreen(initialUserId: userId),
      ),
    );
  }

  Future<void> _deactivate(Map<String, dynamic> row) async {
    final auth = context.read<AuthProvider>();
    final canManageUsers = auth.isOwner || auth.isAdmin;
    if (!canManageUsers) return;
    final id = row['id'] as int;
    final roleKey = (row['role'] as String? ?? 'staff').trim();
    if (id == auth.userId && roleKey == 'owner') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن لصاحب العمل تعطيل حسابه الشخصي')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعطيل المستخدم'),
          content: const Text('سيتم إيقاف الحساب ولن يستطيع تسجيل الدخول.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('تعطيل'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _db.deactivateUser(
        id,
        actingUserId: auth.userId,
        actingRoleKey: auth.roleKey,
      );
    } on UserGovernanceException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم التعطيل')));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final canManageUsers = auth.isOwner || auth.isAdmin;

    final cs = Theme.of(context).colorScheme;
    final gap = ScreenLayout.of(context).pageHorizontalGap;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          leading: const BackButton(),
          title: Text(
            'المستخدمون',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          backgroundColor: cs.surfaceContainerHighest,
          foregroundColor: cs.onSurface,
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.accentGold),
              tooltip: 'تحديث',
              onPressed: _loading ? null : _refreshFromServer,
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
            ? _buildEmptyState()
            : RefreshIndicator(
                onRefresh: _refreshFromServer,
                child: ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: gap, vertical: 16),
                  itemCount: _rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _buildUserCard(_rows[i], auth),
                ),
              ),
        floatingActionButton: canManageUsers
            ? FloatingActionButton.extended(
                onPressed: () => _openEditor(),
                backgroundColor: AppColors.accentGold,
                foregroundColor: Colors.black87,
                icon: const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: Colors.black87,
                ),
                label: Text(
                  'مستخدم جديد',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              )
            : null,
      ),
    );
  }

  Widget _buildEmptyState() {
    final gap = ScreenLayout.of(context).pageHorizontalGap;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gap),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'لا يوجد مستخدمون نشطون',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final canManageUsers =
                    context.watch<AuthProvider>().isOwner ||
                    context.watch<AuthProvider>().isAdmin;
                return Text(
                  canManageUsers
                      ? 'اضغط على زر الإضافة لإنشاء مستخدم جديد'
                      : 'سجّل دخول صاحب العمل أو المدير لإضافة مستخدمين',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user, AuthProvider auth) {
    final name = (user['displayName'] as String?)?.trim().isNotEmpty == true
        ? user['displayName'] as String
        : (user['username'] as String? ?? '—');
    final email = user['email'] as String? ?? '';
    final roleKey = user['role'] as String? ?? 'staff';
    final id = (user['id'] as num).toInt();
    final onlyOwnerProtected =
        roleKey == 'owner' && _protectedOwnerIds.contains(id);
    final canManageUsers = auth.isOwner || auth.isAdmin;
    final canEdit = canManageUsers && (auth.isOwner || roleKey == 'staff');
    final canDeactivate =
        canManageUsers &&
        !onlyOwnerProtected &&
        (auth.isOwner || roleKey == 'staff');
    final gap = ScreenLayout.of(context).pageHorizontalGap;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: gap, vertical: 8),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.accentGold.withValues(alpha: 0.12),
          child: Text(
            name.characters.first,
            style: TextStyle(
              color: AppColors.accentGold,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              email,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
            _roleBadge(roleKey),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            if (v == 'identity') _openIdentity(id);
            if (v == 'edit') _openEditor(existing: user);
            if (v == 'delete') _deactivate(user);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'identity', child: Text('بطاقة الهوية')),
            if (canEdit)
              const PopupMenuItem(value: 'edit', child: Text('تعديل')),
            if (canDeactivate)
              const PopupMenuItem(
                value: 'delete',
                child: Text('تعطيل', style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _roleBadge(String roleKey) {
    final role = _roleAr(roleKey);
    final color = switch (roleKey) {
      'owner' => const Color(0xFFB8960C),
      'admin' => AppColors.accentGold,
      _ => Colors.blueGrey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        role,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
