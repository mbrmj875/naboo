import '../models/pharmacy_owner_dashboard.dart';
import 'pharmacy_reports_repository.dart';

/// حساب KPIs لوحة المالك من [PharmacyReportsRepository].
class PharmacyKpiCalculator {
  PharmacyKpiCalculator({
    PharmacyReportsRepository? reportsRepo,
  }) : _reportsRepo = reportsRepo ?? PharmacyReportsRepository();

  final PharmacyReportsRepository _reportsRepo;

  Future<PharmacyOwnerDashboard> calculateDashboard({
    required int tenantId,
  }) {
    return _reportsRepo.loadOwnerDashboard(tenantId: tenantId);
  }
}
