import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/print_settings_data.dart';
import '../models/staff_branch_profile.dart';
import '../providers/auth_provider.dart';
import 'print_settings_repository.dart';
import 'staff_branch_profile_repository.dart';

/// يختار بيانات المتجر الظاهرة على واتساب والإيصال حسب المستخدم الحالي.
///
/// - صاحب العمل → بيانات المتجر العامة دائماً.
/// - موظف عبّأ اسم فرعه → بياناته فوق إعدادات الطباعة العامة.
/// - موظف بلا بيانات → احتياطي بيانات المتجر العامة.
class EffectiveStoreBranding {
  EffectiveStoreBranding._();

  /// دمج ملف فرع الموظف فوق إعدادات الطباعة (هوية فقط، بلا لمس تفضيلات الطابعة).
  static PrintSettingsData merge({
    required PrintSettingsData base,
    required StaffBranchProfile profile,
    required bool isOwner,
  }) {
    if (isOwner || !profile.hasIdentity) return base;
    return base.copyWith(
      storeTitleLine: profile.storeTitleLine,
      storeAddress: profile.storeAddress,
      storePhones: profile.storePhones,
      storeLogoBase64: profile.storeLogoBase64,
      storeLatitude: profile.storeLatitude,
      storeLongitude: profile.storeLongitude,
      clearStoreLocation: !profile.hasStoreLocation,
    );
  }

  static Future<PrintSettingsData> resolveFromContext(
    BuildContext context, {
    PrintSettingsData? base,
    bool fallbackToWorkspace = true,
  }) {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    return resolve(
      isOwner: auth.isOwner,
      userGlobalId: auth.userGlobalId,
      userId: auth.userId,
      base: base,
      fallbackToWorkspace: fallbackToWorkspace,
    );
  }

  static Future<PrintSettingsData> resolve({
    required bool isOwner,
    String? userGlobalId,
    int? userId,
    PrintSettingsData? base,
    /// عند false: موظف بلا بيانات فرع يرى حقولاً فارغة (بطاقة الإعدادات)
    /// بدل بيانات متجر صاحب العمل — حتى يظهر أن لكل موظف بياناته.
    bool fallbackToWorkspace = true,
  }) async {
    final workspace =
        base ?? await PrintSettingsRepository.instance.load();
    if (isOwner) return workspace;

    final profile = await StaffBranchProfileRepository.instance.loadForUser(
      userGlobalId: userGlobalId,
      userId: userId,
    );
    if (!profile.hasIdentity) {
      if (fallbackToWorkspace) return workspace;
      return workspace.copyWith(
        storeTitleLine: '',
        storeAddress: '',
        storePhones: const <String>[],
        storeLogoBase64: '',
        clearStoreLocation: true,
      );
    }
    return merge(base: workspace, profile: profile, isOwner: false);
  }
}
