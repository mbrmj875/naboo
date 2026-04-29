import 'package:flutter/material.dart';

import '../../models/user_permission_catalog.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/database_helper.dart';
import '../../services/password_hashing.dart';
import '../../services/permission_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/screen_layout.dart';
import '../../utils/customer_validation.dart';

/// التحقق من هاتف عراقي شائع (اختياري): أرقام فقط، طول معقول.
String? _iraqPhoneOptional(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return null;
  final digits = t.replaceAll(RegExp(r'\D'), '');
  if (digits.length < 10 || digits.length > 11) {
    return 'استخدم صيغة هاتف عراقي (مثال: 07XXXXXXXXX)';
  }
  return null;
}

/// صفحة إضافة أو تعديل مستخدم — هوية التطبيق، صلاحيات مفصّلة، ربط بقاعدة البيانات.
class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key, this.existing});

  final Map<String, dynamic>? existing;

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _db = DatabaseHelper();
  final _perm = PermissionService.instance;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _phone2Ctrl;
  late final TextEditingController _jobCtrl;
  late final TextEditingController _passCtrl;
  late final TextEditingController _pass2Ctrl;

  String _role = 'staff';
  Map<String, bool> _permMap = {};
  bool _booting = true;
  bool _saving = false;

  final _groups = buildPermissionGroupsUi();

  bool get _isEdit => widget.existing != null;

  Color get _pageBg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _primary => Theme.of(context).colorScheme.primary;
  Color get _onPrimary => Theme.of(context).colorScheme.onPrimary;
  Color get _filterBg => Theme.of(context).colorScheme.surfaceContainerHighest;
  Color get _textPrimary => Theme.of(context).colorScheme.onSurface;
  Color get _textSecondary => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _outline => Theme.of(context).colorScheme.outline;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(
      text: e?['displayName']?.toString() ?? '',
    );
    _emailCtrl = TextEditingController(text: e?['email']?.toString() ?? '');
    _phoneCtrl = TextEditingController(text: e?['phone']?.toString() ?? '');
    _phone2Ctrl = TextEditingController(text: e?['phone2']?.toString() ?? '');
    _jobCtrl = TextEditingController(text: e?['jobTitle']?.toString() ?? '');
    _passCtrl = TextEditingController();
    _pass2Ctrl = TextEditingController();
    _role = (e?['role'] as String?) == 'admin' ? 'admin' : 'staff';

    if (_isEdit) {
      _loadPermsForEdit();
    } else {
      _permMap = _perm.defaultStaffPermissionMap();
      _booting = false;
    }
  }

  Future<void> _loadPermsForEdit() async {
    final id = widget.existing!['id'] as int;
    final role = widget.existing!['role'] as String? ?? 'staff';
    final m = await _perm.getUserPermissionMapForEdit(
      userId: id,
      roleKey: role,
    );
    if (!mounted) return;
    setState(() {
      _permMap = m;
      _booting = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _phone2Ctrl.dispose();
    _jobCtrl.dispose();
    _passCtrl.dispose();
    _pass2Ctrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration({
    required String label,
    String? hint,
    String? helper,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      filled: true,
      fillColor: _filterBg,
      isDense: true,
      prefixIcon: prefixIcon,
      border: OutlineInputBorder(
        borderRadius: AppShape.none,
        borderSide: BorderSide(color: _outline.withValues(alpha: 0.55)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppShape.none,
        borderSide: BorderSide(color: _outline.withValues(alpha: 0.55)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppShape.none,
        borderSide: BorderSide(color: _primary, width: 1.5),
      ),
    );
  }

  void _onRoleChanged(String? v) {
    final nv = v ?? 'staff';
    setState(() {
      _role = nv;
      if (nv == 'admin') {
        _permMap = {for (final k in PermissionKeys.allKeys) k: true};
      } else {
        _permMap = _perm.defaultStaffPermissionMap();
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('البريد مطلوب (يُستخدم كاسم دخول)')),
      );
      return;
    }
    final p1 = _iraqPhoneOptional(_phoneCtrl.text);
    final p2 = _iraqPhoneOptional(_phone2Ctrl.text);
    if (p1 != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(p1)));
      return;
    }
    if (p2 != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(p2)));
      return;
    }

    if (!_isEdit) {
      if (await _db.signupEmailTaken(email)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('هذا البريد مسجّل مسبقاً')),
          );
        }
        return;
      }
      if (!mounted) return;
      if (_passCtrl.text.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('كلمة المرور 6 أحرف على الأقل')),
        );
        return;
      }
      if (_passCtrl.text != _pass2Ctrl.text) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تأكيد كلمة المرور غير مطابق')),
        );
        return;
      }
    } else {
      final oldMail =
          (widget.existing!['email'] as String?)?.trim().toLowerCase() ?? '';
      if (email.toLowerCase() != oldMail && await _db.signupEmailTaken(email)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('هذا البريد مسجّل لمستخدم آخر')),
          );
        }
        return;
      }
      if (!mounted) return;
      if (_passCtrl.text.isNotEmpty) {
        if (_passCtrl.text.length < 6 || _passCtrl.text != _pass2Ctrl.text) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('كلمة المرور غير صالحة أو التأكيد غير مطابق'),
            ),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final id = widget.existing!['id'] as int;
        String? hash;
        String? salt;
        if (_passCtrl.text.isNotEmpty) {
          salt = PasswordHashing.generateSalt();
          hash = PasswordHashing.hash(_passCtrl.text, salt);
        }
        await _db.updateUserAdminBasic(
          id: id,
          displayName: _nameCtrl.text.trim(),
          email: email,
          phone: _phoneCtrl.text.trim(),
          phone2: _phone2Ctrl.text.trim(),
          jobTitle: _jobCtrl.text.trim(),
          role: _role,
          passwordHash: hash,
          passwordSalt: salt,
        );
        await _syncPermissions(id);
        CloudSyncService.instance.scheduleSyncSoon();
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        final salt = PasswordHashing.generateSalt();
        final hash = PasswordHashing.hash(_passCtrl.text, salt);
        final id = await _db.insertUserByAdmin(
          username: email.toLowerCase(),
          passwordHash: hash,
          passwordSalt: salt,
          role: _role,
          email: email,
          phone: _phoneCtrl.text.trim(),
          phone2: _phone2Ctrl.text.trim(),
          displayName: _nameCtrl.text.trim(),
          jobTitle: _jobCtrl.text.trim(),
        );
        await _syncPermissions(id);
        CloudSyncService.instance.scheduleSyncSoon();
        if (!mounted) return;
        Navigator.pop(context, id);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _syncPermissions(int userId) async {
    if (_role == 'admin') {
      await _perm.clearUserPermissionOverrides(userId);
    } else {
      await _perm.replaceUserPermissions(userId: userId, permissions: _permMap);
    }
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _primary,
      foregroundColor: _onPrimary,
      elevation: 0,
      centerTitle: false,
      title: Text(
        _isEdit ? 'تعديل مستخدم' : 'مستخدم جديد',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: _pageBg,
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildAppBar(),
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          ),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _pageBg,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAppBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _sectionCard(
                            icon: Icons.person_outline,
                            title: 'بيانات الحساب',
                            subtitle:
                                'البريد يُستخدم كاسم دخول. الهاتف بصيغة عراقية شائعة (07…).',
                            children: [
                              TextFormField(
                                controller: _nameCtrl,
                                decoration: _decoration(
                                  label: 'الاسم الكامل',
                                  prefixIcon: Icon(
                                    Icons.badge_outlined,
                                    color: _textSecondary,
                                    size: 22,
                                  ),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'مطلوب'
                                    : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _jobCtrl,
                                decoration: _decoration(
                                  label: 'الدور الوظيفي',
                                  hint: 'كاشير، مخزن، …',
                                  prefixIcon: Icon(
                                    Icons.work_outline,
                                    color: _textSecondary,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _emailCtrl,
                                enabled: !_isEdit,
                                keyboardType: TextInputType.emailAddress,
                                decoration: _decoration(
                                  label: 'البريد الإلكتروني (اسم الدخول)',
                                  prefixIcon: Icon(
                                    Icons.email_outlined,
                                    color: _textSecondary,
                                    size: 22,
                                  ),
                                ),
                                validator: (v) {
                                  final t = v?.trim() ?? '';
                                  if (t.isEmpty) return 'مطلوب';
                                  return CustomerValidation.optionalEmail(v);
                                },
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                decoration: _decoration(
                                  label: 'رقم الهاتف (العراق)',
                                  hint: '07XXXXXXXXX',
                                  helper: 'أرقام عراقية شائعة تبدأ بـ 07',
                                  prefixIcon: Icon(
                                    Icons.phone_android_outlined,
                                    color: _textSecondary,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _phone2Ctrl,
                                keyboardType: TextInputType.phone,
                                decoration: _decoration(
                                  label: 'هاتف ثانٍ (اختياري)',
                                  hint: 'إن وُجد',
                                  prefixIcon: Icon(
                                    Icons.phone_in_talk_outlined,
                                    color: _textSecondary,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _sectionCard(
                            icon: Icons.lock_outline,
                            title: 'الصلاحية وكلمة المرور',
                            children: [
                              DropdownButtonFormField<String>(
                                key: ValueKey<String>(_role),
                                initialValue: _role,
                                decoration: _decoration(
                                  label: 'نوع الحساب',
                                  prefixIcon: Icon(
                                    Icons.admin_panel_settings_outlined,
                                    color: _textSecondary,
                                    size: 22,
                                  ),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'staff',
                                    child: Text('موظف (صلاحيات مفصّلة)'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'admin',
                                    child: Text('مدير (كل الصلاحيات)'),
                                  ),
                                ],
                                onChanged: _saving ? null : _onRoleChanged,
                              ),
                              if (_role == 'admin') ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _primary.withValues(alpha: 0.08),
                                    border: Border.all(
                                      color: _primary.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.info_outline, color: _primary),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          'حساب المدير يتجاوز القيود التفصيلية ويُطبَّق عليه السماح الكامل في النظام.',
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: _textSecondary,
                                            height: 1.35,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _passCtrl,
                                obscureText: true,
                                decoration: _decoration(
                                  label: _isEdit
                                      ? 'كلمة مرور جديدة (اختياري)'
                                      : 'كلمة المرور',
                                  prefixIcon: Icon(
                                    Icons.password_outlined,
                                    color: _textSecondary,
                                    size: 22,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _pass2Ctrl,
                                obscureText: true,
                                decoration: _decoration(
                                  label: _isEdit
                                      ? 'تأكيد كلمة المرور الجديدة'
                                      : 'تأكيد كلمة المرور',
                                  prefixIcon: Icon(
                                    Icons.verified_user_outlined,
                                    color: _textSecondary,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_role == 'staff') ...[
                            const SizedBox(height: 16),
                            _sectionCard(
                              icon: Icons.rule_folder_outlined,
                              title: 'الصلاحيات التفصيلية',
                              subtitle:
                                  'فعّل ما يحق لهذا الموظف الوصول إليه. يُحفظ في قاعدة البيانات لكل مستخدم.',
                              children: [
                                for (final g in _groups) ...[
                                  _permExpansion(g),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ],
                          const SizedBox(height: 28),
                          FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: Text(
                              _saving ? 'جاري الحفظ…' : 'حفظ',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: _primary,
                              foregroundColor: _onPrimary,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              shape: const RoundedRectangleBorder(
                                borderRadius: AppShape.none,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _saving
                                ? null
                                : () => Navigator.pop(context),
                            child: const Text('إلغاء'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: AppShape.none,
        border: Border.all(color: _outline.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: _primary, size: 26),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _textPrimary,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: _outline.withValues(alpha: 0.28)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _permExpansion(PermissionGroupUi g) {
    return Container(
      decoration: BoxDecoration(
        color: _filterBg.withValues(alpha: 0.65),
        border: Border.all(color: _outline.withValues(alpha: 0.35)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        childrenPadding: EdgeInsetsDirectional.only(
          bottom: 8,
          start: ScreenLayout.of(context).pageHorizontalGap * 0.5,
          end: ScreenLayout.of(context).pageHorizontalGap * 0.5,
        ),
        title: Text(
          g.title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
        ),
        children: [
          for (final it in g.items)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                it.label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                ),
              ),
              subtitle: it.subtitle == null
                  ? null
                  : Text(
                      it.subtitle!,
                      style: TextStyle(fontSize: 11.5, color: _textSecondary),
                    ),
              value: _permMap[it.key] ?? false,
              activeThumbColor: _onPrimary,
              activeTrackColor: _primary.withValues(alpha: 0.5),
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _permMap[it.key] = v),
            ),
        ],
      ),
    );
  }
}
