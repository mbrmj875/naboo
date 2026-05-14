import 'package:flutter/material.dart';

import '../../models/customer_record.dart';
import 'customer_financial_detail_panel.dart';
import 'customer_form_screen.dart';

/// تفاصيل مشتريات العميل بالدين والتقسيط — صفحة كاملة (موبايل/تابلت ضيّق).
///
/// **بنية**: ‏الـ Scaffold/AppBar يبقى هنا، بينما المحتوى تم استخراجه إلى
/// [CustomerFinancialDetailPanel] لتمكين إعادة استخدامه داخل
/// `MasterDetailLayout` على الديسكتوب.
class CustomerFinancialDetailScreen extends StatefulWidget {
  const CustomerFinancialDetailScreen({super.key, required this.customer});

  final CustomerRecord customer;

  @override
  State<CustomerFinancialDetailScreen> createState() =>
      _CustomerFinancialDetailScreenState();
}

class _CustomerFinancialDetailScreenState
    extends State<CustomerFinancialDetailScreen> {
  late CustomerRecord _current;

  @override
  void initState() {
    super.initState();
    _current = widget.customer;
  }

  Future<void> _openEdit() async {
    final updated = await Navigator.of(context).push<CustomerRecord?>(
      MaterialPageRoute(
        builder: (_) => CustomerFormScreen(existing: _current),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _current = updated);
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
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          elevation: 0,
          title: Text(
            _current.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          actions: [
            IconButton(
              tooltip: 'تعديل بيانات العميل',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _openEdit,
            ),
          ],
        ),
        body: CustomerFinancialDetailPanel(
          customer: _current,
        ),
      ),
    );
  }
}
