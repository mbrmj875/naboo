part of '../oil_change_order_form_screen.dart';

// الغسيل داخل بطاقة الغيار: الأنواع من كتالوج الغسيل، وعرض «غسلة مع الغيار»،
// وعامل الغسيل. مبلغ الغسلة بعد العرض يدخل إجمالي البطاقة.
extension _OilFormWash on _OilChangeOrderFormScreenState {
  /// كتالوج الغسيل وعرض «غسلة مع الغيار». الفشل لا يوقف البطاقة.
  Future<void> _loadCardWashCatalog() async {
    List<CarWashServiceItem> cat = const [];
    var offer = const WithOilWashOffer();
    try {
      cat = await CarWashServicesRepository.instance.listActive();
    } catch (_) {}
    try {
      offer = (await StorePolicySettingsRepository.instance.load()).withOilWash;
    } catch (_) {}
    if (!mounted) return;
    _rebuild(() {
      _washCatalog = cat;
      _withOilOffer = offer;
    });
    if (_cardWashSelected.isNotEmpty) _recalculateOilTotal();
  }

  /// الأنواع بترتيب الكتالوج، ثم المحفوظة في البطاقة وقد حُذفت من الكتالوج.
  List<String> get _cardWashOrderedNames {
    final out = <String>[
      for (final s in _washCatalog)
        if (_cardWashSelected.contains(s.name)) s.name,
    ];
    for (final n in _cardWashSelected) {
      if (!out.contains(n)) out.add(n);
    }
    return out;
  }

  int _cardWashPriceFor(String name) {
    final saved = _cardWashSaved?.lines.where((l) => l.name == name);
    if (saved != null && saved.isNotEmpty) return saved.first.priceFils;
    for (final s in _washCatalog) {
      if (s.name == name) return s.priceFils;
    }
    return 0;
  }

  String _cardWashSelectionSig(Iterable<String> names) =>
      (names.toList()..sort()).join('\u{1f}');

  /// الغسلة كما ستُحفظ، أو null إن لم يُختر نوع.
  OilCardWash? get _cardWash {
    if (_cardWashSelected.isEmpty) return null;
    final lines = [
      for (final n in _cardWashOrderedNames)
        OilCardWashLine(name: n, priceFils: _cardWashPriceFor(n)),
    ];
    final washer = _cardWashWasher.text.trim();
    final saved = _cardWashSaved;
    // البطاقة المحفوظة بنفس الأنواع تبقى بخصمها كما بيعت، ولو تغيّر العرض بعدها.
    if (saved != null &&
        _cardWashSelectionSig(saved.serviceNames) ==
            _cardWashSelectionSig(_cardWashSelected)) {
      return OilCardWash(
        lines: lines,
        washerName: washer,
        discountFils: saved.discountFils,
        offerCode: saved.offerCode,
        offerNote: saved.offerNote,
      );
    }
    final r = WashOfferEngine.withOil(
      offer: _withOilOffer,
      currentServicePrices: {for (final l in lines) l.name: l.priceFils},
    );
    return OilCardWash(
      lines: lines,
      washerName: washer,
      discountFils: r.discountFils,
      offerCode: r.code,
      offerNote: r.reasonAr,
    );
  }

  int _cardWashNetFils() => _cardWash?.netFils ?? 0;

  void _hydrateCardWash(Map<String, dynamic> row) {
    final w = OilCardWash.fromOrder(row);
    _cardWashSaved = w;
    _cardWashSelected
      ..clear()
      ..addAll(w?.serviceNames ?? const []);
    _cardWashWasher.text = w?.washerName ?? '';
  }

  void _clearCardWash() {
    _cardWashSaved = null;
    _cardWashSelected.clear();
    _cardWashWasher.clear();
  }

  String _cardWashLeaveSig() =>
      '${_cardWashSelectionSig(_cardWashSelected)}|${_cardWashWasher.text.trim()}';

  String? _cardWashCollapsedHint() {
    final w = _cardWash;
    if (w == null) return null;
    if (w.isFree) return 'مجانية';
    return _formatFilsLabel(w.netFils);
  }

  void _toggleCardWashType(String name) {
    _rebuild(() {
      if (!_cardWashSelected.remove(name)) _cardWashSelected.add(name);
      _agreedTotalManual = false;
      _recalculateOilTotal();
    });
  }

  List<Widget> _buildCardWashSectionChildren(ColorScheme cs, bool busy) {
    final names = <String>[
      for (final s in _washCatalog) s.name,
      for (final n in _cardWashSelected)
        if (!_washCatalog.any((s) => s.name == n)) n,
    ];
    if (names.isEmpty) {
      return [
        Text(
          'لا توجد أنواع غسيل. أضفها من «أنواع الغسيل وأسعارها».',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          textAlign: TextAlign.start,
        ),
      ];
    }
    final w = _cardWash;
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final n in names) _buildCardWashTypeChip(n, cs, busy),
        ],
      ),
      if (w != null) ...[
        const SizedBox(height: 10),
        _buildCardWashPriceLine(w, cs),
        const SizedBox(height: 10),
        OilChangeTechnicianField(
          controller: _cardWashWasher,
          enabled: !busy,
          isDense: true,
          label: 'عامل الغسيل',
          pickerTitle: 'اختر عامل الغسيل',
        ),
      ] else if (_withOilOffer.enabled) ...[
        const SizedBox(height: 8),
        Text(
          _withOilOffer.rewardType == WashRewardType.free
              ? 'عرض «غسلة مع الغيار»: الغسلة مجانية.'
              : 'عرض «غسلة مع الغيار» مفعّل.',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          textAlign: TextAlign.start,
        ),
      ],
    ];
  }

  Widget _buildCardWashPriceLine(OilCardWash w, ColorScheme cs) {
    final hasOffer = w.discountFils > 0;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasOffer)
              Text(
                'السعر: ${_formatFilsLabel(w.grossFils)} — '
                'الخصم: ${_formatFilsLabel(w.discountFils)}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                textAlign: TextAlign.start,
              ),
            Text(
              w.isFree
                  ? 'الغسلة: مجانية'
                  : 'الغسلة: ${_formatFilsLabel(w.netFils)}',
              style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary),
              textAlign: TextAlign.start,
            ),
            if ((w.offerNote ?? '').isNotEmpty)
              Text(
                w.offerNote!,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                textAlign: TextAlign.start,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardWashTypeChip(String name, ColorScheme cs, bool busy) {
    final checked = _cardWashSelected.contains(name);
    final price = _cardWashPriceFor(name);
    final priceLbl = price > 0
        ? IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(price))
        : '—';
    return InkWell(
      onTap: busy ? null : () => _toggleCardWashType(name),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: checked
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border.all(
            color: checked
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.5),
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              checked
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: checked ? cs.primary : cs.onSurfaceVariant,
              size: 18,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                // عزل الاسم والسعر: اسم إنجليزي كان يقلب السطر.
                '\u2068$name\u2069 · \u2068$priceLbl\u2069',
                style: TextStyle(
                  fontWeight: checked ? FontWeight.w800 : FontWeight.w500,
                  color: checked ? cs.primary : cs.onSurface,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
