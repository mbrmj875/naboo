import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/customer_record.dart';
import '../../../services/customer_search_index.dart';
import '../../../services/database_helper.dart';

/// حرف واحد يكفي لبدء الاقتراحات، كما في بحث الأسماء الفوري.
const int kOilCustomerFirstNameMinChars = 1;

/// هل اكتمل الاسم الأول بما يكفي لبدء البحث الذكي؟
bool oilCustomerFirstNameReady(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return false;
  final first = trimmed.split(RegExp(r'\s+')).first;
  return first.length >= kOilCustomerFirstNameMinChars;
}

/// حقل اسم العميل = بحث في سجل العملاء مع اقتراحات **تحت الحقل**.
///
/// - سريع: فهرس في الذاكرة (بدون انتظار DB لكل حرف).
/// - الاقتراحات من أول حرف، والفهرس جاهز في الذاكرة قبل الكتابة.
class OilChangeCustomerNameField extends StatefulWidget {
  const OilChangeCustomerNameField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSelected,
    this.customerLinked = false,
    this.enabled = true,
    this.hintText = 'اكتب الاسم الأول كاملاً للبحث',
    this.validator,
    this.search,
    this.prepareIndex,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<CustomerRecord> onSelected;
  final bool customerLinked;
  final bool enabled;
  final String hintText;
  final FormFieldValidator<String>? validator;

  /// للاختبارات: مصدر اقتراحات بديل.
  final List<CustomerRecord> Function(String query)? search;

  /// تحضير الفهرس (اختبارات / تخصيص).
  final Future<void> Function()? prepareIndex;

  @override
  State<OilChangeCustomerNameField> createState() =>
      _OilChangeCustomerNameFieldState();
}

class _OilChangeCustomerNameFieldState
    extends State<OilChangeCustomerNameField> {
  static const _maxSuggestions = 8;

  List<CustomerRecord> _options = const [];
  bool _showOptions = false;
  String? _lastQuery;
  Future<void>? _prepareInFlight;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChanged);
    widget.controller.addListener(_onTextChanged);
    // جهّز فهرس البحث مبكراً حتى تظهر القائمة فور اكتمال الاسم الأول.
    unawaited(_ensureIndexReady());
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChanged);
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    if (!widget.focusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.focusNode.hasFocus) return;
        _lastQuery = null;
        _clearSuggestions();
      });
      return;
    }
    unawaited(_ensureIndexReady());
    _refreshOptions(force: true);
  }

  Future<void> _ensureIndexReady() async {
    if (widget.search != null) return;
    if (CustomerSearchIndex.instance.isReady) return;
    final prepare =
        widget.prepareIndex ?? CustomerSearchIndex.instance.ensureFresh;
    final pending = _prepareInFlight;
    if (pending != null) {
      await pending;
      return;
    }
    final job = prepare();
    _prepareInFlight = job;
    try {
      await job;
    } finally {
      if (identical(_prepareInFlight, job)) _prepareInFlight = null;
    }
    if (!mounted) return;
    if (widget.focusNode.hasFocus) _refreshOptions(force: true);
  }

  void _onTextChanged() {
    if (!widget.focusNode.hasFocus) return;
    _refreshOptions();
  }

  void _clearSuggestions() {
    if (!_showOptions && _options.isEmpty) return;
    setState(() {
      _showOptions = false;
      _options = const [];
    });
  }

  Future<List<CustomerRecord>> _lookup(String query) async {
    if (widget.search != null) return widget.search!(query);

    if (CustomerSearchIndex.instance.isReady &&
        CustomerSearchIndex.instance.length > 0) {
      return CustomerSearchIndex.instance.searchRecords(
        query,
        limit: _maxSuggestions,
      );
    }

    await _ensureIndexReady();
    if (CustomerSearchIndex.instance.length > 0) {
      return CustomerSearchIndex.instance.searchRecords(
        query,
        limit: _maxSuggestions,
      );
    }
    final rows =
        await DatabaseHelper().searchCustomers(query, limit: _maxSuggestions);
    return [
      for (final r in rows)
        CustomerRecord.fromMap(Map<String, dynamic>.from(r)),
    ];
  }

  void _refreshOptions({bool force = false}) {
    final query = widget.controller.text.trim();
    if (!force && query == _lastQuery) return;
    _lastQuery = query;

    if (!oilCustomerFirstNameReady(query)) {
      _clearSuggestions();
      return;
    }

    if (widget.search != null ||
        (CustomerSearchIndex.instance.isReady &&
            CustomerSearchIndex.instance.length > 0)) {
      final matches = widget.search != null
          ? widget.search!(query)
          : CustomerSearchIndex.instance.searchRecords(
              query,
              limit: _maxSuggestions,
            );
      _applyMatches(matches);
      return;
    }

    unawaited(() async {
      final matches = await _lookup(query);
      if (!mounted || widget.controller.text.trim() != query) return;
      if (!widget.focusNode.hasFocus) return;
      _applyMatches(matches);
    }());
  }

  void _applyMatches(List<CustomerRecord> matches) {
    // اعرض القائمة دائماً عند وجود نتائج — التعبئة فقط بالضغط على صف.
    // (حتى التطابق الكامل: المستخدم يختار صراحةً أو يكمل كاسم جديد.)
    final shouldShow = matches.isNotEmpty;
    if (_sameOptions(matches) && shouldShow == _showOptions) return;
    setState(() {
      _options = matches;
      _showOptions = shouldShow;
    });
  }

  bool _sameOptions(List<CustomerRecord> next) {
    if (next.length != _options.length) return false;
    for (var i = 0; i < next.length; i++) {
      if (next[i].id != _options[i].id) return false;
    }
    return true;
  }

  void _pick(CustomerRecord customer) {
    setState(() {
      _showOptions = false;
      _options = const [];
    });
    widget.onSelected(customer);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.unfocus();
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
          // مساحة أسفل الحقل حتى تبقى قائمة الاقتراحات ظاهرة فوق الكيبورد.
          scrollPadding: const EdgeInsets.only(bottom: 240),
          decoration: InputDecoration(
            labelText: 'اسم العميل',
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: widget.hintText,
            suffixIcon: widget.customerLinked
                ? Icon(Icons.link_rounded, color: cs.primary)
                : Icon(
                    Icons.search_rounded,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
          ),
          validator: widget.validator,
          textAlign: TextAlign.start,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => widget.focusNode.unfocus(),
        ),
        if (_showOptions && _options.isNotEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6),
            child: Material(
              elevation: 4,
              shadowColor: Colors.black.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              color: cs.surface,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: _options.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.45),
                  ),
                  itemBuilder: (context, index) {
                    final c = _options[index];
                    final phone = c.phone?.trim() ?? '';
                    return SizedBox(
                      height: 52,
                      child: ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(
                          c.name.trim().isEmpty ? 'عميل' : c.name,
                          textAlign: TextAlign.start,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: phone.isEmpty
                            ? null
                            : Text(
                                phone,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.start,
                                maxLines: 1,
                              ),
                        onTap: widget.enabled ? () => _pick(c) : null,
                      ),
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
