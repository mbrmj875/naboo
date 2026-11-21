part of '../oil_change_order_form_screen.dart';

// أقسام واجهة بطاقة الغيار ومعالجات حقولها.
//
// امتداد على حالة الشاشة: يصل إلى حقولها الخاصة لأنه جزء من نفس المكتبة.
// لا حقول هنا؛ الحالة كلها تبقى في الشاشة.
extension _OilFormSections on _OilChangeOrderFormScreenState {
  Widget _buildOilPriceBreakdownSummary(ColorScheme cs) {
    // كل مجموع كان يُحسب مرتين (مرة في الشرط ومرة داخل النص)؛ يُحسب هنا مرة.
    final oilFils = _oilMaterialSellFilsEst();
    final gearFils = _hydraulicMaterialSellFilsEstFor(_gearHydraulic);
    final powerFils = _hydraulicMaterialSellFilsEstFor(_powerHydraulic);
    final filtersFils = _filtersTotalFils();
    final productsFils = _oilProductLinesTotalFils();
    final servicesFils = _oilServicesTotalFils();
    final notesFils = _notesExtrasFils;

    final laborFils = _oilLaborFils();
    if (laborFils <= 0 &&
        _selectedOilServiceIds.isEmpty &&
        oilFils <= 0 &&
        gearFils <= 0 &&
        powerFils <= 0 &&
        filtersFils <= 0 &&
        productsFils <= 0 &&
        notesFils <= 0) {
      return const SizedBox.shrink();
    }

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (laborFils > 0)
              Text(
                '${oilLaborLineName(customerOil: _oilCustomerProvided)}: '
                '${_formatFilsLabel(laborFils)}',
                textAlign: TextAlign.start,
              ),
            if (_selectedOilServiceIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'خدمات إضافية: ${_formatFilsLabel(_oilExtrasFils())}',
                textAlign: TextAlign.start,
              ),
            ],
            if (laborFils > 0 || _selectedOilServiceIds.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'مجموع الخدمات: ${_formatFilsLabel(servicesFils)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: cs.primary,
                ),
                textAlign: TextAlign.start,
              ),
            ],
            if (oilFils > 0) ...[
              const SizedBox(height: 4),
              Text(
                'زيت (${formatOilLitersDisplay(_oilLitersForPricing())} لتر): '
                '${_formatFilsLabel(oilFils)}',
                textAlign: TextAlign.start,
              ),
            ],
            if (gearFils > 0) ...[
              const SizedBox(height: 4),
              Text(
                'هيدروليك الكير (${formatOilLitersDisplay(_gearHydraulic.litersForPricing())} لتر): '
                '${_formatFilsLabel(gearFils)}',
                textAlign: TextAlign.start,
              ),
            ],
            if (powerFils > 0) ...[
              const SizedBox(height: 4),
              Text(
                'هيدروليك الباور (${formatOilLitersDisplay(_powerHydraulic.litersForPricing())} لتر): '
                '${_formatFilsLabel(powerFils)}',
                textAlign: TextAlign.start,
              ),
            ],
            if (filtersFils > 0) ...[
              const SizedBox(height: 4),
              Text(
                'الفلاتر: ${_formatFilsLabel(filtersFils)}',
                textAlign: TextAlign.start,
              ),
            ],
            if (productsFils > 0) ...[
              const SizedBox(height: 4),
              Text(
                'منتجات إضافية: ${_formatFilsLabel(productsFils)}',
                textAlign: TextAlign.start,
              ),
            ],
            if (notesFils > 0) ...[
              const SizedBox(height: 4),
              Text(
                'إضافات من الملاحظات: ${_formatFilsLabel(notesFils)}',
                textAlign: TextAlign.start,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'إجمالي البيع: '
              '${_formatFilsLabel(servicesFils + oilFils + gearFils + powerFils + filtersFils + productsFils + notesFils)}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.tertiary,
                fontSize: 14,
              ),
              textAlign: TextAlign.start,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOilTechnicianNotesSection(BuildContext context, bool busy) {
    return GuideAnchor(
      id: OilGuideAnchors.formTechnician,
      child: OilChangeRoyalCard.section(
        context: context,
        title: 'الفني والملاحظات',
        icon: Icons.edit_note_rounded,
        children: _buildOilTechnicianAndNotesFields(
          context,
          busy,
          compact: true,
        ),
      ),
    );
  }

  List<Widget> _buildOilTechnicianAndNotesFields(
    BuildContext context,
    bool busy, {
    required bool compact,
  }) {
    return [
      OilChangeTechnicianField(
        controller: _technicianName,
        enabled: !busy,
        isDense: compact,
      ),
      SizedBox(height: compact ? 8 : 10),
      TextFormField(
        controller: _issue,
        onTap: oilFieldSelectAllOnDoubleTap(_issue),
        enabled: !busy,
        decoration: InputDecoration(
          labelText: 'ملاحظات وتفاصيل إضافية',
          border: const OutlineInputBorder(),
          alignLabelWithHint: true,
          suffixIcon: ArabicSpeechMicButton(
            controller: _issue,
            enabled: !busy,
            onTextUpdated: () {
              _onIssueNotesChanged();
              _rebuild(() {});
            },
          ),
        ),
        minLines: compact ? 2 : 3,
        maxLines: compact ? 4 : 6,
        textAlign: TextAlign.start,
      ),
      if (_notesMoneyPreview.isNotEmpty ||
          _notesMoneyAiLoading ||
          (_issue.text.trim().length >= 12 && !_notesExtrasConfirmed))
        OilNotesMoneyPreviewBar(
          result: _notesMoneyPreview,
          enabled: !busy,
          aiLoading: _notesMoneyAiLoading,
          showAiEvenIfEmpty: _issue.text.trim().length >= 12,
          onRequestAi: busy ? null : () => unawaited(_requestNotesMoneyAi()),
          onConfirm: _confirmNotesMoneyExtras,
          onDismiss: _dismissNotesMoneyExtras,
        )
      else if (_notesExtrasConfirmed && _notesExtrasFils > 0)
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 8),
          child: Text(
            'مضاف من الملاحظات: ${IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(_notesExtrasFils))}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.primary,
            ),
            textAlign: TextAlign.start,
          ),
        ),
    ];
  }

  /// شريط الحساب: الزيارة، الدين السابق، المطلوب كله، المستلم، والرصيد بعد
  /// البيع، مع توزيع المستلم قبل الحفظ.
  Widget _buildOilAccountBar(
    BuildContext context,
    bool busy, {
    required int totalF,
    required int paidF,
  }) {
    final cs = Theme.of(context).colorScheme;
    final linked = _customerId != null && _customerId! > 0;
    final acc = OilCardAccount(
      visitFils: totalF,
      priorDebtFils: _collectibleOldDebtFils(),
      receivedFils: paidF,
    );
    String m(int f) => _formatFilsLabel(f);
    final owes = acc.balanceAfterFils > 500;

    Widget row(String label, String value, {bool strong = false, Color? color}) {
      final style = TextStyle(
        fontSize: strong ? 14 : 12.5,
        fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
        color: color ?? cs.onSurface,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: style, textAlign: TextAlign.start),
            ),
            Text(value, style: style, textDirection: TextDirection.ltr),
          ],
        ),
      );
    }

    final priorLabel = _customerOpenDebtLoading
        ? '…'
        : m(_customerOpenDebtFils);
    return Container(
      width: double.infinity,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: owes
            ? cs.errorContainer.withValues(alpha: 0.45)
            : cs.tertiaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (owes ? cs.error : cs.tertiary).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 18,
                color: owes ? cs.error : cs.tertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'حساب العميل',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
              TextButton(
                onPressed: busy ? null : _openCustomerDebtAndRefresh,
                child: const Text('عرض الدين'),
              ),
            ],
          ),
          row('هذه الزيارة', m(acc.visitFils)),
          row('دين سابق', priorLabel),
          if (linked) ...[
            row('المطلوب كله', m(acc.dueAllFils), strong: true),
            row('المستلم', m(paidF)),
            if (paidF < acc.dueAllFils)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: busy
                      ? null
                      : () => _rebuild(() {
                          _advanceManuallyEdited = true;
                          _syncingAdvance = true;
                          try {
                            _assignControllerText(
                              _advance,
                              _formatAdvanceIqd(acc.dueAllFils),
                            );
                          } finally {
                            _syncingAdvance = false;
                          }
                        }),
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: Text('استلام المطلوب كله (${m(acc.dueAllFils)})'),
                ),
              ),
            if (acc.oldDebtPaidFils > 0)
              row(
                'منه تسديد للدين السابق',
                m(acc.oldDebtPaidFils),
                color: cs.tertiary,
              ),
            if (acc.newDebtFils > 500)
              row('دين جديد من الزيارة', m(acc.newDebtFils), color: cs.error),
            const Divider(height: 10),
            row(
              'الرصيد بعد البيع',
              acc.balanceAfterFils > 500 ? m(acc.balanceAfterFils) : 'لا دين',
              strong: true,
              color: owes ? cs.error : cs.tertiary,
            ),
          ] else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'الدين باسم غير مربوط بعميل مسجّل — اختر العميل المسجّل '
                'لتحصيله من هذه البطاقة',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                textAlign: TextAlign.start,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openCustomerDebtAndRefresh() async {
    await openCustomerOpenDebtDetail(
      context,
      customerId: _customerId,
      customerName: _customerName.text.trim(),
    );
    // ربما سدّد من شاشة الدين: حدّث المبلغ والحد الأعلى للمستلم.
    if (!mounted) return;
    await _refreshCustomerOpenDebt();
    if (!mounted) return;
    _rebuild(_clampAdvanceToCheckoutTotal);
  }

  List<Widget> _oilPaymentFields(
    BuildContext context,
    bool busy, {
    required bool compact,
  }) {
    final cs = Theme.of(context).colorScheme;
    // المجاميع تُحسب مرة واحدة: كانت تُستدعى ~25 مرة في كل إعادة بناء، وكل
    // استدعاء يمرّ على كتالوج الخدمات والمنتجات والفلاتر.
    final totalF = _oilCheckoutTotalFils();
    final paidF = _parseFils(_advance);
    final remainderF = (totalF - paidF).clamp(0, totalF);
    final totalLabel = _formatFilsLabel(totalF);
    final remainderLabel = _formatFilsLabel(remainderF);
    final hasDebt = remainderF > 500;
    final customerName = _customerName.text.trim();
    final linkedCustomer = _customerId != null && _customerId! > 0;
    final showBreakdown = _oilLaborFils() > 0 ||
                _selectedOilServiceIds.isNotEmpty ||
        _cardGrandTotalFils() > 0;

    final agreedField = TextFormField(
              controller: _agreed,
              onTap: oilFieldSelectAllOnTap(_agreed),
              enabled: !busy,
              decoration: InputDecoration(
                labelText: 'الإجمالي المتفق عليه (د.ع)',
        border: const OutlineInputBorder(),
        isDense: true,
                helperText: _agreedTotalManual
                    ? 'معدّل يدوياً — «إعادة الحساب» يجمع الكل'
                    : 'زيت + فلاتر + هيدروليك + خدمات + منتجات',
                helperMaxLines: 2,
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: false,
                signed: false,
              ),
              inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
              validator: (v) {
                final s = (v ?? '').trim().replaceAll(',', '');
                if (s.isEmpty) return null;
                final n = double.tryParse(s);
                if (n == null || n < 0) return 'مبلغ غير صحيح';
                return null;
              },
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
    );

    final advanceField = TextFormField(
      controller: _advance,
      onTap: oilFieldSelectAllOnTap(_advance),
      enabled: !busy,
      decoration: InputDecoration(
        labelText: 'المبلغ المستلم',
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: const Icon(Icons.payments_outlined, size: 20),
        helperText: _collectibleOldDebtFils() > 0
            ? 'الزائد عن الزيارة يُسدَّد من الدين السابق، والناقص يُسجَّل ديناً'
            : (_advanceManuallyEdited
                  ? 'لا يتجاوز الإجمالي — الفرق إن وُجد يُسجَّل ديناً على العميل'
                  : 'يُملأ تلقائياً من الإجمالي — عدّله إن دفع أقل (لا أكثر)'),
        helperMaxLines: 2,
      ),
      keyboardType: const TextInputType.numberWithOptions(
        decimal: false,
        signed: false,
      ),
      inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
      validator: (v) {
        final s = (v ?? '').trim().replaceAll(',', '');
        if (s.isEmpty) return null;
        final n = double.tryParse(s);
        if (n == null || n < 0) return 'مبلغ غير صحيح';
        final paidF = IqdMoney.toFils(n);
        final totalF = _oilCheckoutTotalFils();
        if (totalF > 0 && paidF > _maxReceivableFils()) {
          return _collectibleOldDebtFils() > 0
              ? 'لا يتجاوز الزيارة + الدين السابق'
              : 'لا يمكن أن يتجاوز الإجمالي';
        }
        return null;
      },
    );

    Widget totalHero() {
      return Container(
        width: double.infinity,
        padding: EdgeInsetsDirectional.fromSTEB(
          compact ? 12 : 14,
          compact ? 10 : 12,
          compact ? 12 : 14,
          compact ? 10 : 12,
        ),
              decoration: BoxDecoration(
                color: AppColors.accentGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
            color: AppColors.accentGold.withValues(alpha: 0.55),
                ),
              ),
              child: Row(
                children: [
            Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.accentGold,
              size: compact ? 20 : 22,
                  ),
            const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'الإجمالي',
                          style: TextStyle(
                      fontSize: compact ? 12 : 13,
                            color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                          ),
                          textAlign: TextAlign.start,
                        ),
                        Text(
                          totalLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                      fontSize: compact ? 18 : 22,
                            color: AppColors.accentGold,
                          ),
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                        ),
                      ],
                    ),
            ),
            if (totalF > 0 && _advanceManuallyEdited)
              IconButton(
                tooltip: 'إرجاع المبلغ المستلم إلى الإجمالي',
                onPressed: busy
                    ? null
                    : () => _rebuild(_resetOilCheckoutAutoAdvance),
                icon: Icon(Icons.undo_rounded, color: cs.primary, size: 20),
                  ),
                ],
              ),
      );
    }

    Widget debtBanner() {
      // دين سابق: شريط حساب واحد بدل اللافتة المنفصلة أعلى البطاقة.
      if (_customerOpenDebtFils > 0 || _customerOpenDebtLoading) {
        return _buildOilAccountBar(context, busy, totalF: totalF, paidF: paidF);
      }
      if (totalF <= 0) return const SizedBox.shrink();
      if (!hasDebt) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: cs.tertiary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'مسدّد بالكامل — لا دين',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onTertiaryContainer,
                  ),
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
        );
      }

      final debtText = linkedCustomer && customerName.isNotEmpty
          ? 'دين على $customerName: $remainderLabel'
          : 'متبقي (دين): $remainderLabel';

      return Container(
        width: double.infinity,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: cs.errorContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.account_balance_wallet_outlined, color: cs.error, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(
                    debtText,
                  style: TextStyle(
                    fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: cs.onErrorContainer,
                  ),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                ),
                  if (!linkedCustomer) ...[
                    const SizedBox(height: 4),
                Text(
                      'اختر عميلاً مسجّلاً لربط الدين بحسابه',
                  style: TextStyle(
                        fontSize: 11,
                        color: cs.onErrorContainer.withValues(alpha: 0.85),
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
            ],
              ),
            ),
          ],
        ),
      );
    }

    return [
      totalHero(),
      SizedBox(height: compact ? 8 : 10),
      advanceField,
      SizedBox(height: compact ? 8 : 10),
      debtBanner(),
      if (showBreakdown) ...[
        SizedBox(height: compact ? 8 : 10),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 4),
            title: Text(
              'تفاصيل الأسعار',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: cs.primary,
              ),
              textAlign: TextAlign.start,
            ),
            children: [
              if (compact) _buildOilPriceBreakdownSummary(cs) else ...[
                _buildOilPriceBreakdownSummary(cs),
                const SizedBox(height: 8),
              ],
              agreedField,
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          _rebuild(() {
                            _agreedTotalManual = false;
                            _advanceManuallyEdited = false;
                            _recalculateOilTotal();
                          });
                        },
                  icon: const Icon(Icons.calculate_outlined, size: 18),
                  label: const Text('إعادة حساب الإجمالي'),
                  style: TextButton.styleFrom(
                    visualDensity: compact
                        ? VisualDensity.compact
                        : VisualDensity.standard,
                    padding: compact ? EdgeInsets.zero : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ] else ...[
        SizedBox(height: compact ? 6 : 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: busy
                ? null
                : () {
                    _rebuild(() {
                      _agreedTotalManual = false;
                      _advanceManuallyEdited = false;
                      _recalculateOilTotal();
                    });
                  },
            icon: const Icon(Icons.calculate_outlined, size: 18),
            label: const Text('إعادة حساب الإجمالي'),
            style: TextButton.styleFrom(
              visualDensity: compact ? VisualDensity.compact : VisualDensity.standard,
              padding: compact ? EdgeInsets.zero : null,
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildOilCheckoutActionButtons(BuildContext context, bool busy) {
    return [
      const SizedBox(height: 12),
            if (widget.isOilNewCard) ...[
              GuideAnchor(
                id: OilGuideAnchors.formSuspend,
                child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accentGold,
                    side: BorderSide(
                      color: AppColors.accentGold.withValues(alpha: 0.65),
                    ),
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  onPressed: busy
                      ? null
                      : () => _submit(intent: _OilSubmitIntent.suspend),
                  icon: const Icon(Icons.pause_circle_outline_rounded),
                  label: Text(
                    _saving ? 'جارٍ التعليق…' : 'تعليق الفاتورة',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              ),
              const SizedBox(height: 10),
            ] else if (_oilEditCompletingSuspended &&
                !widget.amendInvoicedOrder) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accentGold,
                    side: BorderSide(
                      color: AppColors.accentGold.withValues(alpha: 0.65),
                    ),
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                  ),
                  onPressed: busy
                      ? null
                      : () => _submit(intent: _OilSubmitIntent.suspend),
                  icon: const Icon(Icons.pause_circle_outline_rounded),
                  label: Text(
                    _saving ? 'جارٍ التعليق…' : 'إعادة التعليق',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            GuideAnchor(
              id: OilGuideAnchors.formSave,
              child: SizedBox(
              width: double.infinity,
              child: widget.isEdit
                  ? FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentGold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      onPressed: busy
                          ? null
                          : () => _submit(
                                openInvoice: _oilEditOffersSale &&
                                    !widget.amendInvoicedOrder,
                              ),
                      icon: Icon(
                        widget.amendInvoicedOrder
                            ? Icons.edit_rounded
                            : (_oilEditOffersSale
                                ? Icons.point_of_sale_rounded
                                : Icons.save_rounded),
                      ),
                      label: Text(
                        _saving
                            ? 'جارٍ الحفظ…'
                            : (widget.amendInvoicedOrder
                                ? 'حفظ التعديل على الفاتورة'
                                : (_oilEditOffersSale
                                    ? 'حفظ وبيع'
                                    : 'حفظ')),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    )
                  : FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentGold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      onPressed: busy ? null : () => _submit(openInvoice: true),
                      icon: const Icon(Icons.point_of_sale_rounded),
                      label: Text(
                        _saving ? 'جارٍ الحفظ…' : 'حفظ وبيع',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
            ),
            ),
    ];
  }

  List<Widget> _oilCheckoutFields(
    BuildContext context,
    bool busy, {
    required bool compact,
  }) {
    return [
      ..._oilPaymentFields(context, busy, compact: compact),
      ..._buildOilCheckoutActionButtons(context, busy),
    ];
  }


  String _formatFilsLabel(int fils) {
    if (fils <= 0) return '—';
    return IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(fils));
  }

  int _oilExtrasFils() {
    var extras = 0;
    for (final s in _oilCatalog) {
      if (_selectedOilServiceIds.contains(s.id)) {
        extras += s.priceFils;
      }
    }
    return extras;
  }

  int _oilServicesTotalFils() => _oilLaborFils() + _oilExtrasFils();

  double? _selectedOilSellPerLiterIqd() {
    if (_oilPickSellPerLiter != null && _oilPickSellPerLiter! > 0) {
      return _oilPickSellPerLiter;
    }
    final pid = _oilStockProductId;
    if (pid == null) return null;
    for (final p in _oilProducts) {
      if ((p['id'] as num).toInt() == pid) {
        return (p['sellPrice'] as num?)?.toDouble();
      }
    }
    return null;
  }

  int _oilMaterialSellFilsEst() {
    if (_oilCustomerProvided) return 0;
    final ml = parseOilVolumeDisplay(_oilSizeAmount.text);
    if (ml <= 0) return 0;
    if (_usesShopOilFromStock || _usesWarehouseOilPicker) {
      final sell = _selectedOilSellPerLiterIqd();
      if (sell == null || sell <= 0) return 0;
      if ((_oilStockProductId ?? 0) <= 0) return 0;
      return sellFilsForVolumeMl(
        sellPerLiterFils: IqdMoney.toFils(sell),
        milliliters: ml,
      );
    }
    if (_usesCatalogOilPricing) {
      return sellFilsForVolumeMl(
        sellPerLiterFils: _catalogSellPerLiterFils!,
        milliliters: ml,
      );
    }
    return 0;
  }

  bool get _usesShopOilFromStock =>
      _stockFromWarehouseEnabled &&
      !_oilCustomerProvided &&
      _oilStockProductId != null &&
      _oilStockProductId! > 0;

  void _onOilFamilyDropdownChanged(int? familyKey) {
    _markOilFluidUserEdited();
    _rebuild(() {
      _selectedOilFamilyKey = familyKey;
      _oilStockProductId = null;
      _oilPickSellPerLiter = null;
      _selectedViscosity = null;
      _oilAvailableLiters = 0;
      _catalogSellPerLiterFils = null;
      if (familyKey != null) {
        final lines = _oilStockPickLines
            .where((l) => _OilChangeOrderFormScreenState._oilFamilyKey(l) == familyKey)
            .toList();
        if (lines.length == 1) {
          _applyOilStockLine(lines.first);
        }
      }
    });
    if ((_oilStockProductId ?? 0) > 0) {
      unawaited(_refreshAvailableLiters());
      _recalculateOilTotal();
    }
  }

  void _onOilStockViscosityChanged(int? linkedProductId) {
    _markOilFluidUserEdited();
    if (linkedProductId == null) {
      _rebuild(() {
        _oilStockProductId = null;
        _oilPickSellPerLiter = null;
        _selectedViscosity = null;
        _oilAvailableLiters = 0;
      });
      _recalculateOilTotal();
      return;
    }
    OilPickLine? line;
    for (final l in _oilStockLinesForSelectedFamily) {
      if (l.linkedProductId == linkedProductId) {
        line = l;
        break;
      }
    }
    if (line == null) return;
    final picked = line;
    _rebuild(() => _applyOilStockLine(picked));
    _syncStockLitersFromStepper();
    unawaited(_refreshAvailableLiters());
    _recalculateOilTotal();
  }

  String? _oilSizeValueForSave() {
    if (_usesShopOilFromStock || _usesWarehouseOilPicker) {
      final liters = _oilLitersForPricing();
      if (liters <= 0) return null;
      final ml = (liters * 1000).round();
      return oilSizeDisplayToStored(formatOilVolumeDisplay(ml));
    }
    final stored = oilSizeDisplayToStored(_oilSizeAmount.text);
    if (stored.isEmpty) return null;
    return stored;
  }

  // ── Moved methods (45) ──

  void _markHydraulicFluidUserEdited(OilChangeHydraulicCardSlot slot) {
    if (identical(slot, _gearHydraulic)) {
      _hydraulicGearUserEdited = true;
    } else if (identical(slot, _powerHydraulic)) {
      _hydraulicPowerUserEdited = true;
    }
    _plateVehicleSyncDebounce?.cancel();
  }

  void _clearOilStockSelection() {
    _selectedOilFamilyKey = null;
    _oilStockProductId = null;
    _oilPickSellPerLiter = null;
    _oilAvailableLiters = 0;
    _selectedViscosity = null;
  }

  List<OilPickLine> _hydraulicStockLinesForFamily(OilChangeHydraulicCardSlot slot) {
    final key = slot.selectedFamilyKey;
    if (key == null) return const [];
    return _hydraulicStockPickLines
        .where((l) => _OilChangeOrderFormScreenState._oilFamilyKey(l) == key)
        .toList()
      ..sort(
        (a, b) => a.viscosity.toLowerCase().compareTo(b.viscosity.toLowerCase()),
      );
  }

  int? _hydraulicStockGradeProductIdFor(OilChangeHydraulicCardSlot slot) {
    final pid = slot.stockProductId;
    if (pid == null || pid <= 0) return null;
    for (final l in _hydraulicStockLinesForFamily(slot)) {
      if (l.linkedProductId == pid) return pid;
    }
    return null;
  }

  void _applyHydraulicStockLineFor(OilChangeHydraulicCardSlot slot, OilPickLine line) {
    _markHydraulicFluidUserEdited(slot);
    slot.selectedFamilyKey = _OilChangeOrderFormScreenState._oilFamilyKey(line);
    slot.stockProductId = line.linkedProductId;
    slot.type.text = line.parentName;
    slot.selectedGrade = line.viscosity.isEmpty ? null : line.viscosity;
    slot.pickSellPerLiter = line.sellPerLiterIqd;
    slot.catalogSellPerLiterFils = null;
    slot.selectedBrand = null;
    _agreedTotalManual = false;
  }

  void _onHydraulicFamilyDropdownChangedFor(
    OilChangeHydraulicCardSlot slot,
    int? familyKey,
  ) {
    _markHydraulicFluidUserEdited(slot);
    _rebuild(() {
      slot.selectedFamilyKey = familyKey;
      slot.stockProductId = null;
      slot.pickSellPerLiter = null;
      slot.selectedGrade = null;
      slot.availableLiters = 0;
      if (familyKey != null) {
        final lines = _hydraulicStockPickLines
            .where((l) => _OilChangeOrderFormScreenState._oilFamilyKey(l) == familyKey)
            .toList();
        if (lines.length == 1) _applyHydraulicStockLineFor(slot, lines.first);
      }
    });
    if ((slot.stockProductId ?? 0) > 0) {
      unawaited(_refreshHydraulicAvailableLitersFor(slot));
      _recalculateOilTotal();
    }
  }

  void _onHydraulicStockGradeDropdownChangedFor(
    OilChangeHydraulicCardSlot slot,
    int? linkedProductId,
  ) {
    _markHydraulicFluidUserEdited(slot);
    if (linkedProductId == null) {
      _rebuild(() {
        slot.stockProductId = null;
        slot.pickSellPerLiter = null;
        slot.selectedGrade = null;
        slot.availableLiters = 0;
      });
      _recalculateOilTotal();
      return;
    }
    OilPickLine? line;
    for (final l in _hydraulicStockLinesForFamily(slot)) {
      if (l.linkedProductId == linkedProductId) {
        line = l;
        break;
      }
    }
    if (line == null) return;
    final picked = line;
    _rebuild(() => _applyHydraulicStockLineFor(slot, picked));
    _syncHydraulicLitersFromStepperFor(slot);
    unawaited(_refreshHydraulicAvailableLitersFor(slot));
    _recalculateOilTotal();
  }

  void _syncGuideCatalogActions(GuideController guide) {
    final action = guide.currentStep?.action;
    if (!guide.isRunning) {
      _closeGuideCatalogSheetsIfNeeded();
      return;
    }
    if (action == 'oil.expand_extras') {
      final anchor = guide.currentStep?.anchorId ?? '';
      final toAdd = <_OilFormOptionalSection>{};
      if (anchor.contains('filter') || anchor.contains('hydraulic')) {
        if (anchor.contains('filter')) {
          toAdd.add(_OilFormOptionalSection.filters);
        }
        if (anchor.contains('hydraulic')) {
          toAdd.add(_OilFormOptionalSection.hydraulicGear);
        }
      } else {
        toAdd.add(_OilFormOptionalSection.filters);
        toAdd.add(_OilFormOptionalSection.hydraulicGear);
      }
      final needsExpand =
          toAdd.any((section) => !_expandedOptional.contains(section));
      if (needsExpand) {
        _rebuild(() => _expandedOptional.addAll(toAdd));
        _ensureDeferredCatalogsForExpanded();
      }
    }
    if (action == 'oil.open_oil_catalog' && !_oilCatalogGuideOpen) {
      unawaited(_openOilCatalogManage());
    } else if (action == 'oil.open_filter_catalog' && !_filterCatalogGuideOpen) {
      _rebuild(() {
        _expandedOptional.add(_OilFormOptionalSection.filters);
      });
      _ensureDeferredCatalogsForExpanded();
      unawaited(_openFilterCatalogManage(OilChangeFilterKind.engine));
    } else if (action == 'oil.open_hydraulic_catalog' &&
        !_hydraulicCatalogGuideOpen) {
      _rebuild(() {
        _expandedOptional.add(_OilFormOptionalSection.hydraulicGear);
      });
      _ensureDeferredCatalogsForExpanded();
      unawaited(_openHydraulicCatalogManageFor(_gearHydraulic));
    }
  }

  void _closeGuideCatalogSheetsIfNeeded() {
    if (!mounted) return;
    if (_oilCatalogGuideOpen ||
        _filterCatalogGuideOpen ||
        _hydraulicCatalogGuideOpen) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _openOilCatalogManage() async {
    if (_oilCatalogGuideOpen) return;
    _oilCatalogGuideOpen = true;
    try {
      await showOilChangeOilCatalogSheet(
        context,
        manageOnly: true,
      );
    } finally {
      _oilCatalogGuideOpen = false;
    }
    if (!mounted) return;
    await _loadOilProductCatalog();
    _rebuild(() {
      if (_oilFluidUserEdited) {
        _syncOilCatalogPricingFromSelection();
      } else {
        _reconcileOilCatalogSelection();
      }
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  void _onFilterEntryChanged(OilChangeFilterKind kind, int? entryId) {
    final slot = _filterSlotFor(kind);
    if (entryId == null) {
      _rebuild(() {
        slot.clear();
        if (OilChangeAgreedTotal.shouldClearManualOnComponentChange()) {
          _agreedTotalManual = false;
        }
      });
      _recalculateOilTotal();
      return;
    }
    final entry = OilChangeFilterCatalogRepository.entryById(
      OilChangeFilterCatalogRepository.entriesForKind(
        _filterProductCatalog,
        kind,
      ),
      entryId,
    );
    if (entry == null) return;
    _rebuild(() {
      if (!_filterQtyEditable) slot.qty = 1;
      slot.applyEntry(entry);
      _expandedOptional.add(_OilFormOptionalSection.filters);
      if (OilChangeAgreedTotal.shouldClearManualOnComponentChange()) {
        _agreedTotalManual = false;
      }
    });
    _recalculateOilTotal();
  }

  Future<void> _openFilterCatalogManage(OilChangeFilterKind kind) async {
    if (_filterCatalogGuideOpen) return;
    _filterCatalogGuideOpen = true;
    try {
      await showOilChangeFilterCatalogSheet(
        context,
        manageOnly: true,
        initialKind: kind,
      );
    } finally {
      _filterCatalogGuideOpen = false;
    }
    if (!mounted) return;
    await _loadFilterProductCatalog();
    _rebuild(() {
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  Widget _buildFilterKindRow({
    required BuildContext context,
    required ColorScheme cs,
    required bool busy,
    required OilChangeFilterKind kind,
  }) {
    final slot = _filterSlotFor(kind);
    final entries = OilChangeFilterCatalogRepository.entriesForKind(
      _filterProductCatalog,
      kind,
    );
    final priceLabel = !slot.customerProvided && slot.priceFils > 0
        ? _formatFilsLabel(slot.priceFils)
        : null;

    final customerToggle = Align(
      alignment: AlignmentDirectional.centerStart,
      child: FilterChip(
        label: const Text('من العميل'),
        avatar: const Icon(Icons.person_outline, size: 16),
        selected: slot.customerProvided,
        onSelected: busy
            ? null
            : (v) {
                _rebuild(() {
                  slot.customerProvided = v;
                  slot.laborCardFils = null;
                  if (v) {
                    // فلتر العميل: لا صنف من الكتالوج ولا ثمن.
                    slot.catalogEntryId = null;
                    slot.priceFils = 0;
                    slot.productId = null;
                    slot.qty = 1;
                    slot.unitPriceFils = 0;
                  } else {
                    slot.name = null;
                  }
                  _agreedTotalManual = false;
                });
                _recalculateOilTotal();
              },
      ),
    );

    if (slot.customerProvided) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            kind.label,
            style: const TextStyle(fontWeight: FontWeight.w800),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 4),
          customerToggle,
          const SizedBox(height: 6),
          TextFormField(
            key: ValueKey('customer-filter-name-${kind.code}'),
            initialValue: slot.name ?? '',
            enabled: !busy,
            decoration: InputDecoration(
              labelText: 'اسم ${kind.label} (اختياري)',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => slot.name = v.trim().isEmpty ? null : v.trim(),
            textAlign: TextAlign.start,
          ),
          _buildLaborRow(
            cs,
            label: 'أجرة تركيب ${kind.label}',
            fils: _filterLaborFilsFor(slot),
            edited: slot.laborCardFils != null,
            busy: busy,
            onChanged: (v) {
              _rebuild(() {
                slot.laborCardFils = v;
                _agreedTotalManual = false;
              });
              _recalculateOilTotal();
            },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                value: slot.catalogEntryId != null &&
                        entries.any((e) => e.id == slot.catalogEntryId)
                    ? slot.catalogEntryId
                    : null,
                decoration: InputDecoration(
                  labelText: kind.label,
                  border: const OutlineInputBorder(),
                  hintText: 'اختر ${kind.label.replaceFirst('فلتر ', '')}',
                  isDense: true,
                ),
                isExpanded: true,
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('بدون'),
                  ),
                  ...entries.map(
                    (e) => DropdownMenuItem(
                      value: e.id,
                      child: Text(
                        () {
                          final label = e.name.trim().isEmpty
                              ? 'بدون اسم'
                              : e.name.trim();
                          final priced = e.priceFils > 0
                              ? '$label — ${_formatFilsLabel(e.priceFils)}'
                              : label;
                          final avail = e.availableQty;
                          if (avail == null) return priced;
                          final n = avail % 1 == 0
                              ? avail.toInt().toString()
                              : avail.toStringAsFixed(1);
                          return '$priced (متوفر $n)';
                        }(),
                        textAlign: TextAlign.start,
                      ),
                    ),
                  ),
                ],
                onChanged: busy
                    ? null
                    : (id) => _onFilterEntryChanged(kind, id),
              ),
            ),
            if (!_filtersStockEnabled) ...[
              const SizedBox(width: 4),
              GuideAnchor(
                id: OilGuideAnchors.formFilterCatalogBtn,
                child: IconButton.filledTonal(
                  onPressed: busy
                      ? null
                      : () => unawaited(_openFilterCatalogManage(kind)),
                  tooltip: 'إدارة أسعار ${kind.label}',
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
            ],
          ],
        ),
        if (_filtersStockEnabled && entries.isEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'لا أصناف في المخزون صنفها «${kind.label}» أو «فلتر».',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            textAlign: TextAlign.start,
          ),
        ],
        if (_filterNeedsStockPick(slot)) ...[
          const SizedBox(height: 4),
          Text(
            'محفوظ بالاسم: «${slot.name ?? ''}». اختره من المخزون قبل البيع.',
            style: TextStyle(fontSize: 12, color: cs.error),
            textAlign: TextAlign.start,
          ),
        ],
        if (_filterQtyEditable && slot.catalogEntryId != null)
          _buildFilterQtyRow(cs, slot: slot, busy: busy),
        const SizedBox(height: 4),
        customerToggle,
        if (priceLabel != null) ...[
          const SizedBox(height: 4),
          Text(
            'السعر: $priceLabel',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
            textAlign: TextAlign.start,
          ),
        ],
      ],
    );
  }

  /// فلتر محفوظ بالاسم بلا صنف مخزون والمصدر صار «مرتبط بالمخزون».
  bool _filterNeedsStockPick(OilChangeFilterSlot slot) =>
      _filtersStockEnabled &&
      !slot.customerProvided &&
      slot.hasSelection &&
      (slot.productId ?? 0) <= 0;

  Widget _buildFilterQtyRow(
    ColorScheme cs, {
    required OilChangeFilterSlot slot,
    required bool busy,
  }) {
    void change(int q) {
      _rebuild(() {
        slot.setQty(q);
        _agreedTotalManual = false;
      });
      _recalculateOilTotal();
    }

    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 4),
      child: Row(
        children: [
          const Text('العدد'),
          const Spacer(),
          IconButton(
            tooltip: 'إنقاص',
            onPressed: busy || slot.qty <= 1 ? null : () => change(slot.qty - 1),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(
            '${slot.qty}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          IconButton(
            tooltip: 'زيادة',
            onPressed: busy ? null : () => change(slot.qty + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }

  List<OilChangeHydraulicCatalogEntry> _hydraulicGradeDropdownEntriesFor(
    OilChangeHydraulicCardSlot slot,
  ) {
    final brand = slot.selectedBrand;
    if (brand == null || brand.isEmpty) return const [];
    final cached = _hydraulicGradeEntriesCache[slot];
    if (cached != null &&
        identical(cached.source, _hydraulicProductCatalog) &&
        cached.brand == brand) {
      return cached.entries;
    }
    final entries = OilChangeHydraulicCatalogRepository.entriesForBrand(
      _hydraulicProductCatalog,
      brand,
    );
    _hydraulicGradeEntriesCache[slot] = _HydraulicGradeCache(
      source: _hydraulicProductCatalog,
      brand: brand,
      entries: entries,
    );
    return entries;
  }

  String? _hydraulicBrandDropdownValueFor(OilChangeHydraulicCardSlot slot) {
    final brand = slot.selectedBrand ?? slot.type.text.trim();
    if (brand.isEmpty) return null;
    for (final b in _hydraulicBrandDropdownItems) {
      if (b.toLowerCase() == brand.toLowerCase()) return b;
    }
    return null;
  }

  String? _hydraulicGradeDropdownValueFor(OilChangeHydraulicCardSlot slot) {
    final grade = slot.selectedGrade;
    if (grade == null || grade.isEmpty) return null;
    for (final e in _hydraulicGradeDropdownEntriesFor(slot)) {
      if (e.grade.toLowerCase() == grade.toLowerCase()) return e.grade;
    }
    return null;
  }

  void _applyHydraulicCatalogEntryFor(
    OilChangeHydraulicCardSlot slot,
    OilChangeHydraulicCatalogEntry entry,
  ) {
    _markHydraulicFluidUserEdited(slot);
    slot.selectedBrand = entry.brandName;
    slot.type.text = entry.brandName;
    slot.selectedGrade = entry.grade;
    slot.catalogSellPerLiterFils = entry.sellPerLiterFils;
    slot.stockProductId = null;
    slot.pickSellPerLiter = null;
    slot.litersStock.clear();
    slot.selectedFamilyKey = null;
    _agreedTotalManual = false;
  }

  void _onHydraulicBrandDropdownChangedFor(
    OilChangeHydraulicCardSlot slot,
    String? brand,
  ) {
    _markHydraulicFluidUserEdited(slot);
    _rebuild(() {
      slot.selectedBrand = brand;
      slot.type.text = brand ?? '';
      if (brand == null) {
        slot.selectedGrade = null;
        slot.catalogSellPerLiterFils = null;
        return;
      }
      final entries = OilChangeHydraulicCatalogRepository.entriesForBrand(
        _hydraulicProductCatalog,
        brand,
      );
      final currentGrade = slot.selectedGrade;
      OilChangeHydraulicCatalogEntry? keep;
      if (currentGrade != null && currentGrade.isNotEmpty) {
        keep = OilChangeHydraulicCatalogRepository.entryForBrandGrade(
          _hydraulicProductCatalog,
          brandName: brand,
          grade: currentGrade,
        );
      }
      if (keep != null) {
        _applyHydraulicCatalogEntryFor(slot, keep);
      } else if (entries.length == 1) {
        _applyHydraulicCatalogEntryFor(slot, entries.first);
      } else {
        slot.selectedGrade = null;
        slot.catalogSellPerLiterFils = null;
        slot.stockProductId = null;
        slot.pickSellPerLiter = null;
      }
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  void _onHydraulicGradeDropdownChangedFor(
    OilChangeHydraulicCardSlot slot,
    String? grade,
  ) {
    _markHydraulicFluidUserEdited(slot);
    if (grade == null || slot.selectedBrand == null) return;
    final entry = OilChangeHydraulicCatalogRepository.entryForBrandGrade(
      _hydraulicProductCatalog,
      brandName: slot.selectedBrand!,
      grade: grade,
    );
    if (entry == null) return;
    _rebuild(() => _applyHydraulicCatalogEntryFor(slot, entry));
    _recalculateOilTotal();
  }

  Future<void> _openHydraulicCatalogManageFor(OilChangeHydraulicCardSlot slot) async {
    if (_hydraulicCatalogGuideOpen) return;
    final seedBrand = _hydraulicBrandDropdownValueFor(slot) ??
        (slot.type.text.trim().isEmpty ? null : slot.type.text.trim());
    _hydraulicCatalogGuideOpen = true;
    try {
      await showOilChangeHydraulicCatalogSheet(
        context,
        manageOnly: true,
        initialBrandName: seedBrand,
      );
    } finally {
      _hydraulicCatalogGuideOpen = false;
    }
    if (!mounted) return;
    await _loadHydraulicProductCatalog();
    _rebuild(() {
      _reconcileHydraulicCatalogSelectionFor(slot);
      _agreedTotalManual = false;
    });
    _recalculateOilTotal();
  }

  bool _showCatalogHydraulicFieldsFor(OilChangeHydraulicCardSlot slot) =>
      !slot.customerProvided && !_usesWarehouseHydraulicPickerFor(slot);

  bool _showHydraulicVolumeStepperFor(OilChangeHydraulicCardSlot slot) {
    if (slot.customerProvided) return true;
    if (_usesCatalogHydraulicPricingFor(slot)) return true;
    if (_usesWarehouseHydraulicPickerFor(slot)) {
      return (slot.stockProductId ?? 0) > 0;
    }
    return false;
  }

  Widget _responsivePair(
    BuildContext context, {
    required Widget first,
    required Widget second,
    double gap = 12,
    bool sideBySideOnPhone = false,
  }) {
    // sideBySideOnPhone: فوق 400dp يبقى صفاً حتى على الهاتف؛ تحت 400 يُطوى دائماً.
    if (oilChangePreferStackedFieldsOf(context) ||
        (context.screenLayout.isPhoneVariant && !sideBySideOnPhone)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          first,
          SizedBox(height: gap),
          second,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        SizedBox(width: gap),
        Expanded(child: second),
      ],
    );
  }

  Widget _compactSideBySide({
    required BuildContext context,
    required Widget start,
    required Widget end,
    int startFlex = 1,
    int endFlex = 1,
    double gap = 8,
  }) {
    return oilChangeFieldPair(
      context: context,
      start: start,
      end: end,
      startFlex: startFlex,
      endFlex: endFlex,
      gap: gap,
    );
  }

  Future<void> _openOilProductBarcodeCapture() async {
    final raw = await BarcodeInputLauncher.captureBarcode(
      context,
      title: 'باركود صنف',
      preferCompactHandsetOverlay: true,
    );
    if (!mounted) return;
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return;
    await _handleOilProductBarcode(t);
  }

  Future<void> _openOilProductPicker() async {
    if (_oilBarcodeBusy || !mounted) return;
    _rebuild(() => _isProductPickerOpen = true);
    try {
      final picked = await ProductPickerDialog.show(context);
      if (!mounted || picked == null) return;
      final msg = OilChangeProductScan.addFromProductMap(
        lines: _oilProductLines,
        product: picked,
      );
      _rebuild(() {
        _agreedTotalManual = false;
        _expandedOptional.add(_OilFormOptionalSection.products);
      });
      _recalculateOilTotal();
      if (msg != null && msg.isNotEmpty) {
        _showOilProductSnack(msg, success: true);
      }
    } finally {
      if (mounted) _rebuild(() => _isProductPickerOpen = false);
    }
  }

  void _toggleOptionalSection(_OilFormOptionalSection section) {
    if (!_isOptionalSectionEnabled(section) &&
        !_optionalSectionHasData(section)) {
      return;
    }
    final expanding = !_expandedOptional.contains(section);
    _rebuild(() {
      if (expanding) {
        _expandedOptional.add(section);
      } else {
        _expandedOptional.remove(section);
      }
    });
    if (expanding) {
      _ensureDeferredCatalogsForExpanded();
    }
  }

  String? _oilCollapsedHint() {
    if (!_oilSectionHasData()) return null;
    if (_oilCustomerProvided) return 'زيت العميل';
    final bits = [
      _oilType.text.trim(),
      _selectedViscosity ?? '',
    ].where((b) => b.isNotEmpty);
    return bits.isEmpty ? 'مُحدَّد' : bits.join(' · ');
  }

  String? _hydraulicCollapsedHint(OilChangeHydraulicCardSlot slot) {
    if (!_hydraulicSlotHasData(slot)) return null;
    final brand = slot.selectedBrand ?? slot.type.text.trim();
    final grade = slot.selectedGrade ?? '';
    if (brand.isNotEmpty && grade.isNotEmpty) return '$brand · $grade';
    if (brand.isNotEmpty) return brand;
    if (grade.isNotEmpty) return grade;
    final liters = slot.litersForPricing();
    if (liters > 1e-9) return '${liters.toStringAsFixed(1)} لتر';
    if (slot.customerProvided) return 'من العميل';
    return 'مُحدَّد';
  }

  String _optionalSectionTitle(_OilFormOptionalSection section) {
    return switch (section) {
      _OilFormOptionalSection.oil => 'الزيت',
      _OilFormOptionalSection.products => 'المنتجات',
      _OilFormOptionalSection.filters => 'الفلاتر',
      _OilFormOptionalSection.hydraulicGear => 'هيدروليك الكير',
      _OilFormOptionalSection.hydraulicPower => 'هيدروليك الباور',
      _OilFormOptionalSection.services => 'الخدمات الإضافية',
    };
  }

  IconData _optionalSectionIcon(_OilFormOptionalSection section) {
    return switch (section) {
      _OilFormOptionalSection.oil => Icons.opacity_rounded,
      _OilFormOptionalSection.products => Icons.inventory_2_outlined,
      _OilFormOptionalSection.filters => Icons.filter_alt_outlined,
      _OilFormOptionalSection.hydraulicGear => Icons.water_drop_outlined,
      _OilFormOptionalSection.hydraulicPower => Icons.water_drop_outlined,
      _OilFormOptionalSection.services => Icons.checklist_rounded,
    };
  }

  String? _optionalSectionCollapsedHint(_OilFormOptionalSection section) {
    return switch (section) {
      _OilFormOptionalSection.oil => _oilCollapsedHint(),
      _OilFormOptionalSection.products => _oilProductLines.isEmpty
          ? null
          : '${_oilProductLines.length} صنف',
      _OilFormOptionalSection.filters => () {
          final n =
              _filterKinds.where((k) => _filterSlotFor(k).hasSelection).length;
          if (n == 0) return null;
          return '$n فلتر محدد';
        }(),
      _OilFormOptionalSection.hydraulicGear =>
          _hydraulicCollapsedHint(_gearHydraulic),
      _OilFormOptionalSection.hydraulicPower =>
          _hydraulicCollapsedHint(_powerHydraulic),
      _OilFormOptionalSection.services => _selectedOilServiceIds.isEmpty
          ? null
          : '${_selectedOilServiceIds.length} خدمة',
    };
  }

  Widget _buildOptionalSectionChip(
    ColorScheme cs,
    bool busy,
    _OilFormOptionalSection section,
  ) {
    return Tooltip(
      message: _optionalSectionCollapsedHint(section) ??
          _optionalSectionTitle(section),
      child: FilterChip(
        label: Text(
          _optionalSectionTitle(section),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11.5),
        ),
        avatar: Icon(
          _optionalSectionIcon(section),
          size: 16,
          color: _expandedOptional.contains(section)
              ? cs.onPrimaryContainer
              : cs.onSurfaceVariant,
        ),
        selected: _expandedOptional.contains(section),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 6),
        onSelected:
            busy ? null : (_) => _toggleOptionalSection(section),
      ),
    );
  }

  Widget _buildOilOptionalQuickBar(ColorScheme cs, bool busy) {
    final sections = _OilFormOptionalSection.values
        .where(
          (s) =>
              _isOptionalSectionEnabled(s) || _optionalSectionHasData(s),
        )
        .toList(growable: false);
    if (sections.isEmpty) return const SizedBox.shrink();

    final firstRow = sections.length <= 3
        ? sections
        : sections.sublist(0, 3);
    final secondRow =
        sections.length > 3 ? sections.sublist(3) : const <_OilFormOptionalSection>[];

    return GuideAnchor(
      id: OilGuideAnchors.formExtras,
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsetsDirectional.fromSTEB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: OilChangeRoyalCard.gold.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'إضافات عند الحاجة',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 2),
          Text(
            'اضغط الزر لفتح القسم — اضغط مرة أخرى لإخفائه',
            style: TextStyle(
              fontSize: 10.5,
              color: cs.onSurfaceVariant,
              height: 1.25,
            ),
            textAlign: TextAlign.start,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (var i = 0; i < firstRow.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: _buildOptionalSectionChip(cs, busy, firstRow[i]),
                ),
              ],
            ],
          ),
          if (secondRow.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < secondRow.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _buildOptionalSectionChip(cs, busy, secondRow[i]),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    ),
    );
  }

  /// [childrenBuilder] دالة لا قائمة جاهزة: القسم المطوي كان يُبنى بالكامل ثم
  /// يُرمى في كل إعادة بناء، وهو أثقل جزء في الشاشة (بطاقات الفلاتر والهيدروليك).
  Widget _buildOilOptionalSection(
    BuildContext context, {
    required _OilFormOptionalSection section,
    required List<Widget> Function() childrenBuilder,
  }) {
    final expanded = _expandedOptional.contains(section);
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: AlignmentDirectional.topCenter,
      child: expanded
          ? OilChangeRoyalCard.section(
              context: context,
              title: _optionalSectionTitle(section),
              icon: _optionalSectionIcon(section),
              children: childrenBuilder(),
            )
          : const SizedBox(width: double.infinity),
    );
  }

  Widget _buildOilCheckoutSectionCard(BuildContext context, bool busy) {
    return GuideAnchor(
      id: OilGuideAnchors.formPayment,
      child: OilChangeRoyalCard.section(
        context: context,
        title: 'السعر والدفع',
        icon: Icons.payments_outlined,
        children: _oilCheckoutFields(context, busy, compact: true),
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return OilChangeRoyalCard.section(
      context: context,
      title: title,
      icon: icon,
      children: children,
    );
  }

  /// سطر أجرة يد ظاهر في القسم، يعدّله الموظف لهذه البطاقة فقط.
  Widget _buildLaborRow(
    ColorScheme cs, {
    required String label,
    required int fils,
    required bool edited,
    required bool busy,
    required ValueChanged<int?> onChanged,
    String? zeroHint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: busy
              ? null
              : () async {
                  final v = await _askLaborFils(label: label, current: fils);
                  if (v == null) return;
                  onChanged(v < 0 ? null : v);
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.handyman_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                        textAlign: TextAlign.start,
                      ),
                      if (fils <= 0 && zeroHint != null)
                        Text(
                          zeroHint,
                          style: TextStyle(fontSize: 11.5, color: cs.error),
                          textAlign: TextAlign.start,
                        )
                      else if (edited)
                        Text(
                          'معدّلة لهذه البطاقة',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.start,
                        ),
                    ],
                  ),
                ),
                Text(
                  fils <= 0 ? '0' : _formatFilsLabel(fils),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 16, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// يُرجع الأجرة بالفلس، أو -1 للعودة إلى أجرة الإعدادات، أو null للإلغاء.
  Future<int?> _askLaborFils({
    required String label,
    required int current,
  }) async {
    final ctrl = TextEditingController(
      text: current > 0 ? _formatIqdWhole(current) : '',
    );
    try {
      return await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(label),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [IraqiCurrencyFormat.moneyInputFormatter()],
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'المبلغ (د.ع)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: const Text('من الإعدادات'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                final d = double.tryParse(
                      ctrl.text.trim().replaceAll(',', ''),
                    ) ??
                    0;
                Navigator.pop(ctx, d <= 0 ? 0 : IqdMoney.toFils(d));
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
    } finally {
      ctrl.dispose();
    }
  }

  Widget _buildOilSourceSegment(ColorScheme cs, bool busy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          'مصدر الزيت',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            fontSize: 13,
          ),
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('زيت المحل'),
              icon: Icon(Icons.inventory_2_outlined, size: 18),
            ),
            ButtonSegment(
              value: true,
              label: Text('زيت العميل'),
              icon: Icon(Icons.person_outline, size: 18),
            ),
          ],
          selected: {_oilCustomerProvided},
          onSelectionChanged: busy
              ? null
              : (s) {
                  _markOilFluidUserEdited();
                  _rebuild(() {
                    _oilCustomerProvided = s.first;
                    // الأجرة تتبع المصدر الجديد من الإعدادات.
                    _oilLaborCardFils = null;
                    if (_oilCustomerProvided) {
                      _clearOilStockSelection();
                      _selectedOilFamilyKey = null;
                      _catalogSellPerLiterFils = null;
                      _oilLitersStock.clear();
                    } else {
                      _catalogSellPerLiterFils = null;
                      _selectedOilBrand = null;
                    }
                    _agreedTotalManual = false;
                  });
                  _recalculateOilTotal();
                },
        ),
        if (_oilCustomerProvided)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'لن يُخصم مخزون ولا يُحسب ثمن زيت — العميل أحضره. '
              'اسم الزيت وحجمه اختياريان.',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.start,
            ),
          ),
        if (_oilCustomerProvided) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _oilType,
            enabled: !busy,
            onTap: oilFieldSelectAllOnTap(_oilType),
            decoration: const InputDecoration(
              labelText: 'اسم زيت العميل (اختياري)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _markOilFluidUserEdited(),
            textAlign: TextAlign.start,
          ),
        ],
        _buildLaborRow(
          cs,
          label: 'أجرة التبديل (عمل اليد)',
          fils: _oilLaborFils(),
          edited: _oilLaborCardFils != null,
          busy: busy,
          zeroHint: 'لم تُحدَّد أجرة التبديل — من «الخدمات وأسعارها»',
          onChanged: (v) {
            _rebuild(() {
              _oilLaborCardFils = v;
              _agreedTotalManual = false;
            });
            _recalculateOilTotal();
          },
        ),
      ],
    );
  }

  Widget _buildWarehouseOilPickRow(
    BuildContext context,
    ColorScheme cs,
    bool busy,
  ) {
    if (!_usesWarehouseOilPicker) return const SizedBox.shrink();
    final families = _oilFamilyDropdownOptions;
    final visLines = _oilStockLinesForSelectedFamily;
    final showViscosityDropdown = visLines.any((l) => l.viscosity.isNotEmpty);
    final familyKeyValid = _selectedOilFamilyKey != null &&
        families.any((f) => f.key == _selectedOilFamilyKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        if (_oilStockMetaLoading || _oilStockPickLinesLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (families.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'لا توجد عائلات زيت في المخزون. أضف «زيت — عائلة» من المخزون ثم حدّث.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: busy ? null : () => unawaited(_loadOilStockMeta()),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('تحديث قائمة المخزون'),
                ),
              ),
            ],
          )
        else
          oilChangeFieldPair(
            context: context,
            startFlex: 2,
            endFlex: 1,
            gap: 6,
            start: DropdownButtonFormField<int>(
              value: familyKeyValid ? _selectedOilFamilyKey : null,
              decoration: const InputDecoration(
                labelText: 'زيت من المخزون',
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'اختر العائلة',
              ),
              isExpanded: true,
              items: families
                  .map(
                    (f) => DropdownMenuItem(
                      value: f.key,
                      child: Text(
                        f.label,
                        textAlign: TextAlign.start,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: busy ? null : _onOilFamilyDropdownChanged,
            ),
            end: showViscosityDropdown
                ? DropdownButtonFormField<int>(
                    value: _oilStockViscosityProductId,
                    decoration: InputDecoration(
                      labelText: 'اللزوجة',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: familyKeyValid
                          ? 'اختر اللزوجة'
                          : 'اختر العائلة أولاً',
                    ),
                    isExpanded: true,
                    items: visLines
                        .where((l) => l.viscosity.isNotEmpty)
                        .map(
                          (l) => DropdownMenuItem(
                            value: l.linkedProductId,
                            child: Text(
                              l.viscosity,
                              textAlign: TextAlign.start,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy || !familyKeyValid
                        ? null
                        : _onOilStockViscosityChanged,
                  )
                : InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'اللزوجة',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      _selectedViscosity ??
                          (familyKeyValid && visLines.isNotEmpty
                              ? '—'
                              : '—'),
                      textAlign: TextAlign.start,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        if ((_oilStockProductId ?? 0) > 0) ...[
          const SizedBox(height: 6),
          Text(
            'متوفر في المخزون: ${_oilAvailableLiters.toStringAsFixed(1)} لتر',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
            textAlign: TextAlign.start,
          ),
        ],
        if (_warehouses.length > 1) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: _oilWarehouseId,
            decoration: const InputDecoration(
              labelText: 'المستودع',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            isExpanded: true,
            items: _warehouses
                .map(
                  (w) => DropdownMenuItem<int>(
                    value: (w['id'] as num).toInt(),
                    child: Text(w['name']?.toString() ?? ''),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (v) {
                    _rebuild(() => _oilWarehouseId = v);
                    unawaited(_refreshAvailableLiters());
                  },
          ),
        ],
      ],
    );
  }

  Widget _buildHydraulicSourceSegmentFor(
    ColorScheme cs,
    bool busy,
    OilChangeHydraulicCardSlot slot, {
    required String sourceTitle,
    required String shopLabel,
    required String customerLabel,
    required String customerHint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          sourceTitle,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: cs.onSurface,
            fontSize: 13,
          ),
          textAlign: TextAlign.start,
        ),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: [
            ButtonSegment(
              value: false,
              label: Text(shopLabel),
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
            ),
            ButtonSegment(
              value: true,
              label: Text(customerLabel),
              icon: const Icon(Icons.person_outline, size: 18),
            ),
          ],
          selected: {slot.customerProvided},
          onSelectionChanged: busy
              ? null
              : (s) {
                  _rebuild(() {
                    slot.customerProvided = s.first;
                    slot.laborCardFils = null;
                    if (slot.customerProvided) {
                      slot.clearStockSelection();
                      slot.litersStock.clear();
                    } else {
                      slot.clearCatalogSelection();
                    }
                    _agreedTotalManual = false;
                  });
                  _recalculateOilTotal();
                },
        ),
        if (slot.customerProvided)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              customerHint,
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.start,
            ),
          ),
        if (slot.customerProvided) ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: slot.type,
            enabled: !busy,
            decoration: InputDecoration(
              labelText:
                  'اسم ${sourceTitle.replaceFirst('مصدر ', '')} (اختياري)',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _markHydraulicFluidUserEdited(slot),
            textAlign: TextAlign.start,
          ),
        ],
        if (slot.customerProvided)
          _buildLaborRow(
            cs,
            label: 'أجرة اليد (${sourceTitle.replaceFirst('مصدر ', '')})',
            fils: _hydraulicLaborFilsFor(slot),
            edited: slot.laborCardFils != null,
            busy: busy,
            onChanged: (v) {
              _rebuild(() {
                slot.laborCardFils = v;
                _agreedTotalManual = false;
              });
              _recalculateOilTotal();
            },
          ),
      ],
    );
  }

  Widget _buildWarehouseHydraulicPickRowFor(
    BuildContext context,
    ColorScheme cs,
    bool busy,
    OilChangeHydraulicCardSlot slot, {
    required String stockLabel,
    required String warehouseLabel,
  }) {
    if (!_usesWarehouseHydraulicPickerFor(slot)) return const SizedBox.shrink();
    final families = _hydraulicFamilyDropdownOptions;
    final gradeLines = _hydraulicStockLinesForFamily(slot);
    final showGradeDropdown = gradeLines.any((l) => l.viscosity.isNotEmpty);
    final familyKeyValid = slot.selectedFamilyKey != null &&
        families.any((f) => f.key == slot.selectedFamilyKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        if (_hydraulicStockPickLinesLoading)
          const LinearProgressIndicator(minHeight: 2)
        else if (families.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'لا توجد عائلات هيدروليك في المخزون. أضف «هيدروليك — عائلة» من المخزون ثم حدّث.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                textAlign: TextAlign.start,
              ),
              const SizedBox(height: 6),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed:
                      busy ? null : () => unawaited(_loadHydraulicStockMeta()),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('تحديث قائمة المخزون'),
                ),
              ),
            ],
          )
        else
          oilChangeFieldPair(
            context: context,
            startFlex: 2,
            endFlex: 1,
            gap: 6,
            start: DropdownButtonFormField<int>(
              value: familyKeyValid ? slot.selectedFamilyKey : null,
              decoration: InputDecoration(
                labelText: stockLabel,
                border: const OutlineInputBorder(),
                isDense: true,
                hintText: 'اختر العائلة',
              ),
              isExpanded: true,
              items: families
                  .map(
                    (f) => DropdownMenuItem(
                      value: f.key,
                      child: Text(
                        f.label,
                        textAlign: TextAlign.start,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: busy
                  ? null
                  : (v) => _onHydraulicFamilyDropdownChangedFor(slot, v),
            ),
            end: showGradeDropdown
                ? DropdownButtonFormField<int>(
                    value: _hydraulicStockGradeProductIdFor(slot),
                    decoration: InputDecoration(
                      labelText: 'الدرجة',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      hintText: familyKeyValid
                          ? 'اختر الدرجة'
                          : 'اختر العائلة أولاً',
                    ),
                    isExpanded: true,
                    items: gradeLines
                        .where((l) => l.viscosity.isNotEmpty)
                        .map(
                          (l) => DropdownMenuItem(
                            value: l.linkedProductId,
                            child: Text(
                              l.viscosity,
                              textAlign: TextAlign.start,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy || !familyKeyValid
                        ? null
                        : (v) =>
                            _onHydraulicStockGradeDropdownChangedFor(slot, v),
                  )
                : InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'الدرجة',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    child: Text(
                      slot.selectedGrade ??
                          (familyKeyValid && gradeLines.isNotEmpty
                              ? '—'
                              : '—'),
                      textAlign: TextAlign.start,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
          ),
        if ((slot.stockProductId ?? 0) > 0) ...[
          const SizedBox(height: 6),
          Text(
            'متوفر في المخزون: ${slot.availableLiters.toStringAsFixed(1)} لتر',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.primary,
            ),
            textAlign: TextAlign.start,
          ),
        ],
        if (_warehouses.length > 1) ...[
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: slot.warehouseId,
            decoration: InputDecoration(
              labelText: warehouseLabel,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            isExpanded: true,
            items: _warehouses
                .map(
                  (w) => DropdownMenuItem<int>(
                    value: (w['id'] as num).toInt(),
                    child: Text(w['name']?.toString() ?? ''),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (v) {
                    _markHydraulicFluidUserEdited(slot);
                    _rebuild(() => slot.warehouseId = v);
                    unawaited(_refreshHydraulicAvailableLitersFor(slot));
                  },
          ),
        ],
      ],
    );
  }

  Widget _buildHydraulicFluidCard(
    BuildContext context, {
    required String title,
    required OilChangeHydraulicCardSlot slot,
    required bool busy,
    required ColorScheme cs,
    required String catalogNameLabel,
    required String volumeLabel,
    required String sourceTitle,
    required String shopLabel,
    required String customerLabel,
    required String customerHint,
    required String stockLabel,
    required String warehouseLabel,
    bool wrapInSectionCard = true,
  }) {
    final fields = <Widget>[
      if (!wrapInSectionCard)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
              color: cs.onSurface,
            ),
            textAlign: TextAlign.start,
          ),
        ),
        if (_showCatalogHydraulicFieldsFor(slot))
          oilChangeFieldPairWithAction(
            context: context,
            start: DropdownButtonFormField<String>(
              value: _hydraulicBrandDropdownValueFor(slot),
              decoration: InputDecoration(
                labelText: catalogNameLabel,
                border: const OutlineInputBorder(),
                isDense: true,
                hintText: _hydraulicProductCatalogLoading
                    ? 'جاري التحميل…'
                    : (_hydraulicBrandDropdownItems.isEmpty
                        ? 'أضف من +'
                        : 'اختر الاسم'),
              ),
              isExpanded: true,
              items: _hydraulicBrandDropdownItems
                  .map(
                    (b) => DropdownMenuItem(
                      value: b,
                      child: Text(b, textAlign: TextAlign.start),
                    ),
                  )
                  .toList(),
              onChanged: busy ||
                      (_hydraulicProductCatalogLoading &&
                          _hydraulicBrandDropdownItems.isEmpty)
                  ? null
                  : (b) => _onHydraulicBrandDropdownChangedFor(slot, b),
            ),
            end: DropdownButtonFormField<String>(
              value: _hydraulicGradeDropdownValueFor(slot),
              decoration: InputDecoration(
                labelText: 'الدرجة',
                border: const OutlineInputBorder(),
                isDense: true,
                hintText: _hydraulicBrandDropdownValueFor(slot) == null
                    ? 'اختر الاسم أولاً'
                    : (_hydraulicGradeDropdownEntriesFor(slot).isEmpty
                        ? 'لا درجات'
                        : 'اختر الدرجة'),
              ),
              isExpanded: true,
              items: _hydraulicGradeDropdownEntriesFor(slot)
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.grade,
                      child: Text(e.grade, textAlign: TextAlign.start),
                    ),
                  )
                  .toList(),
              onChanged: busy ||
                      _hydraulicBrandDropdownValueFor(slot) == null ||
                      _hydraulicGradeDropdownEntriesFor(slot).isEmpty
                  ? null
                  : (g) => _onHydraulicGradeDropdownChangedFor(slot, g),
            ),
            action: GuideAnchor(
              id: OilGuideAnchors.formHydraulicCatalogBtn,
              child: IconButton.filledTonal(
                onPressed: busy
                    ? null
                    : () => unawaited(_openHydraulicCatalogManageFor(slot)),
                tooltip: 'إضافة هيدروليك / درجة للكتالوج',
                icon: const Icon(Icons.add_rounded),
              ),
            ),
          ),
        _buildHydraulicSourceSegmentFor(
          cs,
          busy,
          slot,
          sourceTitle: sourceTitle,
          shopLabel: shopLabel,
          customerLabel: customerLabel,
          customerHint: customerHint,
        ),
        _buildWarehouseHydraulicPickRowFor(
          context,
          cs,
          busy,
          slot,
          stockLabel: stockLabel,
          warehouseLabel: warehouseLabel,
        ),
        if (_showHydraulicVolumeStepperFor(slot)) ...[
          const SizedBox(height: 12),
          MilliliterQuantityStepper(
            controller: slot.sizeAmount,
            enabled: !busy,
            labelText: volumeLabel,
            onChanged: () {
              _onOilOrHydraulicVolumeChanged(
                syncStockLiters: () {
                  if (_usesWarehouseHydraulicPickerFor(slot)) {
                    _syncHydraulicLitersFromStepperFor(slot);
                  }
                },
              );
            },
          ),
        ],
    ];
    if (wrapInSectionCard) {
      return _buildSectionCard(
        context,
        title: title,
        icon: Icons.water_drop_outlined,
        children: fields,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: fields,
    );
  }

  Widget _buildOilServiceCheckbox(
    OilChangeServiceItem s,
    ColorScheme cs,
    bool busy,
  ) {
    final checked = _selectedOilServiceIds.contains(s.id);
    final priceLbl = s.priceFils > 0
        ? IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(s.priceFils))
        : '—';
    return InkWell(
      onTap: busy
          ? null
          : () {
              _rebuild(() {
                if (checked) {
                  _selectedOilServiceIds.remove(s.id);
                } else {
                  _selectedOilServiceIds.add(s.id);
                }
                _agreedTotalManual = false;
                _recalculateOilTotal();
              });
            },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: checked
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          border: Border.all(
            color: checked ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
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
                '${s.name} · $priceLbl',
                style: TextStyle(
                  fontWeight: checked ? FontWeight.w800 : FontWeight.w500,
                  color: checked ? cs.primary : cs.onSurface,
                  fontSize: 12,
                ),
                textAlign: TextAlign.start,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOilLiterPriceHint(ColorScheme cs) {
    final liters = _oilLitersForPricing();
    if (_usesCatalogOilPricing) {
      final perLiter = _catalogSellPerLiterFils!;
      final material = _oilMaterialSellFilsEst();
      return Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: Text(
          liters > 1e-9
              ? 'سعر اللتر: ${_formatFilsLabel(perLiter)} × ${formatOilLitersDisplay(liters)} لتر = ${_formatFilsLabel(material)}'
              : 'سعر اللتر: ${_formatFilsLabel(perLiter)}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
          textAlign: TextAlign.start,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Text(
        'أضف سعر اللتر من زر + بجانب اسم الزيت (ماركة ولزوجة).',
        style: TextStyle(
          fontSize: 12,
          color: cs.error,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.start,
      ),
    );
  }

  Widget _buildOilFormScrollStack(
    BuildContext context, {
    required ColorScheme cs,
    required ScreenLayout layout,
    required double pagePad,
    required bool busy,
    double maxWidth = 720,
  }) {
    return Stack(
      children: [
        AdaptiveFormContainer(
          maxWidth: maxWidth,
          child: Form(
            key: _formKey,
            child: RawKeyboardInsetBuilder(
              builder: (context, keyboardBottom) {
                final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
                // حجز شريط النظام + جزء من IME دون مبالغة مع adjustPan.
                final bottomPad = 24 +
                    80 +
                    safeBottom +
                    (keyboardBottom > 8
                        ? (keyboardBottom * 0.45).clamp(0.0, 220.0)
                        : 0.0);
                return ListView(
              padding: EdgeInsetsDirectional.fromSTEB(
                pagePad,
                14,
                pagePad,
                bottomPad,
              ),
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

              // 1. بيانات العميل
              GuideAnchor(
                id: OilGuideAnchors.formCustomer,
                child: _buildSectionCard(
                context,
                title: 'بيانات العميل',
                icon: Icons.person_outline_rounded,
                children: [
                    GuideAnchor(
                      id: OilGuideAnchors.formCustomerName,
                      child: OilChangeCustomerNameField(
                        controller: _customerName,
                        focusNode: _customerFocus,
                        enabled: !busy,
                        customerLinked: _customerId != null,
                        onSelected: (c) =>
                            unawaited(_applyCustomerSelection(c)),
                        validator: _oilCustomerNameRequiredError,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: GuideAnchor(
                            id: OilGuideAnchors.formCustomerPhone,
                            child: TextFormField(
                              controller: _customerPhone,
                              onTap: oilPhoneKeepPrefixOnTap(_customerPhone),
                              decoration: InputDecoration(
                                labelText: 'رقم الهاتف',
                                border: const OutlineInputBorder(),
                                isDense: true,
                                prefixIcon:
                                    const Icon(Icons.phone_rounded, size: 20),
                                hintText: '07xxxxxxxxx',
                                helperText: widget.amendInvoicedOrder
                                    ? 'عند تصحيح الرقم تُعاد إرسال بطاقة واتساب '
                                        'لنفس البطاقة (قالب ميتا) دون إنشاء بطاقة جديدة'
                                    : '11 رقماً تبدأ بـ 07',
                                helperMaxLines: widget.amendInvoicedOrder ? 3 : 1,
                              ),
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.start,
                              inputFormatters: _OilChangeOrderFormScreenState._iraqiMobilePhoneFormatters,
                              validator: _oilCustomerPhoneRequiredError,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          tooltip: 'عميل جديد',
                          onPressed: busy ? null : _openNewCustomer,
                          icon: const Icon(Icons.person_add_alt_rounded),
                        ),
                      ],
                    ),
                    if (!widget.amendInvoicedOrder &&
                        _waAutoAfterSave != false)
                      WaReminderConsentTile(
                        value: _waReminderConsent,
                        prior: _waReminderPrior,
                        onChanged: busy
                            ? null
                            : (v) => _rebuild(() => _waReminderConsent = v),
                      ),
                ],
              ),
              ),

              // 2. بيانات السيارة
              GuideAnchor(
                id: OilGuideAnchors.formCar,
                child: _buildSectionCard(
                context,
                title: 'بيانات السيارة',
                icon: Icons.directions_car_outlined,
                children: [
                    if (!widget.isEdit &&
                        _customerVehicles.length >= 2 &&
                        _customerVehiclesFor == _customerId) ...[
                      Text(
                        'سيارات العميل — اختر السيارة التي أحضرها:',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final v in _customerVehicles)
                            ChoiceChip(
                              key: Key('customerCar_${v['global_id']}'),
                              label: Text(
                                [
                                  (v['plate_display'] ?? '').toString(),
                                  (v['name'] ?? '').toString(),
                                ].where((s) => s.trim().isNotEmpty).join(' · '),
                              ),
                              selected:
                                  OilChangeLookupNormalize.normalizePlateKey(
                                    _deviceSerial.text,
                                  ) ==
                                  (v['plate_key'] ?? '').toString(),
                              onSelected: busy
                                  ? null
                                  : (_) => _pickCustomerVehicle(v),
                            ),
                          ActionChip(
                            key: const Key('customerCarNew'),
                            avatar: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('سيارة جديدة'),
                            onPressed: busy ? null : _pickNewCustomerVehicle,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    _compactSideBySide(
                      context: context,
                      start: TextFormField(
                        controller: _deviceName,
                        onTap: oilFieldSelectAllOnTap(_deviceName),
                        decoration: const InputDecoration(
                          labelText: 'اسم السيارة',
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: 'تويوتا كورولا',
                        ),
                        validator: (v) => _isFieldRequired(OilCardField.carName) &&
                                (v == null || v.trim().isEmpty)
                            ? 'اسم السيارة مطلوب'
                            : null,
                        textAlign: TextAlign.start,
                      ),
                      end: GuideAnchor(
                        id: OilGuideAnchors.formPlate,
                        child: IraqPlateField(
                        controller: _deviceSerial,
                        defaultProvince:
                            widget.isEdit ? null : _defaultPlateProvince,
                        required: _isFieldRequired(OilCardField.plate),
                        onNumberDone: widget.isEdit
                            ? null
                            : () => unawaited(
                                  _syncVehicleFromPlate(askLegacy: true),
                                ),
                        suffixIcon: !widget.isEdit
                            ? IconButton(
                                tooltip: 'جلب بيانات آخر زيارة',
                                onPressed: busy
                                    ? null
                                    : () => unawaited(
                                          _syncVehicleFromPlate(
                                            showFeedback: true,
                                            overwriteExisting: true,
                                            force: true,
                                            askLegacy: true,
                                          ),
                                        ),
                                icon: const Icon(Icons.sync_rounded),
                              )
                            : null,
                      ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _compactSideBySide(
                      context: context,
                      start: TextFormField(
                        controller: _carModel,
                        onTap: oilFieldSelectAllOnTap(_carModel),
                        decoration: const InputDecoration(
                          labelText: 'موديل السيارة',
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: '2022',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: _OilChangeOrderFormScreenState._carModelDigitFormatters,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        onEditingComplete: _normalizeCarModelDisplay,
                      ),
                      end: TextFormField(
                        controller: _engineSize,
                        onTap: oilFieldSelectAllOnTap(_engineSize),
                        decoration: const InputDecoration(
                          labelText: 'حجم المحرك',
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: '1.8',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: _OilChangeOrderFormScreenState._engineSizeInputFormatters,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                      ),
                    ),
                    if (!widget.isEdit)
                      Padding(
                        padding:
                            const EdgeInsetsDirectional.only(start: 4, top: 6),
                        child: Text(
                          'رقم اللوحة مطلوب. عند إدخاله تُحمَّل بيانات آخر زيارة تلقائياً إن وُجدت.',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: cs.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ),
                ],
              ),
              ),

              // 3. العداد — ظاهر دائماً؛ الزيت صار زراً ضمن الأقسام.
              _buildSectionCard(
                context,
                title: 'العداد',
                icon: Icons.speed_rounded,
                children: [
                  _responsivePair(
                    context,
                    sideBySideOnPhone: true,
                    gap: 8,
                    first: GuideAnchor(
                      id: OilGuideAnchors.formOdoCurrent,
                      child: TextFormField(
                      controller: _odometerCurrent,
                      onTap: oilFieldSelectAllOnTap(_odometerCurrent),
                      decoration: InputDecoration(
                        labelText: 'القراءة الحالية (كم)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: _previousOdometerHelper,
                        helperMaxLines: 2,
                        helperStyle: _odometerLowerThanPrevious
                            ? TextStyle(
                                color: cs.error,
                                fontWeight: FontWeight.w700,
                              )
                            : null,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: _OilChangeOrderFormScreenState._odometerInputFormatters,
                      validator: (v) =>
                          _isFieldRequired(OilCardField.odometerCurrent) &&
                                  _odometerDigits(v ?? '').isEmpty
                          ? 'القراءة الحالية مطلوبة'
                          : null,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                    ),
                    second: TextFormField(
                      controller: _odometerNext,
                      onTap: oilFieldSelectAllOnTap(_odometerNext),
                      decoration: const InputDecoration(
                        labelText: 'القراءة اللاحقة (كم)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: _OilChangeOrderFormScreenState._odometerInputFormatters,
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.start,
                    ),
                  ),
                ],
              ),

                if (_anyOptionalExtrasEnabled) ...[
                _buildOilOptionalQuickBar(cs, busy),
                if (_shouldRenderOptionalSection(_OilFormOptionalSection.oil))
                GuideAnchor(
                  id: OilGuideAnchors.formOil,
                  child: _buildOilOptionalSection(
                    context,
                    section: _OilFormOptionalSection.oil,
                    childrenBuilder: () => [
                  if (_showCatalogOilFields)
                    GuideAnchor(
                      id: OilGuideAnchors.formOilBrand,
                      child: oilChangeFieldPairWithAction(
                        context: context,
                        start: DropdownButtonFormField<String>(
                          value: _oilBrandDropdownValue,
                          decoration: InputDecoration(
                            labelText: 'اسم الزيت',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            hintText: _oilProductCatalogLoading
                                ? 'جاري التحميل…'
                                : (_oilBrandDropdownItems.isEmpty
                                    ? 'أضف زيتاً من +'
                                    : 'اختر الزيت'),
                          ),
                          isExpanded: true,
                          items: _oilBrandDropdownItems
                              .map(
                                (b) => DropdownMenuItem(
                                  value: b,
                                  child: Text(
                                    b,
                                    textAlign: TextAlign.start,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: busy ||
                                  (_oilProductCatalogLoading &&
                                      _oilBrandDropdownItems.isEmpty)
                              ? null
                              : _onOilBrandDropdownChanged,
                        ),
                        end: DropdownButtonFormField<String>(
                          value: _oilViscosityDropdownValue,
                          decoration: InputDecoration(
                            labelText: 'اللزوجة',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            hintText: _oilBrandDropdownValue == null
                                ? 'اختر الاسم أولاً'
                                : (_oilViscosityDropdownEntries.isEmpty
                                    ? 'لا قياسات'
                                    : 'اختر اللزوجة'),
                          ),
                          isExpanded: true,
                          items: _oilViscosityDropdownEntries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.viscosity,
                                  child: Text(
                                    e.viscosity,
                                    textAlign: TextAlign.start,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: busy ||
                                  _oilBrandDropdownValue == null ||
                                  _oilViscosityDropdownEntries.isEmpty
                              ? null
                              : _onOilViscosityDropdownChanged,
                        ),
                        action: GuideAnchor(
                          id: OilGuideAnchors.formOilCatalogBtn,
                          child: IconButton.filledTonal(
                            onPressed: busy
                                ? null
                                : () => unawaited(_openOilCatalogManage()),
                            tooltip: 'إضافة زيت / لزوجة للكتالوج',
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ),
                      ),
                    ),
                  _buildOilSourceSegment(cs, busy),
                  _buildWarehouseOilPickRow(context, cs, busy),
                  if (_showOilVolumeStepper) ...[
                    const SizedBox(height: 12),
                    MilliliterQuantityStepper(
                      controller: _oilSizeAmount,
                      enabled: !busy,
                      labelText: 'حجم الزيت المستعمل',
                      unitSuffix: 'لتر',
                      onChanged: () {
                        _onOilOrHydraulicVolumeChanged(
                          syncStockLiters: () {
                            if (_usesWarehouseOilPicker ||
                                _usesShopOilFromStock) {
                              _syncStockLitersFromStepper();
                            }
                          },
                        );
                      },
                    ),
                    if (_showCatalogOilFields &&
                        !_oilCustomerProvided &&
                        _oilBrandDropdownValue != null &&
                        _oilViscosityDropdownValue != null) ...[
                      const SizedBox(height: 8),
                      _buildOilLiterPriceHint(cs),
                    ],
                  ],
                    ],
                  ),
                ),
                if (_shouldRenderOptionalSection(
                    _OilFormOptionalSection.products))
                _buildOilOptionalSection(
                  context,
                  section: _OilFormOptionalSection.products,
                  childrenBuilder: () => [
                OilChangeProductsCard(
                      bare: true,
                  lines: _oilProductLines,
                  busy: busy || _oilBarcodeBusy,
                      onScanBarcode: () =>
                          unawaited(_openOilProductBarcodeCapture()),
                  onAddProduct: () => unawaited(_openOilProductPicker()),
                  onQuantityChanged: _onOilProductQuantityChanged,
                  onRemoveLine: _onOilProductLineRemoved,
                ),
                  ],
                ),
                if (_shouldRenderOptionalSection(
                    _OilFormOptionalSection.filters))
                _buildOilOptionalSection(
                  context,
                  section: _OilFormOptionalSection.filters,
                  childrenBuilder: () => [
                    if (_filterProductCatalogLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    for (var i = 0; i < _filterKinds.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _buildFilterKindRow(
                        context: context,
                        cs: cs,
                        busy: busy,
                        kind: _filterKinds[i],
                      ),
                    ],
                    if (_filterProductCatalog.isEmpty &&
                        !_filterProductCatalogLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'لا توجد فلاتر في الكتالوج. اضغط + بجانب كل فئة لإضافة اسم وسعر.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.start,
                        ),
                      ),
                  ],
                ),
                if (_shouldRenderOptionalSection(
                    _OilFormOptionalSection.hydraulicGear))
                _buildOilOptionalSection(
                  context,
                  section: _OilFormOptionalSection.hydraulicGear,
                  childrenBuilder: () => [
                    _buildHydraulicFluidCard(
                      context,
                      title: 'هيدروليك الكير',
                      slot: _gearHydraulic,
                      busy: busy,
                      cs: cs,
                      catalogNameLabel: 'اسم هيدروليك الكير',
                      volumeLabel: 'حجم هيدروليك الكير',
                      sourceTitle: 'مصدر هيدروليك الكير',
                      shopLabel: 'هيدروليك الكير (المحل)',
                      customerLabel: 'هيدروليك الكير (العميل)',
                      customerHint:
                          'لن يُخصم مخزون — العميل أحضر هيدروليك الكير.',
                      stockLabel: 'هيدروليك الكير من المخزون',
                      warehouseLabel: 'مستودع هيدروليك الكير',
                      wrapInSectionCard: false,
                    ),
                  ],
                ),
                if (_shouldRenderOptionalSection(
                    _OilFormOptionalSection.hydraulicPower))
                _buildOilOptionalSection(
                  context,
                  section: _OilFormOptionalSection.hydraulicPower,
                  childrenBuilder: () => [
                    _buildHydraulicFluidCard(
                      context,
                      title: 'هيدروليك الباور',
                      slot: _powerHydraulic,
                      busy: busy,
                      cs: cs,
                      catalogNameLabel: 'اسم هيدروليك الباور',
                      volumeLabel: 'حجم هيدروليك الباور',
                      sourceTitle: 'مصدر هيدروليك الباور',
                      shopLabel: 'هيدروليك الباور (المحل)',
                      customerLabel: 'هيدروليك الباور (العميل)',
                      customerHint:
                          'لن يُخصم مخزون — العميل أحضر هيدروليك الباور.',
                      stockLabel: 'هيدروليك الباور من المخزون',
                      warehouseLabel: 'مستودع هيدروليك الباور',
                      wrapInSectionCard: false,
                    ),
                  ],
                ),
                if (_shouldRenderOptionalSection(
                    _OilFormOptionalSection.services))
                _buildOilOptionalSection(
                  context,
                  section: _OilFormOptionalSection.services,
                  childrenBuilder: () => [
                    if (_oilCatalog.isEmpty)
                      Text(
                        'لا توجد خدمات إضافية. أضفها من «الخدمات وأسعارها».',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                        textAlign: TextAlign.start,
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _oilCatalog
                            .map((s) => _buildOilServiceCheckbox(s, cs, busy))
                            .toList(),
                      ),
                  ],
                ),
                ],
                if (!layout.isWideVariant) ...[
                  _buildOilTechnicianNotesSection(context, busy),
                  _buildOilCheckoutSectionCard(context, busy),
                ],

            ],
                );
              },
            ),
          ),
        ),
      // البطاقة من السجل تظهر ببياناتها فوراً؛ شريط رفيع فقط حتى تكتمل
      // مطابقة الأسعار والمخزون (الحفظ معطّل خلالها عبر busy).
      if (_prefillBootstrapInProgress)
        const PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          child: LinearProgressIndicator(minHeight: 2),
        ),
    ],
    );
  }
  String _oilAppBarTitle() {
    if (widget.isEdit) {
      if (_status == OilChangeOrderStatus.suspended) {
        return 'استكمال بطاقة معلّقة';
      }
      return 'تعديل بطاقة غيار زيت';
    }
    if (widget.prefillFromOrder != null) return 'زيارة غيار جديدة';
    return 'بطاقة غيار زيت جديدة';
  }

  /// لوحة جانبية ثابتة — للشاشات الواسعة فقط.
  Widget _buildOilCheckoutPanel(BuildContext context, bool busy) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: BorderDirectional(
          end: BorderSide(
            color: OilChangeRoyalCard.gold.withValues(alpha: 0.35),
            width: 1.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GuideAnchor(
              id: OilGuideAnchors.formTechnician,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            Row(
              children: [
                const Icon(
                  Icons.edit_note_rounded,
                  color: OilChangeRoyalCard.gold,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'الفني والملاحظات',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ..._buildOilTechnicianAndNotesFields(
              context,
              busy,
              compact: false,
            ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            GuideAnchor(
              id: OilGuideAnchors.formPayment,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
            Row(
              children: [
                const Icon(
                  Icons.payments_outlined,
                  color: OilChangeRoyalCard.gold,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  'السعر والدفع',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: cs.onSurface,
                  ),
                  textAlign: TextAlign.start,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._oilCheckoutFields(context, busy, compact: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
