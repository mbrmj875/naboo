import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/theme_provider.dart';

/// شاشة فرعية لإعدادات فئة معيّنة من إعدادات المخزون والمنتجات.
class InventorySettingDetailScreen extends StatefulWidget {
  const InventorySettingDetailScreen({
    super.key,
    required this.settingKey,
    required this.title,
    required this.description,
  });

  final String settingKey;
  final String title;
  final String description;

  @override
  State<InventorySettingDetailScreen> createState() =>
      _InventorySettingDetailScreenState();
}

class _InventorySettingDetailScreenState
    extends State<InventorySettingDetailScreen> {
  // حالة محلية للمعاينة — يمكن ربطها لاحقاً بالتخزين أو الـ API
  final Map<String, bool> _bools = {};

  bool _get(String k, [bool def = false]) => _bools[k] ?? def;

  void _set(String k, bool v) => setState(() => _bools[k] = v);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, tp, _) {
        final isDark = tp.isDarkMode;
        final bg = isDark ? const Color(0xFF121212) : const Color(0xFFF0F4F8);
        final surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;
        final textPrimary = isDark ? Colors.white : const Color(0xFF1E293B);
        final textSecondary =
            isDark ? Colors.grey.shade400 : Colors.grey.shade600;
        final divider = isDark ? Colors.grey.shade800 : Colors.grey.shade300;

        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E3A5F),
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios,
                  color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              widget.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.zero,
                  border: Border.all(color: divider),
                ),
                child: Text(
                  widget.description,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: textSecondary,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(height: 20),
              ..._buildControls(
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                divider: divider,
                surface: surface,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _buildControls({
    required Color textPrimary,
    required Color textSecondary,
    required Color divider,
    required Color surface,
  }) {
    switch (widget.settingKey) {
      case 'products':
        return [
          _infoTile(
            'إعدادات المنتجات الكاملة (تهيئة، تتبع، أذون، قيم افتراضية) متوفرة من البطاقة الرئيسية «إعدادات المنتجات» في شبكة إعدادات المخزون.',
            textSecondary,
            surface,
            divider,
          ),
        ];
      case 'categories':
        return [
          _infoTile(
            'تم نقل إدارة التصنيفات إلى شاشة مخصّصة. افتح «التصنيفات» من القائمة الرئيسية لإعدادات المخزون.',
            textSecondary,
            surface,
            divider,
          ),
        ];
      case 'brands':
        return [
          _infoTile(
            'تم نقل إدارة العلامات التجارية إلى شاشة مخصّصة. افتح «العلامات التجارية» من القائمة الرئيسية.',
            textSecondary,
            surface,
            divider,
          ),
        ];
      case 'barcode':
        return [
          _infoTile(
            'تم نقل تهيئة الباركود إلى شاشة مخصّصة. افتح «إعدادات الباركود» من القائمة الرئيسية لهذه الإعدادات.',
            textSecondary,
            surface,
            divider,
          ),
        ];
      case 'employee_default_warehouses':
        return [
          _sectionTitle('المستودعات الافتراضية للموظفين', textPrimary),
          _switchTile(
            'فرض مستودع افتراضي عند تسجيل الحركات',
            'emp_default_force',
            textPrimary,
            textSecondary,
            divider,
            surface,
          ),
          _infoTile(
            'يُنصح بربط كل موظف بمستودع افتراضي لتتبع الصلاحيات والحركات.',
            textSecondary,
            surface,
            divider,
          ),
        ];
      case 'unit_templates':
        return [
          _infoTile(
            'إدارة قوالب الوحدات (الأساسية والتحويل) من الشاشة المخصّصة. افتح «قوالب الوحدات» من القائمة الرئيسية لإعدادات المخزون — تُستعمل كمرجع عند تعريف وحدات إضافية للمنتج.',
            textSecondary,
            surface,
            divider,
          ),
          _sectionTitle('الوحدات', textPrimary),
          _switchTile(
            'السماح بوحدات شراء مختلفة عن البيع',
            'unit_purchase_sell',
            textPrimary,
            textSecondary,
            divider,
            surface,
          ),
          _switchTile(
            'عرض التحويلات في فاتورة الشراء',
            'unit_show_po',
            textPrimary,
            textSecondary,
            divider,
            surface,
          ),
        ];
      case 'print_templates':
        return [
          _sectionTitle('الطباعة', textPrimary),
          _switchTile(
            'تضمين شعار المتجر في المستندات',
            'print_logo',
            textPrimary,
            textSecondary,
            divider,
            surface,
          ),
          _switchTile(
            'طباعة باركود على أذون الصرف',
            'print_barcode_issue',
            textPrimary,
            textSecondary,
            divider,
            surface,
          ),
        ];
      case 'custom_fields':
        return [
          _sectionTitle('الحقول الإضافية', textPrimary),
          _switchTile(
            'إظهار الحقول الإضافية في قوائم المنتجات',
            'cf_show_lists',
            textPrimary,
            textSecondary,
            divider,
            surface,
          ),
          _switchTile(
            'تضمينها في التقارير القابلة للتصدير',
            'cf_export',
            textPrimary,
            textSecondary,
            divider,
            surface,
          ),
        ];
      default:
        return [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'لا توجد إعدادات إضافية لهذه الفئة بعد.',
              style: TextStyle(color: textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ];
    }
  }

  Widget _sectionTitle(String text, Color textPrimary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _switchTile(
    String label,
    String key,
    Color textPrimary,
    Color textSecondary,
    Color divider,
    Color surface,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: divider),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          label,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontSize: 14,
            color: textPrimary,
            height: 1.35,
          ),
        ),
        value: _get(key),
        activeTrackColor:
            const Color(0xFF1E3A5F).withValues(alpha: 0.45),
        activeThumbColor: const Color(0xFF1E3A5F),
        onChanged: (v) => _set(key, v),
      ),
    );
  }

  Widget _infoTile(
    String text,
    Color textSecondary,
    Color surface,
    Color divider,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.zero,
        border: Border.all(color: divider),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: textSecondary, height: 1.5),
        textAlign: TextAlign.right,
      ),
    );
  }
}
