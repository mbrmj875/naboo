import '../models/pharmacy_batch.dart';
import '../models/pharmacy_drug_reference.dart';
import '../models/pharmacy_manufacturer.dart';
import '../models/pharmacy_substitute_candidate.dart';

/// بيانات جاهزة للعرض في لوحة POS — بدون async.
class PharmacyPosDrugPanelData {
  const PharmacyPosDrugPanelData({
    required this.productName,
    required this.drugReference,
    this.manufacturer,
    this.strengthText,
    required this.rxSchedule,
    required this.selectedBatch,
    required this.substitutes,
    required this.available,
    this.latestExpiry,
  });

  final String productName;
  final PharmacyDrugReference drugReference;
  final PharmacyManufacturer? manufacturer;
  final String? strengthText;
  final String rxSchedule;
  final PharmacyBatch? selectedBatch;
  final List<PharmacySubstituteCandidate> substitutes;
  final bool available;
  final DateTime? latestExpiry;
}
