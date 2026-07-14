import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/business_features_provider.dart';
import '../../services/business_setup_settings.dart';
import '../../services/tenant_context_service.dart';
import '../models/owner_dashboard_access_context.dart';
import '../owner_dashboard_profile_resolver.dart';
import '../providers/owner_dashboard_studio_provider.dart';
import '../specs/owner_alert_settings_catalog.dart';
import '../specs/owner_dashboard_l10n_keys.dart';
import '../specs/owner_kpi_catalog.dart';
import '../specs/owner_kpi_catalog_entry.dart';
import '../specs/owner_dashboard_profile.dart';

/// ورقة إعدادات لوحة المالk — إظهار/إخفاء البطاقات + التنبيهات فقط.
Future<void> showOwnerDashboardLayoutSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(ctx).bottom,
            ),
            child: const _OwnerDashboardLayoutSheetBody(),
          ),
        ),
      );
    },
  );
}

class _OwnerDashboardLayoutSheetBody extends StatelessWidget {
  const _OwnerDashboardLayoutSheetBody();

  OwnerDashboardAccessContext _accessContext() {
    return OwnerDashboardAccessContext.fullAccess(
      tenantId: TenantContextService.instance.activeTenantId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final features = context.watch<BusinessFeaturesProvider>().data;
    final studio = context.watch<OwnerDashboardStudioProvider>();
    final access = _accessContext();

    if (!studio.loaded) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    final preset = OwnerDashboardProfileResolver.resolveForAccess(
      OwnerDashboardResolveInput(features: features, access: access),
    );

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'إعدادات لوحة المالك',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await studio.resetToDefaults(
                        features: features,
                        access: access,
                      );
                    },
                    child: const Text('استعادة الافتراضيات'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Text(
                      'إظهار وإخفاء البطاقات',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 8, end: 8, bottom: 8),
                    child: Text(
                      'جميع بطاقات لوحة المالk (v2 و v3) — أوقف التبديل لإخفاء بطاقة.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  _DashboardCardVisibilityList(
                    studio: studio,
                    features: features,
                    access: access,
                  ),
                  const SizedBox(height: 12),
                  _AlertThresholdsSection(
                    studio: studio,
                    features: features,
                    preset: preset.profile,
                  ),
                  const SizedBox(height: 8),
                  _AlertChannelsSection(
                    studio: studio,
                    features: features,
                    preset: preset.profile,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DashboardCardVisibilityList extends StatelessWidget {
  const _DashboardCardVisibilityList({
    required this.studio,
    required this.features,
    required this.access,
  });

  final OwnerDashboardStudioProvider studio;
  final BusinessSetupSettingsData features;
  final OwnerDashboardAccessContext access;

  List<String> _allCatalogIds() {
    return OwnerKpiCatalog.entriesFor(features: features, access: access)
        .map((e) => e.id)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final scope = _allCatalogIds();
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: scope.length,
      itemBuilder: (context, index) {
        final id = scope[index];
        final entry = OwnerKpiCatalog.kpiById(id);
        final title = entry != null
            ? ownerDashboardL10n(entry.titleKey)
            : id;
        return SwitchListTile(
          title: Text(title),
          value: studio.catalogCardIsVisible(id),
          onChanged: (v) => studio.setCatalogCardVisible(id, v),
        );
      },
    );
  }
}

class _AlertThresholdsSection extends StatelessWidget {
  const _AlertThresholdsSection({
    required this.studio,
    required this.features,
    required this.preset,
  });

  final OwnerDashboardStudioProvider studio;
  final BusinessSetupSettingsData features;
  final OwnerDashboardProfile preset;

  @override
  Widget build(BuildContext context) {
    final entries = OwnerAlertSettingsCatalog.entriesForProfile(
      preset,
      features: features,
    );
    if (entries.isEmpty) return const SizedBox.shrink();

    final thresholds = studio.alertSettings.thresholds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'عتبات التنبيه',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
        const Padding(
          padding: EdgeInsetsDirectional.only(start: 8, end: 8, bottom: 8),
          child: Text(
            'يُطبَّق على Action Rail والإشعارات السحابية — لا يظهر التنبيه إلا عند تجاوز العتبة.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        for (final entry in entries)
          if (entry.thresholdKey != null)
            Builder(
              builder: (context) {
                final key = entry.thresholdKey!;
                final value = OwnerAlertSettingsCatalog.readThresholdValue(
                  thresholds,
                  key,
                );
                return ListTile(
                  title: Text(entry.thresholdLabelAr ?? entry.titleAr),
                  subtitle: Text(entry.titleAr),
                  trailing: SizedBox(
                    width: 72,
                    child: TextFormField(
                      key: ValueKey('thr_${key}_$value'),
                      initialValue: '$value',
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onFieldSubmitted: (v) {
                        final n = int.tryParse(v.trim());
                        if (n == null) return;
                        studio.setAlertThresholdValue(key, n);
                      },
                    ),
                  ),
                );
              },
            ),
      ],
    );
  }
}

class _AlertChannelsSection extends StatelessWidget {
  const _AlertChannelsSection({
    required this.studio,
    required this.features,
    required this.preset,
  });

  final OwnerDashboardStudioProvider studio;
  final BusinessSetupSettingsData features;
  final OwnerDashboardProfile preset;

  @override
  Widget build(BuildContext context) {
    final alertIds = OwnerAlertSettingsCatalog.distinctAlertIds(
      preset,
      features: features,
    );
    if (alertIds.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            'قنوات الإشعار',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
        ),
        const Padding(
          padding: EdgeInsetsDirectional.only(start: 8, end: 8, bottom: 4),
          child: Text(
            'Push يُرسل من الخادم (FCM) وفق العتبات — التطبيق لا يولّد إشعاراً محلياً. '
            'عطّل Push للتنبيهات غير الحرجة لتقليل الإزعاج.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        for (final alertId in alertIds) ...[
          Builder(
            builder: (context) {
              final pref = studio.alertSettings.channels.forAlert(alertId);
              return Column(
                children: [
                  SwitchListTile(
                    title: Text(
                      OwnerAlertSettingsCatalog.alertTitleAr(alertId),
                    ),
                    subtitle: const Text('إظهار في Action Rail'),
                    value: pref.showInActionRail,
                    onChanged: (v) {
                      studio.setAlertChannelPref(
                        alertId,
                        pref.copyWith(showInActionRail: v),
                      );
                    },
                  ),
                  SwitchListTile(
                    title: Text(
                      'Push — ${OwnerAlertSettingsCatalog.alertTitleAr(alertId)}',
                    ),
                    subtitle: const Text('إشعار خارج التطبيق (FCM)'),
                    value: pref.enablePush,
                    onChanged: (v) {
                      studio.setAlertChannelPref(
                        alertId,
                        pref.copyWith(enablePush: v),
                      );
                    },
                  ),
                  const Divider(height: 1),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
