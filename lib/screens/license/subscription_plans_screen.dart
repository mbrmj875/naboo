import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/license_service.dart';

const Color _kAccent  = Color(0xFF1E3A5F);
const Color _kGold    = Color(0xFFB8860B);
const Color _kSilver  = Color(0xFF607D8B);

class SubscriptionPlansScreen extends StatelessWidget {
  const SubscriptionPlansScreen({
    super.key,
    this.currentPlan,
    this.highlightPlan,
  });

  final SubscriptionPlan? currentPlan;
  final SubscriptionPlan? highlightPlan;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1B2A),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text(
            'خطط الاشتراك',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          child: Column(
            children: [
              // ── العنوان ──────────────────────────────────────────────────
              const Text(
                'اختر الخطة المناسبة لنشاطك',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'جميع الخطط تشمل تجربة مجانية 15 يوم',
                style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
              ),
              const SizedBox(height: 28),

              // ── البطاقات ─────────────────────────────────────────────────
              _PlanCard(
                plan:        SubscriptionPlan.basic,
                isPopular:   false,
                isCurrent:   currentPlan?.key == 'basic',
                accentColor: _kSilver,
                icon:        Icons.store_outlined,
              ),
              const SizedBox(height: 16),
              _PlanCard(
                plan:        SubscriptionPlan.pro,
                isPopular:   true,
                isCurrent:   currentPlan?.key == 'pro',
                accentColor: _kAccent,
                icon:        Icons.business_outlined,
              ),
              const SizedBox(height: 16),
              _PlanCard(
                plan:        SubscriptionPlan.unlimited,
                isPopular:   false,
                isCurrent:   currentPlan?.key == 'unlimited',
                accentColor: _kGold,
                icon:        Icons.all_inclusive_outlined,
              ),

              const SizedBox(height: 32),

              // ── معلومات الدفع ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.white70, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'كيفية الاشتراك',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '١. تواصل مع فريق NaBoo عبر الطرق أدناه\n'
                      '٢. أخبرنا بالخطة التي تريدها\n'
                      '٣. استلم مفتاح الترخيص بعد الدفع\n'
                      '٤. أدخل المفتاح في التطبيق وابدأ فوراً',
                      style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.8),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── التواصل ──────────────────────────────────────────────────
              _ContactRow(
                icon:  Icons.phone_outlined,
                label: 'واتساب / هاتف',
                value: '+964 7XX XXX XXXX',
              ),
              const SizedBox(height: 8),
              _ContactRow(
                icon:  Icons.email_outlined,
                label: 'البريد الإلكتروني',
                value: 'support@naboo.app',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── بطاقة خطة الاشتراك ────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isPopular,
    required this.isCurrent,
    required this.accentColor,
    required this.icon,
  });

  final SubscriptionPlan plan;
  final bool             isPopular;
  final bool             isCurrent;
  final Color            accentColor;
  final IconData         icon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isCurrent
                ? accentColor.withOpacity(0.15)
                : Colors.white.withOpacity(0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isCurrent
                  ? accentColor
                  : isPopular
                      ? accentColor.withOpacity(0.5)
                      : Colors.white.withOpacity(0.12),
              width: isCurrent ? 2 : isPopular ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // رأس البطاقة
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: accentColor, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plan.nameAr,
                          style: TextStyle(
                            color: accentColor,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          plan.devicesLabel,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // السعر
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _formatPrice(plan.priceIQD),
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'د.ع',
                            style: TextStyle(color: Colors.white70, fontSize: 11),
                          ),
                        ],
                      ),
                      const Text(
                        'شهرياً',
                        style: TextStyle(color: Colors.white54, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),
              Divider(color: Colors.white.withOpacity(0.1)),
              const SizedBox(height: 12),

              // قائمة المميزات
              ...plan.features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: accentColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(f,
                          style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                  ],
                ),
              )),

              const SizedBox(height: 16),

              // حالة الخطة
              if (isCurrent)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accentColor.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check, size: 16, color: accentColor),
                      const SizedBox(width: 6),
                      Text(
                        'خطتك الحالية',
                        style: TextStyle(
                          color: accentColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: accentColor,
                      side: BorderSide(color: accentColor),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () => _showContactDialog(context, plan),
                    child: Text(
                      'اشترِك في ${plan.nameAr}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // شارة الأكثر طلباً
        if (isPopular)
          Positioned(
            top: -12,
            right: 0,
            left: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'الأكثر طلباً',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  void _showContactDialog(BuildContext context, SubscriptionPlan plan) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text('الاشتراك في خطة ${plan.nameAr}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'السعر: ${plan.priceLabel}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
              Text(
                'الأجهزة: ${plan.devicesLabel}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              const Text('للاشتراك، تواصل معنا:'),
              const SizedBox(height: 12),
              _ContactTile(
                icon: Icons.phone_outlined,
                text: '+964 7XX XXX XXXX',
                onCopy: () {
                  Clipboard.setData(const ClipboardData(text: '+964 7XX XXX XXXX'));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الرقم'), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
              const SizedBox(height: 8),
              _ContactTile(
                icon: Icons.email_outlined,
                text: 'support@naboo.app',
                onCopy: () {
                  Clipboard.setData(const ClipboardData(text: 'support@naboo.app'));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم نسخ الإيميل'), behavior: SnackBarBehavior.floating),
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── مكونات مساعدة ─────────────────────────────────────────────────────────────

class _ContactRow extends StatelessWidget {
  const _ContactRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String   label;
  final String   value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.copy_outlined, color: Colors.white54, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: value)),
            tooltip: 'نسخ',
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.icon, required this.text, required this.onCopy});
  final IconData icon;
  final String   text;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCopy,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _kAccent),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.copy_outlined, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
