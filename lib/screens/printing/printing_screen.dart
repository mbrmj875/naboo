import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/invoice.dart';
import '../../models/print_settings_data.dart';
import '../../providers/print_settings_provider.dart';
import '../../theme/design_tokens.dart';
import '../../utils/sale_receipt_pdf.dart';
import '../../services/thermal_esc_pos_service.dart';
import '../../services/thermal_network_printer_service.dart';
import '../inventory/barcode_settings_screen.dart';
import '../settings/store_info_screen.dart';

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
  late bool _thermalEscPosEnabled;
  late TextEditingController _thermalHostCtrl;
  late TextEditingController _thermalPortCtrl;
  late TextEditingController _thermalTimeoutCtrl;
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
    _thermalEscPosEnabled = p.thermalEscPosEnabled;
    _thermalHostCtrl = TextEditingController(text: p.thermalLanHost);
    _thermalPortCtrl = TextEditingController(text: p.thermalLanPort.toString());
    _thermalTimeoutCtrl = TextEditingController(
      text: p.thermalLanTimeoutMs.toString(),
    );
    _storeTitleCtrl = TextEditingController(text: p.storeTitleLine);
    _footerCtrl = TextEditingController(text: p.footerExtra);
  }

  @override
  void dispose() {
    _storeTitleCtrl.dispose();
    _footerCtrl.dispose();
    _thermalHostCtrl.dispose();
    _thermalPortCtrl.dispose();
    _thermalTimeoutCtrl.dispose();
    super.dispose();
  }

  PrintSettingsData _collect() {
    final base = context.read<PrintSettingsProvider>().data;
    return base.copyWith(
      paperFormat: _paper,
      thermalEscPosEnabled: _thermalEscPosEnabled,
      thermalLanHost: _thermalHostCtrl.text.trim(),
      thermalLanPort: int.tryParse(_thermalPortCtrl.text.trim()) ?? 9100,
      thermalLanTimeoutMs:
          int.tryParse(_thermalTimeoutCtrl.text.trim()) ?? 4000,
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

  Future<void> _previewEscPosSample() async {
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
    );
    final text = ThermalEscPosService.instance.buildReceiptText(
      invoice: sample,
      subtotalBeforeDiscount: 30000,
      settings: settings,
    );
    final base64 = ThermalEscPosService.instance.buildReceiptBase64(
      invoice: sample,
      subtotalBeforeDiscount: 30000,
      settings: settings,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('معاينة ESC/POS (تجريبية)'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'تم توليد حمولة حرارية خام. يمكنك نسخ النص أو Base64 لتمريره إلى جسر الطابعة (Bluetooth/USB/LAN).',
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      text,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      base64,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: text));
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('تم نسخ النص الحراري')),
                    );
                  }
                },
                child: const Text('نسخ النص'),
              ),
              TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: base64));
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('تم نسخ Base64 الحراري')),
                    );
                  }
                },
                child: const Text('نسخ Base64'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('إغلاق'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendEscPosSampleToLan() async {
    final settings = _collect();
    final nav = ScaffoldMessenger.of(context);
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
    );
    try {
      final payload = ThermalEscPosService.instance.buildReceiptBytes(
        invoice: sample,
        subtotalBeforeDiscount: 30000,
        settings: settings,
      );
      await ThermalNetworkPrinterService.instance.sendBytes(
        host: settings.thermalLanHost,
        port: settings.thermalLanPort,
        timeoutMs: settings.thermalLanTimeoutMs,
        payload: payload,
      );
      if (!mounted) return;
      nav.showSnackBar(
        const SnackBar(
          content: Text('تم إرسال إيصال تجريبي للطابعة الحرارية عبر الشبكة'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      nav.showSnackBar(
        SnackBar(
          content: Text('تعذر الإرسال للطابعة الحرارية: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          elevation: 0,
          title: Text(
            'الطباعة والمستندات',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: _dirty ? _save : null,
              icon: const Icon(
                Icons.save_rounded,
                color: AppColors.accentGold,
                size: 20,
              ),
              label: const Text(
                'حفظ',
                style: TextStyle(color: AppColors.accentGold),
              ),
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
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
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
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('تفعيل مسار ESC/POS الحراري'),
                          subtitle: const Text(
                            'وضع تجريبي: يولد payload خام للطابعات الحرارية (بدون PDF).',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _thermalEscPosEnabled,
                          activeThumbColor: AppColors.accentGold,
                          onChanged: (v) => setState(() {
                            _thermalEscPosEnabled = v;
                            _dirty = true;
                          }),
                        ),
                        if (_thermalEscPosEnabled) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: _thermalHostCtrl,
                            onChanged: (_) => setState(() => _dirty = true),
                            decoration: InputDecoration(
                              labelText: 'عنوان طابعة الشبكة (IP / Host)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _thermalPortCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() => _dirty = true),
                                  decoration: InputDecoration(
                                    labelText: 'المنفذ',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _thermalTimeoutCtrl,
                                  keyboardType: TextInputType.number,
                                  onChanged: (_) => setState(() => _dirty = true),
                                  decoration: InputDecoration(
                                    labelText: 'المهلة ms',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 14),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('إظهار باركود رقم العملية'),
                          subtitle: const Text(
                            'CODE128 — يقرأه الماسح الضوئي بسرعة',
                            style: TextStyle(fontSize: 12),
                          ),
                          value: _showBarcode,
                          activeThumbColor: AppColors.accentGold,
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
                          activeThumbColor: AppColors.accentGold,
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
                          activeThumbColor: AppColors.accentGold,
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
                          decoration: InputDecoration(
                            labelText: 'سطر فوق عنوان «إيصال بيع» (اسم المتجر)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _footerCtrl,
                          maxLines: 3,
                          onChanged: (_) => setState(() => _dirty = true),
                          decoration: InputDecoration(
                            labelText: 'تذييل إضافي (هاتف، شروط، شكر)',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
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
                          'الاسم، العنوان، وأرقام الهاتف — تظهر على إيصال البيع',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(Icons.chevron_left, size: 20),
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const StoreInfoScreen(),
                            ),
                          );
                          if (!context.mounted) return;
                          final p =
                              context.read<PrintSettingsProvider>().data;
                          _storeTitleCtrl.text = p.storeTitleLine;
                          setState(() => _dirty = true);
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
                    backgroundColor: AppColors.accentGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _previewEscPosSample,
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('معاينة حمولة ESC/POS'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accentGold,
                    side: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _thermalEscPosEnabled ? _sendEscPosSampleToLan : null,
                  icon: const Icon(Icons.wifi_tethering),
                  label: const Text('إرسال تجريبي للطابعة (LAN)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentGold,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('حفظ الإعدادات في قاعدة البيانات'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accentGold,
                    side: BorderSide(color: AppColors.accentGold.withValues(alpha: 0.5)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.accentGold.withValues(alpha: isDark ? 0.15 : 0.08),
        border: Border.all(color: AppColors.accentGold.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.accentGold.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.print_rounded, color: AppColors.accentGold, size: 36),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'مركز الطباعة الاحترافي',
                  style: TextStyle(
                    color: AppColors.accentGold,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'ضبط أحجام الحرارية وA4، محتوى الإيصال، والربط مع المخزون — كل ذلك محفوظ محلياً.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
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
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.accentGold),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.accentGold,
          ),
        ),
      ],
    );
  }
}
