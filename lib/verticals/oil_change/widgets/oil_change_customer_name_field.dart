import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/customer_record.dart';
import '../../../services/database_helper.dart';

/// حقل اسم العميل مع اقتراحات داخل التخطيط — بدون [RawAutocomplete]/OverlayPortal.
class OilChangeCustomerNameField extends StatefulWidget {
  const OilChangeCustomerNameField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSelected,
    this.customerLinked = false,
    this.enabled = true,
    this.hintText = 'ابحث أو اكتب الاسم',
    this.validator,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<CustomerRecord> onSelected;
  final bool customerLinked;
  final bool enabled;
  final String hintText;
  final FormFieldValidator<String>? validator;

  @override
  State<OilChangeCustomerNameField> createState() =>
      _OilChangeCustomerNameFieldState();
}

class _OilChangeCustomerNameFieldState extends State<OilChangeCustomerNameField> {
  final _customersDb = DatabaseHelper();
  List<CustomerRecord> _options = const [];
  bool _showOptions = false;
  Timer? _debounce;
  int _queryGen = 0;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    _debounce?.cancel();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.focusNode.hasFocus) return;
        setState(() => _showOptions = false);
      });
      return;
    }
    unawaited(_scheduleOptionsQuery());
  }

  void _onTextChanged() {
    if (!widget.focusNode.hasFocus) return;
    unawaited(_scheduleOptionsQuery());
  }

  Future<void> _scheduleOptionsQuery() async {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 240), () {
      unawaited(_loadOptions());
    });
  }

  Future<void> _loadOptions() async {
    final gen = ++_queryGen;
    final q = widget.controller.text.trim();
    if (q.isEmpty || !widget.focusNode.hasFocus) {
      if (!mounted) return;
      setState(() {
        _options = const [];
        _showOptions = false;
      });
      return;
    }

    final rows = await _customersDb.queryCustomersPage(
      query: q,
      statusArabic: 'الكل',
      sortKey: 'name_asc',
      limit: 20,
      offset: 0,
    );
    if (!mounted || gen != _queryGen) return;
    if (widget.controller.text.trim() != q || !widget.focusNode.hasFocus) return;

    final options = rows.map(CustomerRecord.fromMap).toList();
    setState(() {
      _options = options;
      _showOptions = options.isNotEmpty;
    });
  }

  void _pick(CustomerRecord customer) {
    setState(() => _showOptions = false);
    widget.onSelected(customer);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.focusNode.unfocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: widget.controller,
          focusNode: widget.focusNode,
          enabled: widget.enabled,
          decoration: InputDecoration(
            labelText: 'اسم العميل',
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: widget.hintText,
            suffixIcon: widget.customerLinked
                ? Icon(Icons.link_rounded, color: cs.primary)
                : null,
          ),
          validator: widget.validator,
          textAlign: TextAlign.start,
          onFieldSubmitted: (_) => widget.focusNode.unfocus(),
        ),
        if (_showOptions && _options.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 4),
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              color: cs.surface,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _options.length,
                  itemBuilder: (context, index) {
                    final c = _options[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        c.name.trim().isEmpty ? 'عميل' : c.name,
                        textAlign: TextAlign.start,
                      ),
                      subtitle: c.phone == null || c.phone!.trim().isEmpty
                          ? null
                          : Text(
                              c.phone!,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.start,
                            ),
                      onTap: widget.enabled ? () => _pick(c) : null,
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}
