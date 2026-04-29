import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../utils/screen_layout.dart';
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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _db.listActiveUsers();
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = [];
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
      case 'admin':
        return 'مدير';
      default:
        return 'موظف';
    }
  }

  Future<void> _openEditor({Map<String, dynamic>? existing}) async {
    final auth = context.read<AuthProvider>();
    if (!auth.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا صلاحية — المدير فقط يضيف أو يعدّل المستخدمين'),
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
    if (!auth.isAdmin) return;
    final id = row['id'] as int;
    if (id == auth.userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يمكن تعطيل حسابك وأنت مسجّل الدخول')),
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
    await _db.deactivateUser(id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم التعطيل')));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    final cs = Theme.of(context).colorScheme;
    final gap = ScreenLayout.of(context).pageHorizontalGap;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text(
            'المستخدمون',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
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
        floatingActionButton: auth.isAdmin
            ? FloatingActionButton.extended(
                onPressed: () => _openEditor(),
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                icon: Icon(
                  Icons.person_add_alt_1_outlined,
                  color: cs.onPrimary,
                ),
                label: Text(
                  'مستخدم جديد',
                  style: TextStyle(
                    color: cs.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
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
                final admin = context.watch<AuthProvider>().isAdmin;
                return Text(
                  admin
                      ? 'اضغط على زر الإضافة لإنشاء مستخدم جديد'
                      : 'سجّل دخول المدير لإضافة مستخدمين',
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
    final primary = Theme.of(context).colorScheme.primary;
    final name = (user['displayName'] as String?)?.trim().isNotEmpty == true
        ? user['displayName'] as String
        : (user['username'] as String? ?? '—');
    final email = user['email'] as String? ?? '';
    final roleKey = user['role'] as String? ?? 'staff';
    final gap = ScreenLayout.of(context).pageHorizontalGap;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
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
          backgroundColor: primary.withValues(alpha: 0.12),
          child: Text(
            name.characters.first,
            style: TextStyle(
              color: primary,
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
            _roleBadge(_roleAr(roleKey)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            final id = user['id'] as int;
            if (v == 'identity') _openIdentity(id);
            if (v == 'edit') _openEditor(existing: user);
            if (v == 'delete') _deactivate(user);
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'identity', child: Text('بطاقة الهوية')),
            if (auth.isAdmin)
              const PopupMenuItem(value: 'edit', child: Text('تعديل')),
            if (auth.isAdmin)
              const PopupMenuItem(
                value: 'delete',
                child: Text('تعطيل', style: TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _roleBadge(String role) {
    final color = role == 'مدير' ? Colors.purple : Colors.blue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.zero,
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
