import '../models/oil_change_campaign_recipient.dart';

/// متغيرات قالب رسالة الحملة.
abstract final class OilChangeCampaignTemplateVars {
  OilChangeCampaignTemplateVars._();

  static const name = '{الاسم}';
  static const car = '{السيارة}';
  static const lastVisit = '{آخر_زيارة}';
  static const store = '{المحل}';

  static const all = [name, car, lastVisit, store];
}

String renderOilChangeCampaignMessage({
  required String template,
  required OilChangeCampaignRecipient recipient,
  required String storeTitle,
}) {
  var out = template;
  out = out.replaceAll(OilChangeCampaignTemplateVars.name, recipient.customerName);
  out = out.replaceAll(OilChangeCampaignTemplateVars.car, recipient.displayCar);
  out = out.replaceAll(
    OilChangeCampaignTemplateVars.lastVisit,
    recipient.lastVisitLabel,
  );
  final shop = storeTitle.trim().isEmpty ? 'المحل' : storeTitle.trim();
  out = out.replaceAll(OilChangeCampaignTemplateVars.store, shop);
  return out;
}

String defaultOilChangeCampaignTemplate() {
  return 'مرحباً ${OilChangeCampaignTemplateVars.name}،\n'
      'نود تذكيركم بموعد غيار الزيت لسيارتكم ${OilChangeCampaignTemplateVars.car}. '
      'آخر زيارة: ${OilChangeCampaignTemplateVars.lastVisit}.\n'
      'نتشرف بزيارتكم في ${OilChangeCampaignTemplateVars.store}.';
}

bool oilChangeCampaignMessageMatchesSearch(
  OilChangeCampaignRecipient r,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  bool hit(String? v) => (v ?? '').toLowerCase().contains(q);
  return hit(r.customerName) ||
      hit(r.deviceName) ||
      hit(r.carModel) ||
      hit(r.engineSize) ||
      hit(r.phone);
}
