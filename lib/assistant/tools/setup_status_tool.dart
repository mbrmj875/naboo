import '../../guides/guide_tour.dart';
import '../../navigation/content_navigation.dart';
import '../../printing/printer_connection.dart';
import '../../services/database_helper.dart';
import '../../services/permission_service.dart';
import '../../verticals/oil_change/services/oil_change_oil_catalog_repository.dart';
import '../../verticals/oil_change/services/oil_change_settings.dart';
import '../../verticals/oil_change/services/oil_change_whatsapp_status_store.dart';
import '../assistant_tool.dart';
import '../assistant_tool_result.dart';

/// خطوة تجهيز واحدة وكيف يُرشَد إليها (ق30، م3-9ب).
class SetupItem {
  const SetupItem(this.key, this.title, {required this.done, this.tourId, this.routeId, this.detail});

  final String key;
  final String title;
  final bool done;
  final String? tourId;
  final String? routeId;
  final String? detail;

  Map<String, Object?> toRow() => {
    'key': key,
    'title': title,
    'done': done,
    'tour_id': ?tourId,
    'route_id': ?routeId,
    'detail': ?detail,
  };
}

/// مصدر الحالة؛ منفصل حتى يُختبر الترتيب بلا قاعدة.
abstract class SetupStatusSource {
  Future<int> oilCatalogCount();
  Future<int> basePriceFils();
  Future<int> activeUsers();
  Future<bool> whatsappConnected();
  Future<bool> printerConfigured();
}

class DeviceSetupStatusSource implements SetupStatusSource {
  const DeviceSetupStatusSource();

  @override
  Future<int> oilCatalogCount() async => (await OilChangeOilCatalogRepository.instance.listActive()).length;

  @override
  Future<int> basePriceFils() => OilChangeSettings.getBaseOilChangePriceFils();

  @override
  Future<int> activeUsers() => DatabaseHelper().countActiveUsers();

  @override
  Future<bool> whatsappConnected() async =>
      await OilChangeWhatsappStatusStore.instance.readStatus() == OilChangeWhatsappGatewayStatus.connected;

  @override
  Future<bool> printerConfigured() async => (await PrinterConnection.load()).isConfigured;
}

/// الخمسة بالترتيب كما في الخطة: الزيوت، أجرة الغيار، الموظفون، واتساب، الطابعة.
Future<List<SetupItem>> readSetupStatus(SetupStatusSource src) async {
  Future<T> safe<T>(Future<T> Function() f, T fallback) async {
    try {
      return await f().timeout(const Duration(seconds: 4));
    } catch (_) {
      return fallback;
    }
  }

  final oils = await safe(src.oilCatalogCount, 0);
  final base = await safe(src.basePriceFils, 0);
  final users = await safe(src.activeUsers, 1);
  final wa = await safe(src.whatsappConnected, false);
  final printer = await safe(src.printerConfigured, false);
  return [
    SetupItem('oil_catalog', 'زيوت الكتالوج', done: oils > 0, tourId: GuideTourIds.oilCatalogOil, detail: '$oils زيت'),
    SetupItem('base_price', 'أجرة الغيار الأساسية', done: base > 0, tourId: GuideTourIds.oilServicesBase),
    // المالك نفسه مستخدم: الموظفون موجودون إن زاد العدد عن واحد.
    SetupItem('staff', 'الموظفون', done: users > 1, tourId: GuideTourIds.usersAddStaff, detail: '${users - 1} موظف'),
    SetupItem('whatsapp', 'ربط واتساب', done: wa, tourId: GuideTourIds.oilWhatsapp),
    SetupItem('printer', 'الطابعة', done: printer, routeId: AppContentRoutes.printing),
  ];
}

/// `setup_status`: للمالك (أو من يملك إعدادات المحل) حين يطلب «جهّز محلي معي».
class SetupStatusTool extends AssistantTool {
  const SetupStatusTool([this.source = const DeviceSetupStatusSource()]);

  final SetupStatusSource source;

  @override
  String get name => 'setup_status';

  @override
  List<String> get requiredPermissions => const [PermissionKeys.settingsApp];

  @override
  bool get guideLevel => true;

  @override
  Future<AssistantToolResult> run(Map<String, Object?> args, AssistantToolContext ctx) async {
    final items = await readSetupStatus(source);
    final missing = items.where((i) => !i.done).map((i) => i.key).toList();
    return AssistantToolResult.success(
      name,
      [for (final i in items) i.toRow()],
      source: 'من إعدادات جهازك',
      extra: {'missing_in_order': missing, 'complete': missing.isEmpty},
    );
  }
}
