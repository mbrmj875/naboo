import 'package:flutter/material.dart';

import '../../../core/widgets/invoices/invoice_list_mode.dart';
import '../../../screens/invoices/invoices_screen.dart';
import '../providers/oil_change_invoice_provider.dart';

/// عارض فواتير إقفال بطاقات غيار الزيت — بدون أي CTA بيع.
class OilChangeInvoicesScreen extends StatefulWidget {
  const OilChangeInvoicesScreen({super.key});

  @override
  State<OilChangeInvoicesScreen> createState() =>
      _OilChangeInvoicesScreenState();
}

class _OilChangeInvoicesScreenState extends State<OilChangeInvoicesScreen> {
  late final OilChangeInvoiceProvider _listController;

  @override
  void initState() {
    super.initState();
    _listController = OilChangeInvoiceProvider();
  }

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InvoicesScreen(
      mode: InvoiceListMode.viewOnly,
      listController: _listController,
      appBarTitle: 'فواتير غيار الزيت',
    );
  }
}
