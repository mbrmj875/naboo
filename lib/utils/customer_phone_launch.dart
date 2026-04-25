import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// دمج الرقم الأساسي مع الإضافي بدون تكرار (حسب الأرقام بعد إزالة غير الرقم).
List<String> mergeCustomerPhoneChoices({
  required String? primaryPhone,
  required List<String> extraPhones,
}) {
  final out = <String>[];
  final seen = <String>{};

  void add(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return;
    final key = t.replaceAll(RegExp(r'\D'), '');
    if (key.isEmpty) return;
    if (seen.contains(key)) return;
    seen.add(key);
    out.add(t);
  }

  add(primaryPhone ?? '');
  for (final e in extraPhones) {
    add(e);
  }
  return out;
}

/// أرقام دولية لـ wa.me / tel (تقدير للعراق: 0… أو 7XXXXXXXXX → 964…).
String customerPhoneDigitsForLinks(String raw) {
  var d = raw.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return '';
  if (!d.startsWith('964')) {
    if (d.startsWith('0')) {
      d = '964${d.substring(1)}';
    } else if (d.length == 10 && d.startsWith('7')) {
      d = '964$d';
    }
  }
  return d;
}

Uri _customerTelUri(String raw) {
  final d = customerPhoneDigitsForLinks(raw);
  return Uri.parse('tel:+$d');
}

Uri _customerWhatsAppUri(String raw) {
  final d = customerPhoneDigitsForLinks(raw);
  return Uri.parse('https://wa.me/$d');
}

Future<void> _launchUri(BuildContext context, Uri uri) async {
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر فتح التطبيق المناسب')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر الفتح: $e')),
      );
    }
  }
}

/// إن وُجد أكثر من رقم يعرض اختياراً ثم يتصل.
Future<void> launchCustomerDial(
  BuildContext context,
  List<String> phones,
) async {
  final chosen = await _resolvePhoneChoice(
    context,
    phones: phones,
    title: 'اختر الرقم للاتصال',
  );
  if (chosen == null || !context.mounted) return;
  await _launchUri(context, _customerTelUri(chosen));
}

Future<void> launchCustomerWhatsApp(
  BuildContext context,
  List<String> phones,
) async {
  final chosen = await _resolvePhoneChoice(
    context,
    phones: phones,
    title: 'اختر الرقم للواتساب',
  );
  if (chosen == null || !context.mounted) return;
  await _launchUri(context, _customerWhatsAppUri(chosen));
}

Future<String?> _resolvePhoneChoice(
  BuildContext context, {
  required List<String> phones,
  required String title,
}) async {
  if (phones.isEmpty) return null;
  if (phones.length == 1) return phones.first;

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final p in phones)
                      ListTile(
                        leading: const Icon(Icons.phone_rounded),
                        title: Text(p),
                        onTap: () => Navigator.pop(ctx, p),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
