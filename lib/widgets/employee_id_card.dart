import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../utils/staff_identity_qr.dart';

/// بطاقة هوية موظف (وجه واحد): QR فقط + بيانات نصية (بدون باركود خطّي).
class EmployeeIdCard extends StatelessWidget {
  const EmployeeIdCard({
    super.key,
    required this.user,
    this.width = 320,
    this.compact = false,
  });

  final Map<String, dynamic> user;
  final double width;
  final bool compact;

  static String _roleLabel(String? key) {
    switch (key) {
      case 'admin':
        return 'مدير النظام';
      case 'staff':
      default:
        return 'موظف';
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = user['id'] as int? ?? 0;
    final name = (user['displayName'] as String?)?.trim().isNotEmpty == true
        ? user['displayName'] as String
        : (user['username'] as String? ?? '—');
    final email = user['email'] as String? ?? '';
    final phone = user['phone'] as String? ?? '';
    final roleKey = user['role'] as String? ?? 'staff';
    final job = (user['jobTitle'] as String?)?.trim() ?? '';
    final pin = (user['shiftAccessPin'] as String?)?.trim() ?? '';
    final createdRaw = user['createdAt'] as String?;
    final created = createdRaw != null
        ? DateTime.tryParse(createdRaw)
        : null;
    final createdStr = created != null
        ? DateFormat('yyyy-MM-dd', 'en').format(created.toLocal())
        : '—';

    final qrPayload = StaffIdentityQr.encode(userId: id, pin: pin);

    final h = compact ? width * 0.52 : width * 0.58;
    final border = Theme.of(context).colorScheme.outline.withValues(alpha: 0.5);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        width: width,
        constraints: BoxConstraints(minHeight: h),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: border, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: EdgeInsets.all(compact ? 10 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'هوية موظف',
                    style: TextStyle(
                      fontSize: compact ? 13 : 15,
                      fontWeight: FontWeight.w900,
                      color: Colors.blueGrey.shade900,
                    ),
                  ),
                ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    '#$id',
                    style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
            Divider(height: compact ? 12 : 16, color: border),
            _line(Icons.person_outline, 'الاسم', name, compact),
            _line(Icons.work_outline, 'الدور الوظيفي', job.isEmpty ? '—' : job, compact),
            _line(Icons.badge_outlined, 'الصلاحية', _roleLabel(roleKey), compact),
            _line(Icons.phone_android, 'الهاتف', phone.isEmpty ? '—' : phone, compact),
            _line(Icons.email_outlined, 'البريد', email.isEmpty ? '—' : email, compact),
            _line(Icons.event, 'تاريخ الإنشاء', createdStr, compact),
            if (!compact) ...[
              const SizedBox(height: 6),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  'رمز الوردية: $pin',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.teal.shade900,
                  ),
                ),
              ),
            ],
            SizedBox(height: compact ? 8 : 10),
            Center(
              child: BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: qrPayload,
                width: compact ? 96 : 118,
                height: compact ? 96 : 118,
                drawText: false,
                color: Colors.black,
              ),
            ),
            if (!compact)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'QR فقط: كاميرا التطبيق، أو جهاز قراءة خارجي (USB/Bluetooth) يوجّه على البطاقة مع التركيز على حقل «جهاز القراءة» في نافذة فتح/إغلاق الوردية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.3),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Widget _line(IconData icon, String label, String value, bool compact) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: compact ? 15 : 17, color: Colors.blueGrey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: compact ? 9 : 10,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: compact ? 11 : 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
