import 'package:flutter/material.dart';

import '../../services/app_settings_repository.dart';
import '../../services/inventory_policy_settings.dart';

/// مركز سياسات المخزون المتقدمة — يُصل إليه من إعدادات المخزون أو من الأدمن.
class InventoryPolicyCenterScreen extends StatefulWidget {
  const InventoryPolicyCenterScreen({super.key});

  @override
  State<InventoryPolicyCenterScreen> createState() =>
      _InventoryPolicyCenterScreenState();
}

class _InventoryPolicyCenterScreenState
    extends State<InventoryPolicyCenterScreen> {
  final _repo = AppSettingsRepository.instance;
  InventoryPolicySettingsData _data = InventoryPolicySettingsData.defaults();
  bool _loading = true;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final d = await InventoryPolicySettingsData.load(_repo);
    if (!mounted) return;
    setState(() {
      _data    = d;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _data.save(_repo);
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ سياسات المخزون')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مركز سياسات المخزون'),
          actions: [
            IconButton(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              tooltip: 'حفظ',
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // ── نوع النشاط ──────────────────────────────────────────
                  _card('نوع نشاط العميل', [
                    DropdownButtonFormField<String>(
                      value: _data.businessProfile,
                      decoration: const InputDecoration(
                        labelText: 'ملف النشاط',
                        border: OutlineInputBorder(),
                      ),
                      items: BusinessProfile.values.map((p) {
                        return DropdownMenuItem(
                          value: p.key,
                          child: Text(p.label),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final profile = BusinessProfile.fromKey(v);
                        setState(() {
                          _data = _data.applyProfileDefaults(profile);
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.blue.withOpacity(0.06),
                      child: const Text(
                        'عند اختيار نوع النشاط تُضبط الخصائص الافتراضية تلقائياً — يمكنك تعديلها يدوياً.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 12),

                  // ── وحدات المخزون الأساسية ──────────────────────────────
                  _card('تمكين الوحدات', [
                    _sw('إدارة المنتجات', _data.enableProducts,
                        (v) => setState(() => _data = _data.copyWith(enableProducts: v))),
                    _sw('إضافة منتج', _data.enableAddProduct,
                        (v) => setState(() => _data = _data.copyWith(enableAddProduct: v))),
                    _sw('السندات المخزنية', _data.enableVouchers,
                        (v) => setState(() => _data = _data.copyWith(enableVouchers: v))),
                    _sw('قوائم الأسعار', _data.enablePriceLists,
                        (v) => setState(() => _data = _data.copyWith(enablePriceLists: v))),
                    _sw('المستودعات', _data.enableWarehouses,
                        (v) => setState(() => _data = _data.copyWith(enableWarehouses: v))),
                    _sw('الجرد', _data.enableStocktaking,
                        (v) => setState(() => _data = _data.copyWith(enableStocktaking: v))),
                    _sw('إعدادات المخزون', _data.enableSettings,
                        (v) => setState(() => _data = _data.copyWith(enableSettings: v))),
                  ]),

                  const SizedBox(height: 12),

                  // ── خصائص بطاقة المنتج ──────────────────────────────────
                  _card('خصائص بطاقة المنتج', [
                    _sw('حقل الرتبة / درجة الجودة', _data.enableProductGrade,
                        (v) => setState(() => _data = _data.copyWith(enableProductGrade: v))),
                    _sw('تاريخ الانتهاء والإنتاج', _data.enableExpiryTracking,
                        (v) => setState(() => _data = _data.copyWith(enableExpiryTracking: v))),
                    _sw('تتبع الدفعات (Batch)', _data.enableBatchTracking,
                        (v) => setState(() => _data = _data.copyWith(enableBatchTracking: v))),
                    _sw('تنبيهات نفاد المخزون', _data.enableLowStockAlerts,
                        (v) => setState(() => _data = _data.copyWith(enableLowStockAlerts: v))),
                    _sw('صور المنتج', _data.enableProductImages,
                        (v) => setState(() => _data = _data.copyWith(enableProductImages: v))),
                    _sw('متغيرات المنتج (مقاس/لون)', _data.enableProductVariants,
                        (v) => setState(() => _data = _data.copyWith(enableProductVariants: v))),
                  ]),

                  const SizedBox(height: 12),

                  // ── المشتريات ────────────────────────────────────────────
                  _card('المشتريات والموردون', [
                    _sw('أوامر الشراء (PO)', _data.enablePurchaseOrders,
                        (v) => setState(() => _data = _data.copyWith(enablePurchaseOrders: v))),
                    _sw('إلزام تحديد مصدر في الوارد', _data.requireSourceOnInbound,
                        (v) => setState(() => _data = _data.copyWith(requireSourceOnInbound: v))),
                  ]),

                  const SizedBox(height: 12),

                  // ── التحليلات ────────────────────────────────────────────
                  _card('التحليلات والتقارير', [
                    _sw('تحليلات المخزون', _data.enableStockAnalytics,
                        (v) => setState(() => _data = _data.copyWith(enableStockAnalytics: v))),
                  ]),
                ],
              ),
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _sw(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      title: Text(title, style: const TextStyle(fontSize: 13)),
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}
