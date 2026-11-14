import '../models/pharmacy_rx_schedule.dart';

/// يكتشف كميات كبيرة لأدوية monitored/Rx.
class OverdoseDetector {
  const OverdoseDetector({this.monitoredThreshold = 100});

  final double monitoredThreshold;

  bool isOverdose({
    required String rxSchedule,
    required double qty,
  }) {
    if (qty < monitoredThreshold) return false;
    return rxSchedule == PharmacyRxSchedule.monitored ||
        rxSchedule == PharmacyRxSchedule.rx;
  }
}
