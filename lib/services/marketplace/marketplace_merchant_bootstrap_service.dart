import 'package:supabase_flutter/supabase_flutter.dart';

import '../../utils/app_logger.dart';
import '../app_settings_repository.dart';
import '../business_setup_settings.dart';
import '../print_settings_repository.dart';
import '../tenant_context_service.dart';
import 'marketplace_catalog_sync_service.dart';
import 'marketplace_orders_service.dart';

/// يضمن وجود متجر Market مربوط ويرفع الكتالوج بعد تسجيل الدخول السحابي.
class MarketplaceMerchantBootstrapService {
  MarketplaceMerchantBootstrapService._();

  static final MarketplaceMerchantBootstrapService instance =
      MarketplaceMerchantBootstrapService._();

  final MarketplaceOrdersService _stores = MarketplaceOrdersService();
  bool _running = false;

  Future<void> ensureStoreAndSyncCatalog() async {
    if (_running) return;
    if (Supabase.instance.client.auth.currentUser == null) {
      return;
    }
    if (!await _marketBootstrapApplicable()) {
      return;
    }
    _running = true;
    try {
      if (!TenantContextService.instance.loaded) {
        await TenantContextService.instance.load();
      }

      var linked = await _stores.fetchLinkedStores();
      if (linked.isEmpty) {
        final name = await _resolveStoreName();
        await _stores.provisionStore(name: name);
        linked = await _stores.fetchLinkedStores();
        AppLogger.info(
          'MarketBootstrap',
          'provisioned store name=$name linked=${linked.length}',
        );
      }
      if (linked.isEmpty) {
        AppLogger.warn(
          'MarketBootstrap',
          'no linked store after provision — skip catalog sync',
        );
        return;
      }

      final result = await MarketplaceCatalogSyncService.instance.syncNow();
      if (result != null) {
        AppLogger.info(
          'MarketBootstrap',
          'catalog sync published=${result.published} skipped=${result.skipped}',
        );
      }
    } catch (e, st) {
      AppLogger.warn(
        'MarketBootstrap',
        'ensureStoreAndSyncCatalog failed: $e',
      );
      AppLogger.error('MarketBootstrap', 'ensureStoreAndSyncCatalog stack', e, st);
    } finally {
      _running = false;
    }
  }

  /// Market غير مفعّل لورش الزيوت — لا نُنشئ متجراً ولا نرفع كتالوجاً تلقائياً.
  Future<bool> _marketBootstrapApplicable() async {
    try {
      final settings = await BusinessSetupSettingsData.load(
        AppSettingsRepository.instance,
      );
      if (settings.businessVertical == BusinessVertical.oilChange) {
        return false;
      }
    } catch (e) {
      AppLogger.warn('MarketBootstrap', '_marketBootstrapApplicable: $e');
    }
    return true;
  }

  Future<String> _resolveStoreName() async {
    try {
      final print = await PrintSettingsRepository.instance.load();
      final fromPrint = print.storeTitleLine.trim();
      if (fromPrint.isNotEmpty && fromPrint != 'اسم المتجر') {
        return fromPrint;
      }
    } catch (_) {}

    if (TenantContextService.instance.loaded) {
      final tenants = TenantContextService.instance.tenants;
      if (tenants.isNotEmpty) {
        final name = tenants.first.name.trim();
        if (name.isNotEmpty && name != 'Default Tenant') {
          return name;
        }
      }
    }
    return 'متجري';
  }
}
