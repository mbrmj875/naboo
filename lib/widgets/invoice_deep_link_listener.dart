import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/database_helper.dart';
import '../screens/debts/customer_debt_detail_screen.dart';
import '../utils/customer_debt_deep_link.dart';
import '../utils/invoice_deep_link.dart';
import 'invoice_detail_sheet.dart';

/// يستمع لروابط `basrainvoice://invoice/{id}` (مثلاً من مسح QR على الإيصال) ويعرض تفاصيل الفاتورة.
class InvoiceDeepLinkListener extends StatefulWidget {
  const InvoiceDeepLinkListener({super.key, required this.child});

  final Widget child;

  @override
  State<InvoiceDeepLinkListener> createState() =>
      _InvoiceDeepLinkListenerState();
}

class _InvoiceDeepLinkListenerState extends State<InvoiceDeepLinkListener> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  int? _lastOpenedId;
  DateTime _lastOpenedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int? _lastOpenedCustomerId;
  DateTime _lastOpenedCustomerAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _initLinks();
  }

  Future<void> _initLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _tryOpen(initial);
        });
      }
    } catch (_) {}
    _sub = _appLinks.uriLinkStream.listen((uri) {
      if (mounted) _tryOpen(uri);
    });
  }

  void _tryOpen(Uri uri) {
    final customerId = CustomerDebtDeepLink.parseCustomerId(uri);
    if (customerId != null && customerId > 0) {
      if (!context.read<AuthProvider>().isLoggedIn) return;
      final now = DateTime.now();
      if (_lastOpenedCustomerId == customerId &&
          now.difference(_lastOpenedCustomerAt) <
              const Duration(milliseconds: 900)) {
        return;
      }
      _lastOpenedCustomerId = customerId;
      _lastOpenedCustomerAt = now;
      unawaited(
        Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => CustomerDebtDetailScreen.fromCustomerId(
              registeredCustomerId: customerId,
            ),
          ),
        ),
      );
      return;
    }

    final id = InvoiceDeepLink.parseInvoiceId(uri);
    if (id == null || id <= 0) return;
    if (!context.read<AuthProvider>().isLoggedIn) return;
    final now = DateTime.now();
    if (_lastOpenedId == id &&
        now.difference(_lastOpenedAt) < const Duration(milliseconds: 900)) {
      return;
    }
    _lastOpenedId = id;
    _lastOpenedAt = now;
    unawaited(
      showInvoiceDetailSheet(context, DatabaseHelper(), id),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
