import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/design_tokens.dart';
import '../models/whatsapp_connect_method.dart';
import 'oil_change_form_theme.dart';

/// لوحة حالة الربط الرسمي (Meta مباشرة أو رقم نابو الرسمي).
class WhatsappOfficialConnectPanel extends StatefulWidget {
  const WhatsappOfficialConnectPanel({
    super.key,
    required this.method,
    required this.preparing,
    required this.messageAr,
    this.onboardingUrl,
    this.onOpenOnboarding,
    this.onOpenCoexistence,
    this.onRefresh,
    this.onBack,
    this.onContinue,
  });

  final WhatsappConnectMethod method;
  final bool preparing;
  final String messageAr;
  final String? onboardingUrl;
  final void Function(String phoneDigits)? onOpenOnboarding;
  final void Function(String phoneDigits)? onOpenCoexistence;
  final VoidCallback? onRefresh;
  final VoidCallback? onBack;
  final VoidCallback? onContinue;

  @override
  State<WhatsappOfficialConnectPanel> createState() =>
      _WhatsappOfficialConnectPanelState();
}

class _WhatsappOfficialConnectPanelState
    extends State<WhatsappOfficialConnectPanel> {
  final _phoneCtrl = TextEditingController();
  String? _phoneError;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  String? _normalizeShopWhatsapp(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00964')) digits = digits.substring(5);
    if (digits.startsWith('964')) digits = digits.substring(3);
    if (digits.startsWith('0')) digits = digits.substring(1);
    if (digits.length == 10 && digits.startsWith('7')) {
      return '964$digits';
    }
    return null;
  }

  String? _requirePhone() {
    final e164 = _normalizeShopWhatsapp(_phoneCtrl.text);
    if (e164 == null) {
      setState(() {
        _phoneError = 'أدخل رقم واتساب المحل (مثال: 07701234567).';
      });
      return null;
    }
    setState(() => _phoneError = null);
    return e164;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final method = widget.method;
    final preparing = widget.preparing;
    final hasUrl = (widget.onboardingUrl ?? '').trim().isNotEmpty;
    final isMetaDirect = method == WhatsappConnectMethod.metaDirect;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [
                AppColors.primary.withValues(alpha: 0.95),
                AppColors.primary.withValues(alpha: 0.78),
                OilChangeFormTheme.gold.withValues(alpha: 0.28),
              ],
            ),
            border: Border.all(
              color: OilChangeFormTheme.gold.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OilChangeFormTheme.gold.withValues(alpha: 0.18),
                  border: Border.all(
                    color: OilChangeFormTheme.gold.withValues(alpha: 0.5),
                  ),
                ),
                child: preparing
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: OilChangeFormTheme.gold,
                        ),
                      )
                    : Icon(
                        method.icon,
                        size: 36,
                        color: OilChangeFormTheme.gold,
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                preparing ? 'جاري تجهيز واتساب…' : method.titleAr,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.messageAr,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.86),
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              _StepDots(
                labels: const ['الرقم', 'التأكيد', 'الجاهزية'],
                activeIndex: preparing ? 1 : 0,
              ),
            ],
          ),
        ),
        if (isMetaDirect) ...[
          const SizedBox(height: 16),
          Text(
            'رقم واتساب المحل',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.left,
              onChanged: (_) {
                if (_phoneError != null) setState(() => _phoneError = null);
              },
              decoration: InputDecoration(
                hintText: '07701234567',
                prefixIcon: const Icon(Icons.phone_outlined),
                errorText: _phoneError,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: OilChangeFormTheme.gold.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'إن ظهرت في فيسبوك: «الحافظة لا تحتوي حسابات واتساب»',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'الحافظة وحدها لا تكفي. تحتاج حساب واتساب للأعمال (WABA) داخلها ثم الرقم.\n'
                    '1) اضغط «عودة» في فيسبوك.\n'
                    '2) إن لم يظهر «إنشاء حساب واتساب»: افتح Business Suite وأنشئ حساب واتساب داخل حافظة محلك.\n'
                    '3) أعد الربط من هنا واختر نفس الحافظة — لا تختر حافظة نابو.',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse('https://business.facebook.com/');
                        try {
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'تعذّر فتح Business Suite. افتح business.facebook.com يدوياً.',
                              ),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('فتح Business Suite'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ترتيب ميتا: حافظة → حساب واتساب (WABA) → رقم + رمز في فيسبوك. '
            'رمز التأكيد يُدخل في فيسبوك فقط، ليس داخل نابو.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        if (hasUrl && widget.onOpenOnboarding != null) ...[
          if (isMetaDirect) ...[
            FilledButton.icon(
              onPressed: () {
                final phone = _requirePhone();
                if (phone == null) return;
                widget.onOpenOnboarding!(phone);
              },
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('ربط هذا الرقم (رقم جديد)'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
            if (widget.onOpenCoexistence != null)
              FilledButton.icon(
                onPressed: () {
                  final phone = _requirePhone();
                  if (phone == null) return;
                  widget.onOpenCoexistence!(phone);
                },
                icon: const Icon(Icons.phone_android_rounded),
                label: const Text('هذا الرقم على واتساب الأعمال (تعايش)'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: AppColors.primary.withValues(alpha: 0.92),
                ),
              ),
            if (widget.onOpenCoexistence != null) const SizedBox(height: 10),
          ] else ...[
            FilledButton.icon(
              onPressed: () => widget.onOpenOnboarding!(''),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('إكمال الربط في Meta'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: AppColors.primary,
              ),
            ),
            const SizedBox(height: 10),
          ],
        ] else if (!preparing && widget.onContinue != null) ...[
          FilledButton.icon(
            onPressed: widget.onContinue,
            icon: const Icon(Icons.rocket_launch_rounded),
            label: const Text('بدء الربط الرسمي'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (widget.onRefresh != null)
          OutlinedButton.icon(
            onPressed: widget.onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('تحديث حالة التجهيز'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: OilChangeFormTheme.gold,
            ),
          ),
        if (widget.onBack != null) ...[
          const SizedBox(height: 4),
          TextButton(
            onPressed: widget.onBack,
            child: const Text('العودة لاختيار طريقة أخرى'),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          preparing
              ? 'نابو يجهّز القوالب والرقم تلقائياً — لا تحتاج إنشاء قالب يدوياً.'
              : isMetaDirect
                  ? 'أدخل رقم المحل أولاً ثم اربط. إن علقت عند حافظة فارغة: أنشئ WABA من Business Suite ثم أعد الربط.'
                  : 'بعد الإكمال ستظهر حالة «جاهز» عند اكتمال الإعداد على السحابة.',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurfaceVariant,
            height: 1.4,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StepDots extends StatelessWidget {
  const _StepDots({required this.labels, required this.activeIndex});

  final List<String> labels;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          Expanded(
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: i <= activeIndex
                        ? OilChangeFormTheme.gold
                        : Colors.white.withValues(alpha: 0.22),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        i == activeIndex ? FontWeight.w800 : FontWeight.w500,
                    color: Colors.white.withValues(
                      alpha: i <= activeIndex ? 0.95 : 0.55,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (i < labels.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}
