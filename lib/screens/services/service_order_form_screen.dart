import 'dart:async' show unawaited;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/customer_record.dart';
import '../../screens/customers/customer_form_screen.dart';
import '../../services/database_helper.dart';
import '../../services/product_repository.dart';
import '../../services/service_orders_repository.dart';
import '../../utils/iqd_money.dart';
import '../../utils/iraqi_currency_format.dart';
import '../../widgets/adaptive/adaptive_form_container.dart';

class ServiceOrderFormScreen extends StatefulWidget {
  const ServiceOrderFormScreen({
    super.key,
    this.editOrderId,
    this.editOrderGlobalId,
  });

  final int? editOrderId;
  final String? editOrderGlobalId;

  bool get isEdit => editOrderId != null && editOrderId! > 0;

  @override
  State<ServiceOrderFormScreen> createState() => _ServiceOrderFormScreenState();
}

class _ServiceOrderFormScreenState extends State<ServiceOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerName = TextEditingController();
  final _customerFocus = FocusNode();
  final _deviceName = TextEditingController();
  final _deviceSerial = TextEditingController();
  final _estimated = TextEditingController(text: '0');
  final _agreed = TextEditingController();
  final _advance = TextEditingController(text: '0');
  final _issue = TextEditingController();

  bool _hydratingEdit = false;
  bool _saving = false;
  Object? _error;
  String? _errorText;

  int? _customerId;
  bool _suspendCustomerIdClear = false;

  DateTime? _openedAtUtc;
  DateTime? _workStartedAtUtc;
  String? _promisedDeliveryStoredIso;

  int _etaHours = 0;
  int _etaMinutes = 0;

  int? _serviceId;
  String? _serviceName;
  String _status = 'pending';

  final DatabaseHelper _customersDb = DatabaseHelper();

  @override
  void initState() {
    super.initState();
    _customerName.addListener(_onCustomerNameTyped);
    if (widget.isEdit) {
      _hydratingEdit = true;
      unawaited(_load());
    }
  }

  void _onCustomerNameTyped() {
    if (_suspendCustomerIdClear) return;
    if (_customerId != null && mounted) {
      setState(() => _customerId = null);
    }
  }

  @override
  void dispose() {
    _customerName.removeListener(_onCustomerNameTyped);
    _customerName.dispose();
    _customerFocus.dispose();
    _deviceName.dispose();
    _deviceSerial.dispose();
    _estimated.dispose();
    _agreed.dispose();
    _advance.dispose();
    _issue.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _errorText = null;
    });
    try {
      final gid = widget.editOrderGlobalId;
      if (gid == null || gid.trim().isEmpty) {
        throw StateError('missing_global_id');
      }
      final r = await ServiceOrdersRepository.instance.getServiceOrderByGlobalId(gid);
      if (!mounted) return;
      if (r == null) throw StateError('not_found');
      final svcId = (r['serviceId'] as num?)?.toInt();
      String? svcName;
      if (svcId != null && svcId > 0) {
        final row = await ProductRepository().getProductById(svcId);
        svcName = row == null ? null : (row['name'] ?? '').toString().trim();
      }
      final edm = (r['expectedDurationMinutes'] as num?)?.toInt() ?? 0;
      final h = edm > 0 ? edm ~/ 60 : 0;
      final m = edm > 0 ? edm % 60 : 0;
      setState(() {
        _customerId = (r['customerId'] as num?)?.toInt();
        _customerName.text = (r['customerNameSnapshot'] ?? '').toString();
        _deviceName.text = (r['deviceName'] ?? '').toString();
        _deviceSerial.text = (r['deviceSerial'] ?? '').toString();
        _status = (r['status'] ?? 'pending').toString();
        _serviceId = svcId;
        _serviceName = svcName;
        _estimated.text = IraqiCurrencyFormat.formatDecimal2(
          IqdMoney.fromFils((r['estimatedPriceFils'] as num?)?.toInt() ?? 0),
        );
        final agreedF = (r['agreedPriceFils'] as num?)?.toInt();
        _agreed.text = agreedF == null
            ? ''
            : IraqiCurrencyFormat.formatDecimal2(IqdMoney.fromFils(agreedF));
        _advance.text = IraqiCurrencyFormat.formatDecimal2(
          IqdMoney.fromFils((r['advancePaymentFils'] as num?)?.toInt() ?? 0),
        );
        _issue.text = (r['issueDescription'] ?? '').toString();
        _openedAtUtc =
            DateTime.tryParse((r['createdAt'] ?? '').toString())?.toUtc();
        _workStartedAtUtc =
            DateTime.tryParse((r['workStartedAt'] ?? '').toString())?.toUtc();
        _etaHours = h;
        _etaMinutes = m;
        final pd = (r['promisedDeliveryAt'] ?? '').toString().trim();
        _promisedDeliveryStoredIso = pd.isEmpty ? null : pd;
        _hydratingEdit = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorText = _friendlyError(e);
        _hydratingEdit = false;
      });
    }
  }

  String _friendlyError(Object e) {
    final raw = e.toString();
    if (raw.contains('TenantContextService') || raw.contains('tenant')) {
      return 'تعذر تحديد بيانات المستأجر. أعد فتح التطبيق ثم حاول مرة أخرى.';
    }
    if (raw.contains('no such table') || raw.contains('no such column')) {
      return 'قاعدة البيانات تحتاج تهيئة/تحديث. أعد فتح التطبيق ثم حاول مرة أخرى.';
    }
    return 'حدث خطأ غير متوقع أثناء الحفظ.';
  }

  int _parseFils(TextEditingController c) {
    final raw = c.text.trim().replaceAll(',', '');
    final v = double.tryParse(raw) ?? 0;
    return IqdMoney.toFils(v);
  }

  int? _etaTotalMinutes() {
    final t = _etaHours * 60 + _etaMinutes;
    return t > 0 ? t : null;
  }

  Future<void> _openNewCustomer() async {
    if (_hydratingEdit || _saving) return;
    final rec = await Navigator.of(context).push<CustomerRecord>(
      MaterialPageRoute(
        builder: (_) => const CustomerFormScreen(),
      ),
    );
    if (!mounted || rec == null) return;
    _suspendCustomerIdClear = true;
    setState(() {
      _customerId = rec.id;
      _customerName.text = rec.name.trim();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suspendCustomerIdClear = false;
    });
  }

  Future<void> _openDurationWheel() async {
    if (_hydratingEdit || _saving) return;
    var h = _etaHours.clamp(0, 72);
    var m = _etaMinutes.clamp(0, 59);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 4),
                    child: Text(
                      'المدة المتوقعة لإنجاز العمل',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                      textAlign: TextAlign.start,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'ساعات',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            'دقائق',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 200,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        children: [
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: FixedExtentScrollController(
                                initialItem: h,
                              ),
                              itemExtent: 32,
                              onSelectedItemChanged: (i) {
                                h = i;
                                setModal(() {});
                              },
                              children: [
                                for (var i = 0; i <= 72; i++)
                                  Center(child: Text('$i')),
                              ],
                            ),
                          ),
                          Expanded(
                            child: CupertinoPicker(
                              scrollController: FixedExtentScrollController(
                                initialItem: m,
                              ),
                              itemExtent: 32,
                              onSelectedItemChanged: (i) {
                                m = i;
                                setModal(() {});
                              },
                              children: [
                                for (var i = 0; i < 60; i++)
                                  Center(child: Text('$i')),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 12),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('إلغاء'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: () {
                            setState(() {
                              _etaHours = h;
                              _etaMinutes = m;
                            });
                            Navigator.pop(ctx);
                          },
                          child: const Text('تم'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (mounted) setState(() {});
  }

  String _durationSummaryLabel() {
    final t = _etaHours * 60 + _etaMinutes;
    if (t <= 0) return 'لم تُحدَّد — اضغط لاختيار الساعات والدقائق';
    if (_etaHours > 0 && _etaMinutes > 0) {
      return '$_etaHours س $_etaMinutes د — اضغط للتعديل';
    }
    if (_etaHours > 0) return '$_etaHours ساعة — اضغط للتعديل';
    return '$_etaMinutes دقيقة — اضغط للتعديل';
  }

  Widget _buildScheduleBanner(ColorScheme cs) {
    final mins = _etaTotalMinutes();
    DateTime? targetLocal;
    if (mins != null) {
      final base = (_workStartedAtUtc ?? _openedAtUtc ?? DateTime.now().toUtc())
          .toLocal();
      targetLocal = base.add(Duration(minutes: mins));
    } else if (_promisedDeliveryStoredIso != null) {
      targetLocal =
          DateTime.tryParse(_promisedDeliveryStoredIso!)?.toLocal();
    }

    if (targetLocal == null && mins == null) return const SizedBox.shrink();

    final formatter = DateFormat('EEEE، d MMMM yyyy • HH:mm', 'ar');
    final overdue = targetLocal != null &&
        DateTime.now().isAfter(targetLocal) &&
        _status != 'delivered' &&
        _status != 'cancelled';

    final subtitle = _workStartedAtUtc == null && mins != null
        ? 'بعد «بدء العمل» من قائمة التذاكر يُثبَّت الموعد بدقة من وقت البدء.'
        : (mins != null
            ? 'مدة العمل المتوقعة: $mins دقيقة'
            : null);

    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: overdue
            ? cs.errorContainer.withValues(alpha: 0.35)
            : cs.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: overdue
              ? cs.error.withValues(alpha: 0.35)
              : cs.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                overdue ? Icons.warning_amber_rounded : Icons.schedule_rounded,
                color: overdue ? cs.error : cs.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  overdue
                      ? 'تجاوز موعد التسليم المتوقع'
                      : 'موعد التسليم المتوقع (للزبون)',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: overdue ? cs.error : cs.onPrimaryContainer,
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
          if (targetLocal != null) ...[
            const SizedBox(height: 6),
            Text(
              formatter.format(targetLocal),
              style: TextStyle(
                color: overdue ? cs.onErrorContainer : cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.start,
            ),
          ],
          if (subtitle != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                textAlign: TextAlign.start,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _applyServicePricing(int? productId) async {
    if (productId == null || productId <= 0) {
      if (!mounted) return;
      setState(() {
        _estimated.text = IraqiCurrencyFormat.formatDecimal2(0);
      });
      return;
    }
    final row = await ProductRepository().getProductById(productId);
    if (!mounted) return;
    final sp = (row?['sellPrice'] as num?)?.toDouble() ?? 0.0;
    setState(() {
      _estimated.text = IraqiCurrencyFormat.formatDecimal2(sp);
      _agreed.clear();
    });
  }

  Future<void> _pickService() async {
    final repo = ProductRepository();
    final rows = await repo.getProducts();
    if (!mounted) return;
    final services = rows
        .where((e) => ((e['isService'] as num?)?.toInt() ?? 0) == 1)
        .toList(growable: false);

    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final search = TextEditingController();
        return StatefulBuilder(builder: (ctx, setModal) {
          final q = search.text.trim().toLowerCase();
          final filtered = services.where((s) {
            if (q.isEmpty) return true;
            final n = (s['name'] ?? '').toString().toLowerCase();
            final bc = (s['barcode'] ?? '').toString().toLowerCase();
            return n.contains(q) || bc.contains(q);
          }).toList(growable: false);

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 12, 8),
                  child: TextField(
                    controller: search,
                    onChanged: (_) => setModal(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'بحث في الخدمات…',
                      isDense: true,
                    ),
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final s = filtered[i];
                      final name = (s['name'] ?? '').toString();
                      final id = (s['id'] as num?)?.toInt();
                      final sell = (s['sell'] as num?)?.toDouble() ?? 0;
                      return ListTile(
                        title: Text(name.isEmpty ? 'خدمة' : name),
                        subtitle: Text(
                          IraqiCurrencyFormat.formatIqd(sell),
                          textDirection: TextDirection.ltr,
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: id == null ? null : () => Navigator.pop(ctx, s),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          );
        });
      },
    );

    if (picked == null) return;
    final pid = (picked['id'] as num?)?.toInt();
    setState(() {
      _serviceId = pid;
      _serviceName = (picked['name'] ?? '').toString().trim();
    });
    await _applyServicePricing(pid);
  }

  Future<void> _submit() async {
    if (_hydratingEdit || _saving) return;
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    var serialOut = _deviceSerial.text.trim();
    if (serialOut.isEmpty) {
      serialOut =
          'REF-${DateTime.now().millisecondsSinceEpoch % 100000000}';
      _deviceSerial.text = serialOut;
    }

    final estF = _parseFils(_estimated);
    final agreedRaw = _agreed.text.trim().replaceAll(',', '');
    final agreedD = agreedRaw.isEmpty ? null : double.tryParse(agreedRaw);
    final agreedF = agreedD == null ? null : IqdMoney.toFils(agreedD);
    final advF = _parseFils(_advance);

    final etaMins = _etaTotalMinutes();
    String? promIso;
    if (_workStartedAtUtc != null && etaMins != null && etaMins > 0) {
      promIso = _workStartedAtUtc!
          .add(Duration(minutes: etaMins))
          .toIso8601String();
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.isEdit) {
        await ServiceOrdersRepository.instance.updateServiceOrderById(
          widget.editOrderId!,
          patchCustomerIdField: true,
          customerId: _customerId,
          customerNameSnapshot: _customerName.text.trim(),
          deviceName: _deviceName.text.trim(),
          deviceSerial: serialOut,
          serviceId: _serviceId,
          estimatedPriceFils: estF,
          agreedPriceFils: agreedF,
          advancePaymentFils: advF,
          status: _status,
          issueDescription: _issue.text.trim(),
          patchEtaFields: true,
          expectedDurationMinutes: etaMins,
          promisedDeliveryAt: promIso,
        );
      } else {
        await ServiceOrdersRepository.instance.createServiceOrder(
          customerId: _customerId,
          customerNameSnapshot: _customerName.text.trim(),
          deviceName: _deviceName.text.trim(),
          deviceSerial: serialOut,
          serviceId: _serviceId,
          estimatedPriceFils: estF,
          agreedPriceFils: agreedF,
          advancePaymentFils: advF,
          status: _status,
          issueDescription: _issue.text.trim(),
          expectedDurationMinutes: etaMins,
          promisedDeliveryAt: null,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _errorText = _friendlyError(e);
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_hydratingEdit && widget.isEdit) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final busy = _hydratingEdit || _saving;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit ? 'تعديل تذكرة' : 'تذكرة جديدة'),
        actions: [
          IconButton(
            tooltip: 'حفظ',
            onPressed: busy ? null : _submit,
            icon: const Icon(Icons.save_rounded),
          ),
        ],
      ),
      body: AdaptiveFormContainer(
        child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 22),
          children: [
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.error.withValues(alpha: 0.25)),
                ),
                child: Text(
                  (_errorText ?? 'حدث خطأ أثناء الحفظ. حاول مرة أخرى.'),
                  style: TextStyle(color: cs.error),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _buildScheduleBanner(cs),
            if (_etaTotalMinutes() != null || _promisedDeliveryStoredIso != null)
              const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: RawAutocomplete<CustomerRecord>(
                    textEditingController: _customerName,
                    focusNode: _customerFocus,
                    displayStringForOption: (c) => c.name,
                    optionsBuilder: (tv) async {
                      final q = tv.text.trim();
                      if (q.isEmpty) {
                        return const Iterable<CustomerRecord>.empty();
                      }
                      await Future<void>.delayed(
                        const Duration(milliseconds: 240),
                      );
                      if (!mounted || _customerName.text.trim() != q) {
                        return const Iterable<CustomerRecord>.empty();
                      }
                      final rows = await _customersDb.queryCustomersPage(
                        query: q,
                        statusArabic: 'الكل',
                        sortKey: 'name_asc',
                        limit: 20,
                        offset: 0,
                      );
                      return rows.map(CustomerRecord.fromMap);
                    },
                    onSelected: (c) {
                      _suspendCustomerIdClear = true;
                      setState(() {
                        _customerId = c.id;
                        _customerName.text = c.name.trim();
                        _customerName.selection = TextSelection.collapsed(
                          offset: _customerName.text.length,
                        );
                      });
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _suspendCustomerIdClear = false;
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'اسم العميل',
                          border: const OutlineInputBorder(),
                          hintText: 'ابدأ الكتابة للبحث في العملاء',
                          suffixIcon: _customerId != null
                              ? Icon(Icons.link_rounded, color: cs.primary)
                              : null,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'اسم العميل مطلوب'
                                : null,
                        textAlign: TextAlign.start,
                        onFieldSubmitted: (_) => onSubmit(),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      final list = options.toList();
                      return Align(
                        alignment: AlignmentDirectional.topStart,
                        child: Material(
                          elevation: 6,
                          borderRadius: BorderRadius.circular(12),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: list.length,
                              itemBuilder: (ctx, i) {
                                final c = list[i];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    c.name.trim().isEmpty ? 'عميل' : c.name,
                                    textAlign: TextAlign.start,
                                  ),
                                  subtitle: c.phone == null ||
                                          c.phone!.trim().isEmpty
                                      ? null
                                      : Text(
                                          c.phone!,
                                          textDirection: TextDirection.ltr,
                                          textAlign: TextAlign.start,
                                        ),
                                  onTap: () => onSelected(c),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'عميل جديد',
                  onPressed: busy ? null : _openNewCustomer,
                  icon: const Icon(Icons.person_add_alt_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _deviceName,
              decoration: const InputDecoration(
                labelText: 'اسم الجهاز / السيارة',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'اسم الجهاز مطلوب' : null,
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _deviceSerial,
              decoration: const InputDecoration(
                labelText: 'رقم تسلسلي / لوحة (اختياري)',
                border: OutlineInputBorder(),
              ),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, top: 4),
              child: Text(
                'إن تُرك فارغاً يُولَّد تلقائياً رقم مرجعي داخلي للتذكرة (وليس سيريال الجهاز).',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.start,
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: busy ? null : _openDurationWheel,
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
                  child: Row(
                    children: [
                      Icon(Icons.access_time_filled_rounded, color: cs.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'المدة المتوقعة',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                              textAlign: TextAlign.start,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _durationSummaryLabel(),
                              style: TextStyle(
                                fontSize: 13,
                                color: cs.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.start,
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_left_rounded, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('الخدمة'),
              subtitle: Text(
                _serviceName?.trim().isNotEmpty == true
                    ? _serviceName!
                    : (_serviceId == null ? 'غير محددة (اختياري)' : 'محددة'),
              ),
              trailing: OutlinedButton.icon(
                onPressed: busy ? null : _pickService,
                icon: const Icon(Icons.search_rounded),
                label: const Text('اختيار'),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _estimated,
                    readOnly: true,
                    enableInteractiveSelection: true,
                    decoration: const InputDecoration(
                      labelText: 'سعر تقديري (من الخدمة)',
                      border: OutlineInputBorder(),
                      helperText: 'يُملأ تلقائياً من سعر الخدمة',
                    ),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _agreed,
                    decoration: const InputDecoration(
                      labelText: 'السعر المتفق عليه (د.ع)',
                      border: OutlineInputBorder(),
                      helperText: 'المكان الوحيد لتعديل السعر',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final s = (v ?? '').trim().replaceAll(',', '');
                      if (s.isEmpty) return null;
                      final n = double.tryParse(s);
                      if (n == null || n < 0) return 'أدخل مبلغاً صحيحاً';
                      return null;
                    },
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _advance,
                    decoration: const InputDecoration(
                      labelText: 'عربون/دفعة مقدمة (د.ع)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      final n =
                          double.tryParse((v ?? '').trim().replaceAll(',', ''));
                      if (n == null || n < 0) return 'أدخل مبلغاً صحيحاً';
                      return null;
                    },
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _issue,
              decoration: const InputDecoration(
                labelText: 'وصف المشكلة (اختياري)',
                border: OutlineInputBorder(),
              ),
              minLines: 2,
              maxLines: 5,
              textAlign: TextAlign.start,
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: busy ? null : _submit,
              child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ التذكرة'),
            ),
          ],
        ),
      ),
      ),
    );
  }
}
