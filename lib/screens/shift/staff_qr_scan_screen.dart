import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../utils/staff_identity_qr.dart' show StaffIdentityQr, StaffQrData;

/// شاشة ملء الشاشة لمسح QR بطاقة الموظف (فتح/إغلاق الوردية).
class StaffQrScanScreen extends StatefulWidget {
  const StaffQrScanScreen({super.key});

  @override
  State<StaffQrScanScreen> createState() => _StaffQrScanScreenState();
}

class _StaffQrScanScreenState extends State<StaffQrScanScreen> {
  final MobileScannerController _ctrl = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final b in capture.barcodes) {
      final raw = b.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final parsed = StaffIdentityQr.tryParse(raw);
      if (parsed != null && mounted) {
        _handled = true;
        Navigator.of(context).pop<StaffQrData>(parsed);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مسح بطاقة الموظف'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Stack(
          children: [
            MobileScanner(
              controller: _ctrl,
              onDetect: _onDetect,
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'وجّه الكاميرا نحو رمز QR على بطاقة الهوية.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
