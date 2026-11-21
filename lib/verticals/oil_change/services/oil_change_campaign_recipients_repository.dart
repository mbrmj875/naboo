import '../../../services/database_helper.dart';
import '../../../services/service_orders_repository.dart';
import '../../../utils/app_logger.dart';
import '../models/oil_change_campaign_recipient.dart';
import '../utils/oil_change_order_status.dart';

/// يجلب مستلمي حملة واتساب — عميل واحد لكل هاتف (آخر زيارة).
class OilChangeCampaignRecipientsRepository {
  OilChangeCampaignRecipientsRepository._();

  static final OilChangeCampaignRecipientsRepository instance =
      OilChangeCampaignRecipientsRepository._();

  static const _pageSize = 120;
  static const _maxPages = 12;

  Future<List<OilChangeCampaignRecipient>> loadRecipients() async {
    await DatabaseHelper().ensureDefaultTenantSeedIfNeeded();
    await DatabaseHelper().ensureServiceOrdersReadRepair();

    final byPhone = <String, OilChangeCampaignRecipient>{};
    int? afterId;

    for (var page = 0; page < _maxPages; page++) {
      final rows = await ServiceOrdersRepository.instance.getOilChangeLogPage(
        afterId: afterId,
        limit: _pageSize,
        statusFilter: OilChangeLogStatusFilter.active,
      );
      if (rows.isEmpty) break;

      for (final row in rows) {
        final recipient = OilChangeCampaignRecipient.fromLogRow(row);
        if (recipient == null) continue;
        final key = OilChangeCampaignRecipient.phoneKey(recipient.phone);
        if (key.isEmpty) continue;
        byPhone.putIfAbsent(key, () => recipient);
      }

      if (rows.length < _pageSize) break;
      afterId = (rows.last['id'] as num?)?.toInt();
      if (afterId == null || afterId <= 0) break;
    }

    final list = byPhone.values.toList()
      ..sort((a, b) => b.orderId.compareTo(a.orderId));

    AppLogger.info(
      'oil_change_wa_campaign',
      'loaded ${list.length} unique recipients',
    );
    return list;
  }
}
