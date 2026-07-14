import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../models/user_permission_catalog.dart';
import '../../services/database_helper.dart';
import '../../services/password_hashing.dart';
import '../../services/permission_service.dart';
import '../../theme/design_tokens.dart';
import '../../utils/pin_input_constraints.dart';
import '../../utils/screen_layout.dart';
import '../../widgets/inputs/pin_four_boxes_field.dart';

/// صفحة إضافة أو تعديل مستخدم — مبسّطة: اسم + رمز PIN + مستوى صلاحية.
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
  late final TextEditingController _pinCtrl;
  late final TextEditingController _pin2Ctrl;

  /// true = كامل التخصيص (كل الصلاحيات), false = محدود (صلاحيات افتراضية)
  bool _fullAccess = false;

  Map<String, bool> _permMap = {};
  bool _booting = true;
  bool _saving = false;
  bool _showPin = false;
  bool _showPin2 = false;

  /// التخصيص المتقدم — يُفتح فقط عند اختيار "تخصيص يدوي"
  bool _showAdvancedPerms = false;

  final _groups = buildPermissionGroupsUi();

  bool get _isEdit => widget.existing != null;

  Color get _pageBg => Theme.of(context).scaffoldBackgroundColor;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _primary => Theme.of(context).colorScheme.primary;
  Color get _onPrimary => Theme.of(context).colorScheme.onPrimary;
  Color get _filterBg =>
      Theme.of(context).colorScheme.surfaceContainerHighest;
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
    _pinCtrl = TextEditingController();
    _pin2Ctrl = TextEditingController();

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
    // تحديد ما إذا كانت الصلاحيات كاملة
    final allTrue = m.values.every((v) => v);
    setState(() {
      _permMap = m;
      _fullAccess = allTrue;
      _booting = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _pin2Ctrl.dispose();
    super.dispose();
  }

  InputDecoration _decoration({
    required String label,
    String? hint,
    String? helper,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      filled: true,
      fillColor: _filterBg,
      isDense: true,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
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

  /// يولّد username فريد من الاسم (بدون مسافات، أحرف صغيرة + رقم عشوائي)
  String _generateUsername(String name) {
    final base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^\w\u0600-\u06FF]'), '');
    final suffix = DateTime.now().millisecondsSinceEpoch % 10000;
    return '${base.isEmpty ? 'user' : base}_$suffix';
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الاسم مطلوب')),
      );
      return;
    }

    // التحقق من رمز PIN
    if (!_isEdit) {
      if (!PinInputConstraints.isValid(_pinCtrl.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(PinInputConstraints.invalidMessage)),
        );
        return;
      }
      if (!PinInputConstraints.matches(_pinCtrl.text, _pin2Ctrl.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(PinInputConstraints.mismatchMessage)),
        );
        return;
      }
    } else {
      if (_pinCtrl.text.isNotEmpty) {
        if (!PinInputConstraints.matches(_pinCtrl.text, _pin2Ctrl.text)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(PinInputConstraints.mismatchMessage),
            ),
          );
          return;
        }
      }
    }

    // تطبيق مستوى الصلاحية
    if (_fullAccess && !_showAdvancedPerms) {
      _permMap = {
        for (final k in PermissionKeys.allKeys) k: true,
      };
    } else if (!_fullAccess && !_showAdvancedPerms) {
      _permMap = _perm.defaultStaffPermissionMap();
    }
    // إذا _showAdvancedPerms فإن _permMap يحتوي على التخصيص اليدوي

    setState(() => _saving = true);
    try {
      if (_isEdit) {
        final id = widget.existing!['id'] as int;
        String? hash;
        String? salt;
        if (_pinCtrl.text.isNotEmpty) {
          salt = PasswordHashing.generateSalt();
          hash = await PasswordHashing.hashPin(_pinCtrl.text, salt);
        }
        final auth = context.read<AuthProvider>();
        await _db.updateUserAdminBasic(
          id: id,
          displayName: name,
          email: widget.existing!['email']?.toString() ?? '',
          phone: widget.existing!['phone']?.toString() ?? '',
          phone2: widget.existing!['phone2']?.toString() ?? '',
          jobTitle: widget.existing!['jobTitle']?.toString() ?? '',
          role: 'staff',
          passwordHash: hash,
          passwordSalt: salt,
          actingUserId: auth.userId,
          actingRoleKey: auth.roleKey,
        );
        await _syncPermissions(id);
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        final salt = PasswordHashing.generateSalt();
        final hash = await PasswordHashing.hashPin(_pinCtrl.text, salt);
        final auth = context.read<AuthProvider>();
        final username = _generateUsername(name);
        final id = await _db.insertUserByAdmin(
          username: username,
          passwordHash: hash,
          passwordSalt: salt,
          role: 'staff',
          email: '',
          phone: '',
          phone2: '',
          displayName: name,
          jobTitle: '',
          actingRoleKey: auth.roleKey,
        );
        await _syncPermissions(id);
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
    await _perm.replaceUserPermissions(userId: userId, permissions: _permMap);
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
                          // ── 1. الاسم ──
                          _sectionCard(
                            icon: Icons.person_outline,
                            title: 'بيانات الموظف',
                            children: [
                              TextFormField(
                                controller: _nameCtrl,
                                decoration: _decoration(
                                  label: 'الاسم',
                                  hint: 'اسم الموظف',
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
                            ],
                          ),

                          const SizedBox(height: 16),

                          // ── 2. رمز PIN ──
                          _sectionCard(
                            icon: Icons.pin_outlined,
                            title: 'رمز الدخول (PIN)',
                            subtitle: PinInputConstraints.staffSubtitle,
                            children: [
                              PinFourBoxesField(
                                controller: _pinCtrl,
                                label: _isEdit
                                    ? 'رمز PIN جديد (اختياري)'
                                    : 'رمز PIN',
                                obscureText: !_showPin,
                                onToggleObscure: () =>
                                    setState(() => _showPin = !_showPin),
                                validator: _isEdit
                                    ? PinInputConstraints.validateOptional
                                    : PinInputConstraints.validateRequired,
                              ),
                              const SizedBox(height: 14),
                              PinFourBoxesField(
                                controller: _pin2Ctrl,
                                label: 'تأكيد رمز PIN',
                                obscureText: !_showPin2,
                                onToggleObscure: () =>
                                    setState(() => _showPin2 = !_showPin2),
                                validator: (v) {
                                  if (_isEdit && _pinCtrl.text.isEmpty) {
                                    return null;
                                  }
                                  if (!PinInputConstraints.isValid(v ?? '')) {
                                    return PinInputConstraints.invalidMessage;
                                  }
                                  if (v != _pinCtrl.text) {
                                    return PinInputConstraints.mismatchMessage;
                                  }
                                  return null;
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // ── 3. مستوى الصلاحية ──
                          _sectionCard(
                            icon: Icons.security_outlined,
                            title: 'مستوى الصلاحية',
                            children: [
                              _accessLevelTile(
                                title: 'موظف محدود التخصيص',
                                subtitle:
                                    'صلاحيات أساسية فقط (نقطة بيع، عرض المخزون، الصندوق)',
                                icon: Icons.shield_outlined,
                                selected: !_fullAccess && !_showAdvancedPerms,
                                onTap: () => setState(() {
                                  _fullAccess = false;
                                  _showAdvancedPerms = false;
                                  _permMap = _perm.defaultStaffPermissionMap();
                                }),
                              ),
                              const SizedBox(height: 8),
                              _accessLevelTile(
                                title: 'موظف كامل التخصيص',
                                subtitle:
                                    'جميع الصلاحيات (تقارير، إدارة مخزون، عملاء، إعدادات)',
                                icon: Icons.admin_panel_settings_outlined,
                                selected: _fullAccess && !_showAdvancedPerms,
                                onTap: () => setState(() {
                                  _fullAccess = true;
                                  _showAdvancedPerms = false;
                                  _permMap = {
                                    for (final k in PermissionKeys.allKeys)
                                      k: true,
                                  };
                                }),
                              ),
                              const SizedBox(height: 8),
                              _accessLevelTile(
                                title: 'تخصيص يدوي',
                                subtitle:
                                    'اختر الصلاحيات بنفسك واحدة تلو الأخرى',
                                icon: Icons.tune_outlined,
                                selected: _showAdvancedPerms,
                                onTap: () => setState(() {
                                  _showAdvancedPerms = true;
                                }),
                              ),
                            ],
                          ),

                          // ── تفاصيل الصلاحيات (تظهر فقط عند تخصيص يدوي) ──
                          if (_showAdvancedPerms) ...[
                            const SizedBox(height: 16),
                            _sectionCard(
                              icon: Icons.rule_folder_outlined,
                              title: 'الصلاحيات التفصيلية',
                              subtitle:
                                  'فعّل ما يحق لهذا الموظف الوصول إليه.',
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

  Widget _accessLevelTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected
          ? _primary.withValues(alpha: 0.12)
          : _filterBg.withValues(alpha: 0.5),
      child: InkWell(
        onTap: _saving ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? _primary
                  : _outline.withValues(alpha: 0.35),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? _primary : _textSecondary,
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: selected ? _primary : _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle, color: _primary, size: 22),
            ],
          ),
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
