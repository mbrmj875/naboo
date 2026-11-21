import 'package:flutter/material.dart';

import '../services/wa_oil_followup_scheduler.dart';

/// إبلاغ الزبون بالتذكير عند الفاتورة. مفعّل افتراضيًا، ويُطفأ إذا رفض الزبون.
class WaReminderConsentTile extends StatelessWidget {
  const WaReminderConsentTile({
    super.key,
    required this.value,
    required this.prior,
    required this.onChanged,
  });

  final bool value;
  final WaRecipientConsentStatus prior;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final customerStopped =
        prior == WaRecipientConsentStatus.customerOptedOut;
    final String subtitle;
    if (customerStopped) {
      subtitle = 'طلب الزبون إيقاف التذكيرات. يعيدها بإرسال كلمة: تفعيل';
    } else if (prior == WaRecipientConsentStatus.staffDeclined) {
      subtitle = 'رفض الزبون التذكيرات سابقًا. فعّلها إذا وافق الآن';
    } else if (value) {
      subtitle = 'يصله التذكير في موعد الغيار القادم';
    } else {
      subtitle = 'لن يصله تذكير';
    }
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      value: customerStopped ? false : value,
      onChanged: customerStopped ? null : onChanged,
      title: const Text('أخبرت الزبون أنه ستصله رسائل تذكير على واتساب'),
      subtitle: Text(subtitle),
    );
  }
}
