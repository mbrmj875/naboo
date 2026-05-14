import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/invoice.dart';
import '../../models/print_settings_data.dart';
import '../../providers/print_settings_provider.dart';
import '../../theme/design_tokens.dart';
import '../../utils/sale_receipt_pdf.dart';
import '../inventory/barcode_settings_screen.dart';

/// مركز الطباعة — إعدادات مرتبطة بقاعدة البيانات [print_settings] وإيصال البيع.
class PrintingScreen extends StatefulWidget {
  const PrintingScreen({super.key});

  @override
  State<PrintingScreen> createState() => _PrintingScreenState();
}

class _PrintingScreenState extends State<PrintingScreen> {
  late PrintPaperFormat _paper;
  late bool _showBarcode;
  late bool _showQr;
  late bool _showBuyerAddressQr;
  late TextEditingController _storeTitleCtrl;
  late TextEditingController _footerCtrl;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final p = context.read<PrintSettingsProvider>().data;
    _paper = p.paperFormat;
    _showBarcode = p.receiptShowBarcode;
    _showQr = p.receiptShowQr;
    _showBuyerAddressQr = p.receiptShowBuyerAddressQr;
    _storeTitleCtrl = TextEditingController(text: p.storeTitleLine);
    _footerCtrl = TextEditingController(text: p.footerExtra);
  }

  @override
  void dispose() {
    _storeTitleCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  PrintSettingsData _collect() {
    return PrintSettingsData(
      paperFormat: _paper,
      receiptShowBarcode: _showBarcode,
      receiptShowQr: _showQr,
      receiptShowBuyerAddressQr: _showBuyerAddressQr,
      storeTitleLine: _storeTitleCtrl.text.trim(),
      footerExtra: _footerCtrl.text.trim(),
    );
  }

  Future<void> _save() async {
    final nav = ScaffoldMessenger.of(context);
    try {
      await context.read<PrintSettingsProvider>().save(_collect());
      if (!mounted) return;
      setState(() => _dirty = false);
      nav.showSnackBar(
        const SnackBar(
          content: Text('تم حفظ إعدادات الطباعة'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        nav.showSnackBar(SnackBar(content: Text('تعذر الحفظ: $e')));
      }
    }
  }

  Future<void> _previewSample() async {
    final settings = _collect();
    final sample = Invoice(
      customerName: 'عميل تجريبي',
      date: DateTime.now(),
      type: InvoiceType.cash,
      items: [
        InvoiceItem(
          productName: 'صنف 1',
          quantity: 2,
          price: 15000,
          total: 30000,
          productId: null,
        ),
      ],
      discount: 0,
      tax: 0,
      advancePayment: 0,
      total: 30000,
      createdByUserName: 'موظف',
      discountPercent: 0,
      deliveryAddress: settings.receiptShowBuyerAddressQr
          ? 'بغداد، شارع تجريبي'
          : null,
    );
    await SaleReceiptPdf.presentReceipt(
      context,
      invoice: sample,
      subtotalBeforeDiscount: 30000,
      printSettings: settings,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('الطباعة والمستندات'),
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          actions: [
            TextButton.icon(
              onPressed: _dirty ? _save : null,
              icon: Icon(Icons.save_rounded, color: cs.onPrimary, size: 20),
              label: Text('حفظ', style: TextStyle(color: cs.onPrimary)),
            ),
          ],
        ),
        body: Consumer<PrintSettingsProvider>(
          builder: (context, prov, _) {
            if (!prov.isReady) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const _HeroCard(),
                const SizedBox(height: 14),
                const _SectionTitle(icon: Icons.description_outlined, title: 'إيصال البيع'),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppShape.none,
                    side: BorderSide(color: cs.outline),
                  ),
                  color: cs.surface,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'حجم الورق الافتراضي',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<PrintPaperFormat>(
                          value: _paper,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(borderRadius: AppShape.none),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: PrintPaperFormat.thermal58,
                              child: Text('حراري 58 مم (ضيق)'),
                            ),
                            DropdownMenuItem(
                              value: PrintPaperFormat.thermal80,
                              child: Text('حراري 80 مم (قياسي)'),
                            ),
                            DropdownMenuItem(
                              value: PrintPaperFormat.a4,
                              child: Text('A4'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _paper = v;
                              _dirty = true;
                            });
                          },
                        ),
                        const SizedBox(height: 14),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('إظهار باركود رقم العملية'),
                          subtitle: const Text(
                            'CODE128 — يقرأه الماسح الضوئي بسرعة',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _showBarcode,
                          activeThumbColor: cs.primary,
                          onChanged: (v) =>
                              setState(() {
                                _showBarcode = v;
                                _dirty = true;
                              }),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('إظهار رمز QR'),
                          subtitle: const Text(
                            'ملخص نصي للعميل — يُوصى به للضريبة والمراجعة',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _showQr,
                          activeThumbColor: cs.primary,
                          onChanged: (v) =>
                              setState(() {
                                _showQr = v;
                                _dirty = true;
                              }),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('QR لعنوان المشتري (خرائط)'),
                          subtitle: const Text(
                            'عند التفعيل يظهر حقل «عنوان المشتري» في البيع ويُطبَع QR يفتح الموقع على Google Maps',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _showBuyerAddressQr,
                          activeThumbColor: cs.primary,
                          onChanged: (v) =>
                              setState(() {
                                _showBuyerAddressQr = v;
                                _dirty = true;
                              }),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _storeTitleCtrl,
                          onChanged: (_) => setState(() => _dirty = true),
                          decoration: const InputDecoration(
                            labelText: 'سطر فوق عنوان «إيصال بيع» (اسم المتجر)',
                            border: OutlineInputBorder(borderRadius: AppShape.none),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _footerCtrl,
                          maxLines: 3,
                          onChanged: (_) => setState(() => _dirty = true),
                          decoration: const InputDecoration(
                            labelText: 'تذييل إضافي (هاتف، شروط، شكر)',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(borderRadius: AppShape.none),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionTitle(icon: Icons.link_rounded, title: 'ربط مع بقية النظام'),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: AppShape.none,
                    side: BorderSide(color: cs.outline),
                  ),
                  color: cs.surface,
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(Icons.qr_code_2_rounded,
                            color: cs.secondary),
                        title: const Text('إعدادات الباركود والملصقات'),
                        subtitle: const Text(
                          'تنسيق الباركود للمنتجات — يُستخدم عند الطباعة من المخزون',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_left, size: 20),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const BarcodeSettingsScreen(),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(Icons.store_rounded,
                            color: cs.primary),
                        title: const Text('بيانات المتجر'),
                        subtitle: const Text(
                          'من الإعدادات — لاحقاً يمكن ربط اسم المتجر تلقائياً بالإيصال',
                          style: TextStyle(fontSize: 12),
                        ),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'استخدم حقل «اسم المتجر» أعلاه أو بطاقة بيانات المتجر من الإعدادات',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _previewSample,
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('معاينة إيصال تجريبي'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.secondary,
                    foregroundColor: cs.onSecondary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ الإعدادات في قاعدة البيانات'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'البيانات تُخزَّن في جدول print_settings وتُطبَّق تلقائياً عند طباعة إيصال البيع بعد كل عملية.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final onHero = cs.onPrimary;
    final deep = Color.lerp(cs.primary, Colors.black, 0.22)!;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, deep],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: AppShape.none,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: onHero.withValues(alpha: 0.12),
              borderRadius: AppShape.none,
            ),
            child: Icon(Icons.print_rounded, color: onHero, size: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'مركز الطباعة الاحترافي',
                  style: TextStyle(
                    color: onHero,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'ضبط أحجام الحرارية وA4، محتوى الإيصال، والربط مع المخزون — كل ذلك محفوظ محلياً.',
                  style: TextStyle(
                    color: onHero.withValues(alpha: 0.88),
                    fontSize: 13,
                    height: 1.35,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.secondary),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
      ],
    );
  }
}
