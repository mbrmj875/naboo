part of '../oil_change_order_form_screen.dart';

// حفظ بطاقة الغيار: التحقق، كتابة البطاقة، البيع، ومهام ما بعد الحفظ.
//
// امتداد على حالة الشاشة؛ الحالة كلها تبقى في الشاشة.
extension _OilFormSave on _OilChangeOrderFormScreenState {
  /// أعمدة التسعير المحفوظة في البطاقة (الإصدار 51): أجرة التبديل الفعلية،
  /// وأجرة يد الهيدروليك حين يُحضره العميل، وسعر لتر هيدروليك الكتالوج.
  /// الفاتورة تُبنى منها فلا تتغير إن تغيّرت الإعدادات بعد الحفظ.
  Map<String, Object?> _cardPricingColumnsForSave() {
    int? catalogSell(OilChangeHydraulicCardSlot slot) =>
        !slot.customerProvided &&
            !_usesWarehouseHydraulicPickerFor(slot) &&
            (slot.catalogSellPerLiterFils ?? 0) > 0
        ? slot.catalogSellPerLiterFils
        : null;
    return {
      'odometerUnit': _odometerUnit,
      'oilLaborFils': _oilLaborFils(),
      'hydraulicLaborFils': _gearHydraulic.customerProvided
          ? _hydraulicLaborFilsFor(_gearHydraulic)
          : null,
      'powerHydraulicLaborFils': _powerHydraulic.customerProvided
          ? _hydraulicLaborFilsFor(_powerHydraulic)
          : null,
      'hydraulicSellPerLiterFils': catalogSell(_gearHydraulic),
      'powerHydraulicSellPerLiterFils': catalogSell(_powerHydraulic),
    };
  }

  /// عند حفظ البطاقة بالاسم/الهاتف مباشرة: إنشاء أو ربط سجل في جدول العملاء
  /// ليظهر في إدارة العملاء وقائمة الاتصال.
  Future<void> _ensureCustomerRecordFromOilForm({
    required String customerName,
    required String phoneRaw,
  }) async {
    final name = customerName.trim();
    if (name.isEmpty || name == '—') return;

    final nameErr = CustomerValidation.name(name);
    if (nameErr != null) return;

    final e164 = CustomerValidation.toE164IraqMobile(phoneRaw);
    final phoneOk =
        e164 != null && CustomerValidation.iraqiMobilePhone(phoneRaw) == null;
    final phoneForSave = phoneOk ? e164 : null;

    final tenantCtx = TenantContextService.instance;
    if (!tenantCtx.loaded) {
      await DatabaseHelper().ensureDefaultTenantSeedIfNeeded();
      await tenantCtx.load();
    }
    final tenantId = tenantCtx.requireActiveTenantId();

    Future<void> linkLocal(int cid) async {
      if (!mounted) return;
      _suspendCustomerIdClear = true;
      _rebuild(() {
        _customerId = cid;
        _linkedCustomerName = name;
      });
      // تصحيح مفوتر: لا تؤخر الحفظ بانتظار اصطناعي.
      if (!widget.amendInvoicedOrder) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
      _suspendCustomerIdClear = false;
    }

    /// يزامن اسم (وهاتف إن لزم) سجل العملاء المرتبط عند تصحيح البطاقة أو الحفظ.
    Future<void> syncLinkedCustomerProfile(int cid) async {
      try {
        final row = await _customersDb.getCustomerById(cid);
        if (row == null) return;

        final currentName = (row['name']?.toString() ?? '').trim();
        final currentPhoneKey = CustomerValidation.phoneMatchKey(
          row['phone']?.toString(),
        );
        final nameChanged =
            OilChangeLookupNormalize.normalizeNameKey(currentName) !=
            OilChangeLookupNormalize.normalizeNameKey(name);
        // هاتف: املأ الفارغ دائماً؛ وعند التصحيح حدّث إن تغيّر في النموذج.
        final phoneForSaveKey = CustomerValidation.phoneMatchKey(phoneForSave);
        final phoneChanged =
            phoneForSave != null &&
            phoneForSave.isNotEmpty &&
            (currentPhoneKey == null ||
                currentPhoneKey.isEmpty ||
                (widget.amendInvoicedOrder &&
                    phoneForSaveKey != currentPhoneKey));

        if (!nameChanged && !phoneChanged) return;

        final extras = await _customersDb.getCustomerExtraPhones(cid);
        final phoneOut = phoneChanged
            ? phoneForSave
            : (row['phone']?.toString());
        await _customersDb.updateCustomer(
          id: cid,
          name: name,
          phone: phoneOut,
          email: row['email']?.toString(),
          address: row['address']?.toString(),
          notes: row['notes']?.toString(),
          extraPhones: extras,
        );
      } catch (e, st) {
        AppLogger.error(
          'OilChangeForm',
          'sync linked customer profile failed',
          e,
          st,
        );
      }
    }

    try {
      var cid = _customerId;
      if (cid != null && cid > 0) {
        await syncLinkedCustomerProfile(cid);
        await linkLocal(cid);
        CustomerSearchIndex.instance.invalidate();
        if (mounted) {
          unawaited(context.read<CustomersProvider>().refresh());
        }
        return;
      }

      if (phoneForSave != null) {
        cid = await _customersDb.findCustomerIdOwningNormalizedPhoneAnywhere(
          phoneForSave,
        );
      }
      // الربط بالهاتف فقط (والهاتف إلزامي في البطاقة): اسم مطابق بهاتف
      // مختلف عميل جديد، لا ربط بالاسم.
      if (cid != null && cid > 0) {
        await linkLocal(cid);
        await syncLinkedCustomerProfile(cid);
      } else {
        try {
          final newId = await _customersDb.insertCustomer(
            name: name,
            phone: phoneForSave,
            tenantId: tenantId,
          );
          await linkLocal(newId);
        } on DuplicateCustomerPhoneException {
          if (phoneForSave != null) {
            final existing = await _customersDb
                .findCustomerIdOwningNormalizedPhoneAnywhere(phoneForSave);
            if (existing != null && existing > 0) {
              await linkLocal(existing);
              await syncLinkedCustomerProfile(existing);
            }
          }
        }
      }

      CustomerSearchIndex.instance.invalidate();
      if (mounted) {
        unawaited(context.read<CustomersProvider>().refresh());
      }
    } catch (e, st) {
      AppLogger.error(
        'OilChangeForm',
        'ensure customer from oil form failed',
        e,
        st,
      );
    }
  }

  /// صف المسودة: لقطة البطاقة + ما يلزم لاستعادة المخزون والأجور كما كُتبت.
  Map<String, dynamic> _draftRowFromForm() {
    double? liters(double v) => v > 0 ? v : null;
    final row = _orderSnapshotFromForm()..remove('createdAt');
    return {
      ...row,
      'status': 'pending',
      'oilCustomerProvided': _oilCustomerProvided ? 1 : 0,
      'oilProductId': _oilStockProductId,
      'oilWarehouseId': _oilWarehouseId,
      'oilLitersUsed': liters(_parseOilLitersStock()),
      'oilSellPerLiterFils': _catalogSellPerLiterFils,
      // الأجور كما كتبها الموظف (null = من الإعدادات)، لا القيمة المحسوبة.
      'oilLaborFils': _oilLaborCardFils,
      'hydraulicLaborFils': _gearHydraulic.laborCardFils,
      'powerHydraulicLaborFils': _powerHydraulic.laborCardFils,
      for (final slot in [_gearHydraulic, _powerHydraulic]) ...{
        slot.col('ProductId'): slot.stockProductId,
        slot.col('WarehouseId'): slot.warehouseId,
        slot.col('LitersUsed'): liters(slot.litersForPricing()),
      },
    };
  }

  Future<void> _autosaveDraft() async {
    if (!mounted || widget.isEdit || _draftDone || _saving) return;
    if (!_hasUnsavedOilDraft()) return;
    try {
      await OilCardDraftStore.instance.save(
        _draftRowFromForm(),
        List.of(_oilProductLines),
      );
    } catch (_) {}
  }

  Future<void> _offerDraftRestore() async {
    if (widget.isEdit || widget.prefillFromOrder != null) return;
    final draft = await OilCardDraftStore.instance.load();
    if (draft == null || !mounted || _hasUnsavedOilDraft()) return;
    final t = draft.savedAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final when =
        '${t.year}/${two(t.month)}/${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
    final restore = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('بطاقة غير محفوظة'),
        content: Text(
          'توجد بطاقة لم تُحفظ: ${draft.summary}\nآخر تعديل: $when',
          textAlign: TextAlign.start,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تجاهلها'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (restore != true) {
      await OilCardDraftStore.instance.clear();
      return;
    }
    await _loadFluidStockSettings();
    if (!mounted) return;
    _rebuild(() {
      _hydrateEditFieldsFromRow(draft.row);
      _status = 'pending';
      _oilProductLines
        ..clear()
        ..addAll(draft.productLines);
    });
    unawaited(_loadFilterProductCatalog());
    _recalculateOilTotal();
  }

  Map<String, dynamic> _orderSnapshotFromForm() {
    final sizeVal = _oilSizeValueForSave();
    final phoneRaw = _customerPhone.text.trim();
    final phoneStored =
        CustomerValidation.toE164IraqMobile(phoneRaw) ?? phoneRaw;
    return {
      if (_customerId != null && _customerId! > 0) 'customerId': _customerId,
      'customerNameSnapshot': _customerName.text.trim(),
      'customerPhone': phoneStored,
      'deviceName': _deviceName.text.trim(),
      'carModel': _carModelForSave,
      'engineSize': _engineSize.text.trim(),
      'deviceSerial': _deviceSerial.text.trim(),
      'odometerCurrent': _odometerCurrentForSave,
      'odometerNext': _odometerNextForSave,
      'oilType': _oilType.text.trim(),
      'oilViscosity': _selectedViscosity,
      'oilSize': sizeVal,
      'hydraulicType': _gearHydraulic.type.text.trim(),
      'hydraulicGrade': _gearHydraulic.selectedGrade,
      'hydraulicSize': _hydraulicSizeValueForSaveFor(_gearHydraulic),
      'hydraulicCustomerProvided': _gearHydraulic.customerProvided ? 1 : 0,
      'powerHydraulicType': _powerHydraulic.type.text.trim(),
      'powerHydraulicGrade': _powerHydraulic.selectedGrade,
      'powerHydraulicSize': _hydraulicSizeValueForSaveFor(_powerHydraulic),
      'powerHydraulicCustomerProvided': _powerHydraulic.customerProvided
          ? 1
          : 0,
      'filterType': _filterTypeSummaryForSave(),
      'oilFiltersJson': _oilFiltersJsonForSave(),
      'engineFilterName': _filterSlotFor(OilChangeFilterKind.engine).name,
      'engineFilterPriceFils': _filterSlotFor(
        OilChangeFilterKind.engine,
      ).priceFils,
      'airFilterName': _filterSlotFor(OilChangeFilterKind.air).name,
      'airFilterPriceFils': _filterSlotFor(OilChangeFilterKind.air).priceFils,
      'gearFilterName': _filterSlotFor(OilChangeFilterKind.gear).name,
      'gearFilterPriceFils': _filterSlotFor(OilChangeFilterKind.gear).priceFils,
      'requestedServices': _oilServiceNamesForSave(),
      'technicianName': _technicianName.text.trim(),
      'issueDescription': _issue.text.trim(),
      'agreedPriceFils': _oilCheckoutTotalFils(),
      'advancePaymentFils': _oilCheckoutPaidFils(),
      'estimatedPriceFils': _parseFils(_estimated),
      ..._cardPricingColumnsForSave(),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }

  Future<void> _issueNewCardStockInParallel({
    required int savedId,
    required bool oilCustomer,
    required int? oilPid,
    required int? oilWh,
    required double oilLiters,
    required bool hydCustomer,
    required int? hydPid,
    required int? hydWh,
    required double hydLiters,
    required bool powerHydCustomer,
    required int? powerHydPid,
    required int? powerHydWh,
    required double powerHydLiters,
  }) async {
    // تسلسلي عمداً: التشغيل المتوازي كان يترك صرفاً جزئياً عند فشل فرع.
    if (_stockFromWarehouseEnabled &&
        !oilCustomer &&
        oilPid != null &&
        oilLiters > 0) {
      final voucherId = await OilChangeStockService.instance
          .issueForOilChangeOrder(
            orderId: savedId,
            productId: oilPid,
            liters: oilLiters,
            warehouseId: oilWh ?? 0,
            notes: 'صرف زيت',
            allowNegative: _stockOverrideApproved,
          );
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        savedId,
        patchOilStockFields: true,
        stockVoucherId: voucherId,
        oilProductId: oilPid,
        oilLitersUsed: oilLiters,
        oilCustomerProvided: false,
        oilWarehouseId: oilWh,
      );
    }

    if (_gearHydraulicStockEnabled &&
        !hydCustomer &&
        hydPid != null &&
        hydLiters > 0) {
      final hydVoucherId = await OilChangeStockService.instance
          .issueForOilChangeOrder(
            orderId: savedId,
            productId: hydPid,
            liters: hydLiters,
            warehouseId: hydWh ?? 0,
            notes: 'صرف هيدروليك الكير',
            allowNegative: _stockOverrideApproved,
          );
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        savedId,
        patchHydraulicStockFields: true,
        hydraulicStockVoucherId: hydVoucherId,
        hydraulicProductId: hydPid,
        hydraulicLitersUsed: hydLiters,
        hydraulicCustomerProvided: false,
        hydraulicWarehouseId: hydWh,
      );
    }

    if (_powerHydraulicStockEnabled &&
        !powerHydCustomer &&
        powerHydPid != null &&
        powerHydLiters > 0) {
      final powerVoucherId = await OilChangeStockService.instance
          .issueForOilChangeOrder(
            orderId: savedId,
            productId: powerHydPid,
            liters: powerHydLiters,
            warehouseId: powerHydWh ?? 0,
            notes: 'صرف هيدروليك الباور',
            allowNegative: _stockOverrideApproved,
          );
      await OilChangeOrdersRepository.instance.updateOilChangeOrder(
        savedId,
        patchPowerHydraulicStockFields: true,
        powerHydraulicStockVoucherId: powerVoucherId,
        powerHydraulicProductId: powerHydPid,
        powerHydraulicLitersUsed: powerHydLiters,
        powerHydraulicCustomerProvided: false,
        powerHydraulicWarehouseId: powerHydWh,
      );
    }
  }

  void _showRootSnackBar(
    String message, {
    Duration duration = const Duration(seconds: 6),
  }) {
    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    ScaffoldMessenger.of(
      ctx,
    ).showSnackBar(SnackBar(content: Text(message), duration: duration));
  }

  /// مفتاح مقارنة هاتف — أرقام غربية فقط بدون فواصل.
  String _normalizedPhoneKey(String? raw) {
    final western = OilChangeLookupNormalize.toWesternDigits(raw ?? '');
    return CustomerValidation.normalizePhoneDigits(western) ?? '';
  }

  bool _phoneChangedFromAmendBaseline() {
    return oilChangeAmendShouldResendWhatsapp(
      amendInvoicedOrder: widget.amendInvoicedOrder,
      currentPhoneDigits: _normalizedPhoneKey(_customerPhone.text),
      baselinePhoneDigits: _baselineCustomerPhoneDigits,
    );
  }

  Future<_OilPostSaveJob?> _buildOilPostSaveJob({
    required Map<String, dynamic>? savedOrder,
    required int? orderId,
    required bool openInvoice,
    bool skipPostSaveActions = false,
    bool wasSuspendedSave = false,
    bool completingSuspendedSale = false,
  }) async {
    if (skipPostSaveActions) return null;

    final order = Map<String, dynamic>.from(
      savedOrder ?? _orderSnapshotFromForm(),
    );
    if (_customerId != null && _customerId! > 0) {
      order['customerId'] = _customerId;
    }

    int? invoiceId;
    String? checkoutError;
    final amending = widget.amendInvoicedOrder;

    if (amending && orderId != null && orderId > 0 && mounted) {
      final auth = context.read<AuthProvider>();
      final staff = auth.username.trim();
      try {
        final result = await OilChangePostSaleService.instance.amendFromOrder(
          orderId: orderId,
          actorUsername: staff.isEmpty ? null : staff,
          actorUserId: auth.userId,
          // المدفوع عند البيع كما فُتحت البطاقة: ما سُدِّد بعده يبقى للعميل.
          originalCardAdvanceFils:
              (widget.prefillFromOrder?['advancePaymentFils'] as num?)?.toInt(),
        );
        invoiceId = result.invoiceId;
      } on OilChangePostSaleException catch (e) {
        checkoutError = 'حُفظت البطاقة لكن تعذر تعديل الفاتورة: ${e.message}';
      } catch (e) {
        checkoutError = 'تعذر تعديل الفاتورة: $e';
      }
    } else if (openInvoice && orderId != null && orderId > 0 && mounted) {
      final staff = context.read<AuthProvider>().username.trim();
      try {
        final result = await OilChangeCheckoutService.instance
            .completeFromOrder(
              order: order,
              orderId: orderId,
              createdByUserName: staff.isEmpty ? null : staff,
            );
        invoiceId = result.invoiceId;
      } on OilChangeCheckoutException catch (e) {
        // داخل المعاملة الواحدة: فشل البيع يلغي حفظ البطاقة والصرف معه.
        if (SharedDbTransaction.isActive) rethrow;
        checkoutError = 'حُفظت البطاقة لكن تعذر إتمام البيع: ${e.message}';
      } catch (e) {
        if (SharedDbTransaction.isActive) rethrow;
        checkoutError = 'تعذر إتمام البيع: $e';
      }
    }

    final phoneChangedOnAmend = _phoneChangedFromAmendBaseline();
    // عند تغيّر الرقم في التصحيح: أرسل دائماً قالب البطاقة العادي (مسار auto).
    final waAuto = phoneChangedOnAmend
        ? true
        : (amending ? false : (_waAutoAfterSave ?? false));
    final waManual = phoneChangedOnAmend
        ? false
        : (amending ? false : (_waManualAfterSave ?? false));

    if (phoneChangedOnAmend) {
      AppLogger.info(
        'oil_change_wa',
        'amend phone changed → will send normal card template '
            'from=${_baselineCustomerPhoneDigits ?? ''} '
            'to=${_normalizedPhoneKey(_customerPhone.text)}',
      );
      await _warmPostSaveSettings();
    } else if (!amending) {
      await _warmPostSaveSettings();
    }

    final printData = amending && !phoneChangedOnAmend
        ? (_cachedPrintSettings ?? PrintSettingsData.defaults())
        : (_cachedPrintSettings ?? await _loadStoreBrandingForCustomer());
    _cachedPrintSettings = printData;

    return _OilPostSaveJob(
      order: order,
      orderId: orderId,
      invoiceId: invoiceId,
      customerPhone: _customerPhone.text.trim(),
      printSettings: printData,
      waAuto: waAuto,
      waManual: waManual,
      waAskRating: _waAskRatingAfterSave ?? true,
      waReminderConsent: amending ? null : _waReminderConsent,
      priorOpenDebtFils: _priorOpenDebtFilsAtCheckout,
      isEdit: widget.isEdit,
      wasSuspendedSave: wasSuspendedSave,
      completingSuspendedSale: completingSuspendedSale,
      isAmendInvoiced: amending,
      sendWhatsappForPhoneChange: phoneChangedOnAmend,
      productsSummary: _oilProductLines
          .where((line) => line.productName.trim().isNotEmpty)
          .map(
            (line) => line.quantity > 1
                ? '${line.productName.trim()} ×${line.quantity}'
                : line.productName.trim(),
          )
          .join('، '),
      checkoutError: checkoutError,
    );
  }

  void _scheduleOilPostSaveJob(
    _OilPostSaveJob job, {
    bool checkoutErrorShown = false,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _runOilPostSaveJob(job, checkoutErrorShown: checkoutErrorShown),
      );
    });
  }

  /// تسديد من الدين السابق بالزائد عن الزيارة: نفس منطق شاشة الديون (الأقدم
  /// أولاً، سند قبض، قيد صندوق)، داخل معاملة البيع.
  Future<void> _collectOldDebtFromCard({
    required int orderId,
    required int fils,
  }) async {
    final cid = _customerId;
    if (cid == null || cid <= 0 || fils <= 0) return;
    final name = _customerName.text.trim();
    final staff = context.read<AuthProvider>().username.trim();
    await DatabaseHelper().recordCustomerDebtPayment(
      party: CustomerDebtParty(
        customerId: cid,
        displayName: name,
        normalizedName: name.toLowerCase(),
      ),
      amount: IqdMoney.fromFils(fils),
      recordedByUserName: staff.isEmpty ? 'موظف' : staff,
      note: 'من بطاقة غيار #$orderId',
    );
  }

  Future<bool> _confirmNewDebtOverOld({
    required int priorFils,
    required int newFils,
  }) async {
    String m(int f) => IraqiCurrencyFormat.formatIqd(IqdMoney.fromFils(f));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('دين جديد فوق دين سابق'),
          content: Text(
            'على العميل دين سابق ${m(priorFils)}.\n'
            'متبقي هذه الزيارة ${m(newFils)}.\n'
            'الرصيد بعد البيع: ${m(priorFils + newFils)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('متابعة البيع'),
            ),
          ],
        ),
      ),
    );
    return ok == true;
  }

  /// البيع فشل فأُلغي الحفظ كله (المعاملة الواحدة). البطاقة باقية على الشاشة.
  Future<void> _showSaleNotSavedDialog(String reason) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: const Icon(Icons.error_outline_rounded),
          title: const Text('لم يتم البيع ولم يُحفظ شيء'),
          content: Text(
            '$reason\n\n'
            'لم تُحفظ البطاقة ولم يُصرف شيء من المخزون. صحّح السبب ثم اضغط '
            '«حفظ وبيع» مرة أخرى، أو علّق البطاقة.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    );
  }

  /// البطاقة حُفظت لكن البيع لم يتم. يبقى ظاهراً حتى يضغط «حسناً».
  Future<void> _showCardSavedButNotSoldDialog(String reason) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          icon: const Icon(Icons.error_outline_rounded),
          title: const Text('حُفظت البطاقة ولم تُنشأ الفاتورة'),
          content: Text(
            '$reason\n\n'
            'البطاقة موجودة في السجل. افتحها من هناك لإكمال البيع بعد '
            'تصحيح السبب، ولا تنشئ بطاقة جديدة لنفس السيارة.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runOilPostSaveJob(
    _OilPostSaveJob job, {
    bool checkoutErrorShown = false,
  }) async {
    if (!checkoutErrorShown &&
        job.checkoutError != null &&
        job.checkoutError!.trim().isNotEmpty) {
      _showRootSnackBar(
        job.checkoutError!,
        duration: const Duration(seconds: 7),
      );
    }

    // تصحيح فاتورة مكتملة: لا طباعة؛ واتساب فقط إن تغيّر رقم الهاتف (قالب البطاقة العادي).
    if (job.isAmendInvoiced) {
      if (job.sendWhatsappForPhoneChange) {
        await _runOilPostSaveWhatsapp(job);
      }
      return;
    }

    await Future.wait([
      _runOilPostSavePrint(job),
      _runOilPostSaveWhatsapp(job),
    ]);
  }

  Future<void> _runOilPostSavePrint(_OilPostSaveJob job) async {
    final invoiceId = job.invoiceId;
    if (invoiceId == null || invoiceId <= 0) return;
    // قالب «إيصال غيار زيت» على طابعة الجهاز. لا طابعة أو طباعة تلقائية
    // مطفأة = لا شيء ولا رسالة؛ الفشل الحقيقي فقط يظهر.
    final r = await ReceiptPrinter.printInvoice(
      invoiceId,
      auto: true,
      settings: job.printSettings,
    );
    if (r.outcome == PrintOutcome.failed) {
      _showRootSnackBar('حُفظت البطاقة، لكن الطباعة فشلت: ${r.message}');
    }
  }

  Future<void> _runOilPostSaveWhatsapp(_OilPostSaveJob job) async {
    final phone = job.customerPhone;

    final allowAmendPhoneWhatsapp =
        job.isAmendInvoiced && job.sendWhatsappForPhoneChange;

    // الإرسال مطفأ بقرار صاحب المحل: لا تنبيه في كل حفظ.
    if (!job.waAuto && !job.waManual) {
      return;
    }
    if (phone.isEmpty) {
      _showRootSnackBar(
        'لم تُرسل رسالة واتساب: رقم الزبون فارغ في البطاقة.',
        duration: const Duration(seconds: 6),
      );
      return;
    }
    // واتساب عند الحفظ/البيع، أو عند تصحيح البطاقة إذا تغيّر رقم الهاتف فقط.
    if (job.isEdit &&
        !job.completingSuspendedSale &&
        !allowAmendPhoneWhatsapp) {
      return;
    }

    if (job.waAuto) {
      try {
        final outcome = await OilChangeWhatsappNotifyService.instance
            .notifyAfterOilChangeSave(
              customerPhone: phone,
              order: job.order,
              storeTitle: job.printSettings.storeTitleLine,
              storeFooter: job.printSettings.footerExtra,
              orderId: job.orderId,
              invoiceId: job.invoiceId,
              includeRatingAsk: job.waAskRating,
              productsSummary: job.productsSummary,
              printSettings: job.printSettings,
              phoneCorrectionResend: allowAmendPhoneWhatsapp,
              priorOpenDebtFils: job.priorOpenDebtFils,
            );
        final err = OilChangeWhatsappUserMessages.errorSnackbarForOutcome(
          outcome,
        );
        if (err != null) {
          _showRootSnackBar(err, duration: const Duration(seconds: 8));
        }
      } catch (e) {
        _showRootSnackBar('تعذّر إرسال واتساب: $e');
      }
      // بطاقة بلا زيت (فلتر/هيدروليك/خدمة فقط) لا تذكير غيار لها.
      if (oilOrderHasOil(job.order)) {
        try {
          await WaOilFollowupScheduler.instance.enqueueAfterSave(
            orderId: job.orderId,
            customerPhone: phone,
            order: job.order,
            storeTitle: job.printSettings.storeTitleLine,
            consent: job.waReminderConsent,
          );
        } catch (_) {}
      }
      return;
    }

    if (!job.waManual) return;

    final msg = buildOilServiceWhatsAppMessage(
      order: job.order,
      storeTitle: job.printSettings.storeTitleLine,
      storeFooter: job.printSettings.footerExtra,
      priorOpenDebtFils: job.priorOpenDebtFils,
      includeRatingAsk: job.waAskRating,
    );
    final ctx = appRootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await launchWhatsAppWithMessage(ctx, phone: phone, message: msg);
  }

  /// يصرف/يرجع مخزون الفلاتر ويحفظ سندات الصرف في سطورها.
  Future<void> _syncFilterStockAfterSave(int orderId) async {
    final previous = widget.isEdit
        ? _editFilterLines
        : const <OilFilterLineData>[];
    final hadVouchers = previous.any((l) => (l.stockVoucherId ?? 0) > 0);
    if (!_filtersStockEnabled && !hadVouchers) return;
    final next = _oilFilterLinesForSave();
    final synced = await OilChangeStockService.instance.syncFilterStock(
      orderId: orderId,
      previous: previous,
      next: next,
      allowNegative: _stockOverrideApproved,
    );
    await OilChangeOrdersRepository.instance.updateOilChangeOrder(
      orderId,
      oilFiltersJson: encodeOilFiltersJson(synced),
    );
    for (final line in synced) {
      final slot = _filterSlotsByCode[line.code];
      if (slot != null) slot.stockVoucherId = line.stockVoucherId;
    }
    _editFilterLines = synced;
  }

  /// ما تأخذه البطاقة من المخزون عند البيع، مع ما صُرف سابقاً في التعديل.
  List<OilStockNeed> _stockNeedsForSale({
    required bool oilCustomer,
    required int? oilPid,
    required int? oilWh,
    required double oilLiters,
  }) {
    final needs = <OilStockNeed>[];
    final editable = widget.isEdit && _editInvoiceId <= 0;
    if (_stockFromWarehouseEnabled &&
        !oilCustomer &&
        !_usesCatalogOilPricing &&
        (oilPid ?? 0) > 0 &&
        oilLiters > 0) {
      final sameAsBefore =
          (editable || widget.amendInvoicedOrder) &&
          !_editOilCustomerProvided &&
          _editOilProductId == oilPid;
      needs.add(
        OilStockNeed(
          label: 'الزيت',
          productId: oilPid!,
          qty: oilLiters,
          credit: sameAsBefore ? _editOilLitersUsed : 0,
          unit: 'لتر',
        ),
      );
    }
    for (final (slot, label) in [
      (_gearHydraulic, 'هيدروليك الكير'),
      (_powerHydraulic, 'هيدروليك الباور'),
    ]) {
      if (!_hydraulicStockEnabledFor(slot) || slot.customerProvided) continue;
      final pid = slot.stockProductId ?? 0;
      final liters = slot.litersForPricing();
      if (pid <= 0 || liters <= 1e-9) continue;
      final sameAsBefore =
          (editable || widget.amendInvoicedOrder) &&
          !slot.editCustomerProvided &&
          slot.editProductId == pid;
      needs.add(
        OilStockNeed(
          label: label,
          productId: pid,
          qty: liters,
          credit: sameAsBefore ? slot.editLitersUsed : 0,
          unit: 'لتر',
        ),
      );
    }
    final prevByCode = {
      for (final l in _editFilterLines)
        if (l.issuesStock && (l.stockVoucherId ?? 0) > 0) l.code: l,
    };
    for (final kind in _filterKinds) {
      final slot = _filterSlotFor(kind);
      final pid = slot.productId ?? 0;
      if (slot.customerProvided || pid <= 0) continue;
      final prev = prevByCode[kind.code];
      needs.add(
        OilStockNeed(
          label: kind.label,
          productId: pid,
          qty: slot.qty.toDouble(),
          credit: prev != null && prev.productId == pid
              ? prev.qty.toDouble()
              : 0,
        ),
      );
    }
    // المنتجات تُخصم مع الفاتورة؛ بعد الفاتورة لا نعرف ما خُصم فلا تُفحص.
    if (_editInvoiceId <= 0) {
      for (final line in _oilProductLines) {
        needs.add(
          OilStockNeed(
            label: 'منتج: ${line.productName}',
            productId: line.productId,
            qty: line.stockBaseQty,
            unit: line.unitLabel.isEmpty ? 'قطعة' : 'لتر',
          ),
        );
      }
    }
    return needs;
  }

  /// ميزة الديون: إن كانت مطفأة يُمنع المتبقي برسالة واضحة، وللمالك زر
  /// «تفعيل الديون» يفعّلها ويتابع البيع. بلا مزوّد الميزات (الاختبارات) = مفعّلة.
  Future<bool> _ensureDebtsFeatureOn() async {
    BusinessFeaturesProvider? features;
    try {
      features = context.read<BusinessFeaturesProvider>();
    } catch (_) {
      return true;
    }
    if (features.data.enableDebts) return true;
    var isOwner = false;
    try {
      isOwner = context.read<AuthProvider>().isOwner;
    } catch (_) {}
    final enable = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الديون مطفأة في هذا المحل'),
        content: Text(
          isOwner
              ? 'لا يمكن ترك متبقٍّ على العميل والديون مطفأة، لأنه لن يظهر في أي '
                    'صفحة. استلم المبلغ كاملاً، أو فعّل الديون الآن.'
              : 'لا يمكن ترك متبقٍّ على العميل والديون مطفأة. استلم المبلغ '
                    'كاملاً، أو اطلب من المالك تفعيل الديون من الإعدادات.',
          textAlign: TextAlign.start,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          if (isOwner)
            FilledButton(
              key: const Key('oilEnableDebtsButton'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('تفعيل الديون ومتابعة'),
            ),
        ],
      ),
    );
    if (enable != true || !mounted) return false;
    await features.save(features.data.copyWith(enableDebts: true));
    return mounted;
  }

  /// يعرض النقص ويطلب رمز المالك للمتابعة برصيد سالب.
  /// العميل عليه دين متأخر: الدين الجديد يُمنع إلا برمز المالك.
  Future<bool> _approveDebtForOverdue(OverdueCustomerDebt overdue) async {
    final wantsOverride = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(overdue.title),
        content: Text(overdue.message, textAlign: TextAlign.start),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('دين جديد برمز المالك'),
          ),
        ],
      ),
    );
    if (wantsOverride != true || !mounted) return false;
    return confirmOwnerPinForSensitiveAction(
      context,
      title: overdue.cashOnly ? 'دين لعميل «نقداً فقط»' : 'دين جديد لعميل متأخر',
      message: overdue.cashOnly
          ? 'السماح بدين جديد لعميل مضبوط «نقداً فقط».'
          : 'السماح بدين جديد رغم دين متأخر عمره ${overdue.daysOld} يوماً.',
      confirmLabel: 'سماح وبيع',
    );
  }

  /// ق-6: نقص الرصيد لا يمنع البيع ولا يطلب رمز المالك. الموظف يرى التنبيه
  /// ويتابع، والرصيد يصير سالباً، ويُسجَّل الحدث باسمه ويصل إشعار للمالك.
  Future<bool> _approveStockShortages(List<OilStockShortage> shortages) async {
    final cs = Theme.of(context).colorScheme;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('الرصيد غير كافٍ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final s in shortages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(s.text, textAlign: TextAlign.start),
                ),
              const SizedBox(height: 4),
              Text(
                'البيع يتم والرصيد يصير سالباً، ويُسجَّل باسمك ويصل تنبيه '
                'للمالك. صحّح الرصيد لاحقاً بـ«استلام بضاعة» أو «تحويل» من المخزن.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                textAlign: TextAlign.start,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('متابعة البيع'),
          ),
        ],
      ),
    );
    return go == true && mounted;
  }

  Future<void> _recordStockOverride(int orderId) async {
    final shortages = _stockOverrideShortages;
    if (!_stockOverrideApproved || shortages.isEmpty) return;
    final auth = context.read<AuthProvider>();
    try {
      await BusinessAuditLogService.instance.record(
        eventType: 'oil_change_stock_override',
        entityType: 'service_order',
        entityId: '$orderId',
        newValueJson: jsonEncode({
          'approvedBy': 'warning',
          'shortages': [for (final s in shortages) s.toJson()],
        }),
        userId: auth.userId,
        username: auth.displayName,
      );
    } catch (_) {}
  }

  Future<bool> _validateHydraulicStockBeforeSave({
    required OilChangeHydraulicCardSlot slot,
    required String label,
    required bool customer,
    required double liters,
    required int? productId,
    required int? warehouseId,
  }) async {
    if (!_hydraulicStockEnabledFor(slot)) {
      return true;
    }
    if (customer || liters <= 1e-9) return true;
    if (productId == null || productId <= 0) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'اختر $label من المخزون والدرجة، أو فعّل «هيدروليك العميل»',
          ),
        ),
      );
      return false;
    }
    return true;
  }

  List<String> _missingOilChangeCoreFields() {
    final missing = <String>[];

    if (_customerName.text.trim().isEmpty) {
      missing.add('بيانات العميل: اسم العميل');
    }
    final phoneErr = _oilCustomerPhoneRequiredError(_customerPhone.text);
    if (phoneErr != null) {
      missing.add('بيانات العميل: رقم الهاتف');
    }

    bool req(OilCardField f) => _isFieldRequired(f);
    void need(OilCardField f, bool empty, String label) {
      if (req(f) && empty) missing.add(label);
    }

    need(OilCardField.carName, _deviceName.text.trim().isEmpty, 'بيانات السيارة: اسم السيارة');
    need(OilCardField.plate, _deviceSerial.text.trim().isEmpty, 'بيانات السيارة: رقم اللوحة');
    need(OilCardField.carModel, _carModel.text.trim().isEmpty, 'بيانات السيارة: موديل السيارة');
    need(OilCardField.engineSize, _engineSize.text.trim().isEmpty, 'بيانات السيارة: حجم المحرك');
    need(OilCardField.odometerCurrent, _odometerDigits(_odometerCurrent.text).isEmpty, 'العداد: القراءة الحالية');
    need(OilCardField.odometerNext, _odometerDigits(_odometerNext.text).isEmpty, 'العداد: القراءة اللاحقة');
    need(OilCardField.technician, _technicianName.text.trim().isEmpty, 'الفني: اسم الفني');

    if (req(OilCardField.oil)) {
      final liters = _oilLitersForPricing();
      if (_oilCustomerProvided) {
        // زيت العميل: اسمه وحجمه اختياريان ولا يعطّلان البيع.
      } else if (_usesWarehouseOilPicker) {
        if ((_oilStockProductId ?? 0) <= 0) {
          missing.add('تغيير الزيت: اختيار الزيت من المخزون');
        }
        if (liters <= 1e-9) {
          missing.add('تغيير الزيت: حجم الزيت المستعمل');
        }
      } else if (_showCatalogOilFields) {
        if ((_oilBrandDropdownValue ?? '').trim().isEmpty) {
          missing.add('تغيير الزيت: اسم الزيت');
        }
        if ((_oilViscosityDropdownValue ?? '').trim().isEmpty) {
          missing.add('تغيير الزيت: اللزوجة');
        }
        if (liters <= 1e-9) {
          missing.add('تغيير الزيت: حجم الزيت المستعمل');
        }
      } else {
        if (_oilType.text.trim().isEmpty) {
          missing.add('تغيير الزيت: نوع الزيت');
        }
        if (liters <= 1e-9) {
          missing.add('تغيير الزيت: حجم الزيت المستعمل');
        }
      }
    }

    // شرط لا يُلغى بالإعدادات: لا فاتورة بلا بند مسعَّر.
    if (_cardGrandTotalFils() <= 0) {
      missing.add('البطاقة بلا أي بند مسعَّر: أضف زيتاً أو خدمة أو منتجاً');
    }

    return missing;
  }

  /// رقم الهاتف إلزامي في بطاقة الغيار — فارغ أو غير عراقي صالح.
  String? _oilCustomerPhoneRequiredError(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return 'رقم الهاتف مطلوب';
    return CustomerValidation.iraqiMobilePhone(t);
  }

  String? _oilCustomerNameRequiredError(String? raw) {
    final t = (raw ?? '').trim();
    if (t.isEmpty) return 'اسم العميل مطلوب';
    return CustomerValidation.name(t);
  }

  Future<void> _showOilChangeCoreMissingDialog(List<String> missing) async {
    if (!mounted || missing.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بيانات البطاقة غير مكتملة'),
        content: SingleChildScrollView(
          child: Text(
            'أكمل البطاقات الأساسية التالية قبل الحفظ أو البيع:\n\n'
            '${missing.map((m) => '• $m').join('\n')}',
            textAlign: TextAlign.start,
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Future<void> _submitOilChangeOrder({
    bool openInvoice = false,
    _OilSubmitIntent intent = _OilSubmitIntent.complete,
  }) async {
    final reSuspending =
        widget.isEdit &&
        intent == _OilSubmitIntent.suspend &&
        _oilEditCompletingSuspended;
    final suspending =
        (!widget.amendInvoicedOrder) &&
        ((!widget.isEdit && intent == _OilSubmitIntent.suspend) ||
            reSuspending);
    // قبل تغيير الحالة — لإرسال واتساب عند إكمال معلّقة.
    final completingSuspendedSale =
        !widget.amendInvoicedOrder &&
        widget.isEdit &&
        _oilEditCompletingSuspended &&
        intent == _OilSubmitIntent.complete;

    if (widget.amendInvoicedOrder) {
      openInvoice = false;
    } else if (!widget.isEdit && !suspending) {
      openInvoice = true;
    }
    if (completingSuspendedSale) {
      openInvoice = true;
    }
    if (_hydratingEdit || _saving) return;

    // البند 4.3: الوردية قد تُغلق والشاشة مفتوحة. يُفحص قبل حفظ صف البطاقة،
    // فلا تتغير البطاقة دون فاتورتها.
    if (widget.amendInvoicedOrder &&
        await PaidCardLock.isLocked(
          await DatabaseHelper().database,
          _editInvoiceId,
        )) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(PaidCardLock.message)),
        );
      }
      return;
    }

    if (widget.amendInvoicedOrder && intent == _OilSubmitIntent.suspend) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يمكن تعليق بطاقة مكتملة أثناء التصحيح.'),
          ),
        );
      }
      return;
    }

    // ألغِ مزامنة لوحة متأخرة حتى لا تُفسِد القراءات عند الحفظ/التعليق.
    _plateVehicleSyncDebounce?.cancel();

    // قفل فوري قبل أي await — يمنع نقراً مزدوجاً يكرّر البطاقة/المخزون/الفاتورة.
    _saving = true;
    _stockOverrideApproved = false;
    _stockOverrideShortages = const [];
    if (mounted) {
      _rebuild(() => _error = null);
    }

    // الحالة لا تتغير إلا إن كُتبت البطاقة فعلاً؛ أي فحص فاشل يعيدها كما كانت.
    final statusBeforeSubmit = _status;
    var cardWritten = false;
    // رقم بطاقة جديدة أُنشئت في هذه المحاولة؛ إن فشل ما بعدها لا تُعاد المحاولة
    // من نفس الشاشة (كانت تنشئ بطاقة ثانية وتصرف المخزون مرتين).
    int? createdNewCardId;
    var soldInOneTxn = false;

    try {
      final conflict = ShiftActorConflictGuard.evaluate(
        sessionUserId: context.read<AuthProvider>().userId,
        activeShift: context.read<ShiftProvider>().activeShift,
      );
      if (conflict.hasConflict) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'لا يمكن حفظ البطاقة/البيع من هذه الجلسة: الوردية المفتوحة باسم ${conflict.shiftStaffName}.',
              ),
            ),
          );
        }
        return;
      }

      if (_oilCheckoutFinalized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('هذه البطاقة مُغلقة ولا يمكن تعديلها.'),
            ),
          );
        }
        return;
      }

      if (suspending) {
        final nameErr = _oilCustomerNameRequiredError(_customerName.text);
        final phoneErr = _oilCustomerPhoneRequiredError(_customerPhone.text);
        if (nameErr != null || phoneErr != null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  nameErr != null && phoneErr != null
                      ? 'أدخل اسم العميل ورقم الهاتف قبل تعليق الفاتورة.'
                      : (nameErr ?? phoneErr)!,
                ),
              ),
            );
          }
          return;
        }
        if (_isFieldRequired(OilCardField.plate) &&
            _deviceSerial.text.trim().isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('أدخل رقم اللوحة على الأقل قبل تعليق الفاتورة.'),
              ),
            );
          }
          return;
        }
      } else {
        final ok = _formKey.currentState?.validate() ?? false;
        if (!ok) return;
      }

      if (suspending) {
        _status = OilChangeOrderStatus.suspended;
        openInvoice = false;
      } else {
        final missingCore = _missingOilChangeCoreFields();
        if (missingCore.isNotEmpty) {
          if (_isFieldRequired(OilCardField.oil) && !_oilSectionHasData()) {
            // الزيت الناقص في قسم مطوي: افتحه ليراه الموظف.
            _rebuild(() => _expandedOptional.add(_OilFormOptionalSection.oil));
          }
          await _showOilChangeCoreMissingDialog(missingCore);
          return;
        }
        if (!await _confirmLowerOdometerIfNeeded()) return;
        _status = widget.amendInvoicedOrder
            ? OilChangeOrderStatus.delivered
            : OilChangeOrderStatus.completed;
      }

      final serialOut = _deviceSerial.text.trim();

      final suspendLabels = suspending
          ? _oilSuspendSaveLabels(serialOut)
          : null;
      final customerNameOut =
          suspendLabels?.customerName ?? _customerName.text.trim();
      final deviceNameOut =
          suspendLabels?.deviceName ?? _deviceName.text.trim();

      final sizeVal = _oilSizeValueForSave();
      final hydSizeVal = _hydraulicSizeValueForSaveFor(_gearHydraulic);
      final powerHydSizeVal = _hydraulicSizeValueForSaveFor(_powerHydraulic);

      final estF = _parseFils(_estimated);
      final agreedF = OilChangeAgreedTotal.agreedFilsForSave(
        agreedFils: _parseFils(_agreed),
        cardGrandFils: _cardGrandTotalFils(),
        manuallyEdited: _agreedTotalManual,
      );
      final agreedFOrNull = agreedF > 0 ? agreedF : null;
      final advRaw = _parseFils(_advance);
      final totalCap = agreedFOrNull ?? _cardGrandTotalFils();
      final advF = totalCap > 0 && advRaw > totalCap ? totalCap : advRaw;

      await _ensureCustomerRecordFromOilForm(
        customerName: customerNameOut,
        phoneRaw: _customerPhone.text.trim(),
      );
      if (!mounted) return;

      if (openInvoice) {
        final totalF = agreedFOrNull ?? _cardGrandTotalFils();
        final remainderF = totalF > 0 ? (totalF - advF).clamp(0, totalF) : 0;
        if (remainderF > 500 && (_customerId == null || _customerId! <= 0)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'لتسجيل المتبقي كدين: اختر عميلاً مسجّلاً من القائمة قبل «حفظ وبيع».',
                ),
                duration: Duration(seconds: 6),
              ),
            );
          }
          return;
        }
        // ميزة الديون مطفأة: لا متبقٍّ يُسجَّل ديناً لا صفحة لرؤيته (بند 2-17).
        if (remainderF > 500 && !suspending && !await _ensureDebtsFeatureOn()) {
          return;
        }
        // سقوف الدين تُفحص قبل أي كتابة، لا بعد حفظ البطاقة وصرف المخزون.
        if (remainderF > 500) {
          final capErr = await SaleDebtCapsValidator.validate(
            customerId: _customerId,
            customerName: customerNameOut,
            remainderFils: remainderF,
          );
          if (!mounted) return;
          if (capErr != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(capErr),
                duration: const Duration(seconds: 6),
              ),
            );
            return;
          }
        }
        // دين متأخر عن فترة التسديد: الدين الجديد برمز المالك فقط.
        if (remainderF > 500 && !suspending) {
          final overdue = await SaleDebtOverdueCheck.find(
            customerId: _customerId,
            customerName: customerNameOut,
            payingNowFils: oilOldDebtPaymentFils(
              receivedFils: advRaw,
              visitTotalFils: totalCap,
              oldDebtFils: _collectibleOldDebtFils(),
            ),
          );
          if (!mounted) return;
          if (overdue != null && !await _approveDebtForOverdue(overdue)) {
            return;
          }
        }
        // دين جديد فوق دين سابق: تأكيد بالرصيد الجديد قبل أي كتابة.
        final priorF = _collectibleOldDebtFils();
        if (remainderF > 500 && priorF > 0) {
          final ok = await _confirmNewDebtOverOld(
            priorFils: priorF,
            newFils: remainderF,
          );
          if (!mounted || !ok) return;
        }
      }

      // الزائد عن الزيارة يُسدَّد من الدين السابق داخل معاملة البيع نفسها.
      final oldDebtPayF =
          openInvoice && !suspending && !widget.amendInvoicedOrder
          ? oilOldDebtPaymentFils(
              receivedFils: advRaw,
              visitTotalFils: totalCap,
              oldDebtFils: _collectibleOldDebtFils(),
            )
          : 0;

      final etaMins = _etaTotalMinutes();
      String? promIso;
      if (_workStartedAtUtc != null && etaMins != null && etaMins > 0) {
        promIso = _workStartedAtUtc!
            .add(Duration(minutes: etaMins))
            .toIso8601String();
      }

      if (_usesWarehouseOilPicker) {
        _syncStockLitersFromStepper();
      }
      if (_usesWarehouseHydraulicPickerFor(_gearHydraulic)) {
        _syncHydraulicLitersFromStepperFor(_gearHydraulic);
      }
      if (_usesWarehouseHydraulicPickerFor(_powerHydraulic)) {
        _syncHydraulicLitersFromStepperFor(_powerHydraulic);
      }

      final oilCustomer = _oilCustomerProvided;
      final oilLiters = _oilLitersForPricing();
      final oilSellPerLiterFils = _usesCatalogOilPricing
          ? _catalogSellPerLiterFils
          : null;
      final oilPid = oilCustomer ? null : _oilStockProductId;
      final oilWh = oilCustomer ? null : _oilWarehouseId;

      final hydCustomer = _gearHydraulic.customerProvided;
      final hydLiters = _gearHydraulic.litersForPricing();
      final hydPid = hydCustomer ? null : _gearHydraulic.stockProductId;
      final hydWh = hydCustomer ? null : _gearHydraulic.warehouseId;

      final powerHydCustomer = _powerHydraulic.customerProvided;
      final powerHydLiters = _powerHydraulic.litersForPricing();
      final powerHydPid = powerHydCustomer
          ? null
          : _powerHydraulic.stockProductId;
      final powerHydWh = powerHydCustomer ? null : _powerHydraulic.warehouseId;

      if (!suspending &&
          _stockFromWarehouseEnabled &&
          !oilCustomer &&
          !_usesCatalogOilPricing &&
          oilLiters > 0 &&
          (oilPid == null || oilPid <= 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'اختر زيت المحل واللزوجة من القائمة، أو فعّل «زيت العميل»',
            ),
          ),
        );
        return;
      }
      if (!suspending) {
        for (final kind in _filterKinds) {
          if (!_filterNeedsStockPick(_filterSlotFor(kind))) continue;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'اختر ${kind.label} من المخزون، أو فعّل «من العميل»',
              ),
            ),
          );
          return;
        }
        if (!await _validateHydraulicStockBeforeSave(
          slot: _gearHydraulic,
          label: 'هيدروليك الكير',
          customer: hydCustomer,
          liters: hydLiters,
          productId: hydPid,
          warehouseId: hydWh,
        )) {
          return;
        }
        if (!await _validateHydraulicStockBeforeSave(
          slot: _powerHydraulic,
          label: 'هيدروليك الباور',
          customer: powerHydCustomer,
          liters: powerHydLiters,
          productId: powerHydPid,
          warehouseId: powerHydWh,
        )) {
          return;
        }
        final stockMoves =
            !widget.isEdit || _editInvoiceId <= 0 || widget.amendInvoicedOrder;
        if (stockMoves) {
          final shortages = await OilCardStockCheck.shortages(
            _stockNeedsForSale(
              oilCustomer: oilCustomer,
              oilPid: oilPid,
              oilWh: oilWh,
              oilLiters: oilLiters,
            ),
          );
          if (!mounted) return;
          if (shortages.isNotEmpty) {
            if (!await _approveStockShortages(shortages)) return;
            _stockOverrideApproved = true;
            _stockOverrideShortages = shortages;
          }
        }
      }

      {
        // الإيصال والرسالة يعرضان الدين السابق بعد ما سُدِّد منه الآن.
        _priorOpenDebtFilsAtCheckout = _customerOpenDebtFils - oldDebtPayF;
      }

      final amendingFastPath = widget.amendInvoicedOrder;
      final amendPhoneResend =
          amendingFastPath && _phoneChangedFromAmendBaseline();
      final postSaveWarmup = (amendingFastPath && !amendPhoneResend)
          ? Future<void>.value()
          : _warmPostSaveSettings();

      {
        final tenantCtx = TenantContextService.instance;
        if (!tenantCtx.loaded) {
          await DatabaseHelper().ensureDefaultTenantSeedIfNeeded();
          await tenantCtx.load();
        }
      }

      try {
        await postSaveWarmup;
        int? savedId;
        Map<String, dynamic>? savedOrder;

        // البيع (بطاقة جديدة أو إكمال معلّقة) في معاملة واحدة: البطاقة وصرف
        // المخزون والفاتورة تنجح معاً أو لا يُحفظ منها شيء.
        final oneTxn = openInvoice && !widget.amendInvoicedOrder && !suspending;
        soldInOneTxn = oneTxn;
        Future<({bool aborted, _OilPostSaveJob? job})> persist() async {
          if (widget.isEdit) {
            await OilChangeOrdersRepository.instance.updateOilChangeOrder(
              widget.editOrderId!,
              patchCustomerIdField: true,
              customerId: _customerId,
              customerNameSnapshot: customerNameOut,
              deviceName: deviceNameOut,
              deviceSerial: serialOut,
              serviceId: _serviceId,
              estimatedPriceFils: estF,
              agreedPriceFils: agreedFOrNull,
              advancePaymentFils: advF,
              status: _status,
              issueDescription: _issue.text.trim(),
              // إكمال معلّقة → يوم السجل = يوم الحفظ والبيع (وليس يوم التعليق).
              stampCreatedAtAsNow: completingSuspendedSale,
              patchEtaFields: true,
              expectedDurationMinutes: etaMins,
              promisedDeliveryAt: promIso,
              carModel: _carModelForSave,
              engineSize: _engineSize.text.trim(),
              odometerCurrent: _odometerCurrentForSave,
              odometerNext: _odometerNextForSave,
              oilType: _oilType.text.trim(),
              oilViscosity: _selectedViscosity,
              oilSize: sizeVal,
              filterType: _filterTypeSummaryForSave(),
              oilFiltersJson: _oilFiltersJsonForSave(),
              engineFilterName:
                  _filterSlotFor(OilChangeFilterKind.engine).hasSelection
                  ? _filterSlotFor(OilChangeFilterKind.engine).name
                  : null,
              engineFilterPriceFils:
                  _filterSlotFor(OilChangeFilterKind.engine).hasSelection
                  ? _filterSlotFor(OilChangeFilterKind.engine).priceFils
                  : null,
              airFilterName:
                  _filterSlotFor(OilChangeFilterKind.air).hasSelection
                  ? _filterSlotFor(OilChangeFilterKind.air).name
                  : null,
              airFilterPriceFils:
                  _filterSlotFor(OilChangeFilterKind.air).hasSelection
                  ? _filterSlotFor(OilChangeFilterKind.air).priceFils
                  : null,
              gearFilterName:
                  _filterSlotFor(OilChangeFilterKind.gear).hasSelection
                  ? _filterSlotFor(OilChangeFilterKind.gear).name
                  : null,
              gearFilterPriceFils:
                  _filterSlotFor(OilChangeFilterKind.gear).hasSelection
                  ? _filterSlotFor(OilChangeFilterKind.gear).priceFils
                  : null,
              requestedServices: _oilServiceNamesForSave(),
              customerPhone: _customerPhone.text.trim(),
              technicianName: _technicianName.text.trim(),
              patchOilStockFields: true,
              oilProductId: oilPid,
              oilLitersUsed: oilLiters > 0 ? oilLiters : null,
              oilCustomerProvided: oilCustomer,
              oilWarehouseId: oilWh,
              oilSellPerLiterFils: oilSellPerLiterFils,
              extraColumns: _cardPricingColumnsForSave(),
              hydraulicType: _gearHydraulic.type.text.trim(),
              hydraulicGrade: _gearHydraulic.selectedGrade,
              hydraulicSize: hydSizeVal,
              patchHydraulicStockFields: true,
              hydraulicProductId: hydPid,
              hydraulicLitersUsed: hydLiters > 0 ? hydLiters : null,
              hydraulicCustomerProvided: hydCustomer,
              hydraulicWarehouseId: hydWh,
              powerHydraulicType: _powerHydraulic.type.text.trim(),
              powerHydraulicGrade: _powerHydraulic.selectedGrade,
              powerHydraulicSize: powerHydSizeVal,
              patchPowerHydraulicStockFields: true,
              powerHydraulicProductId: powerHydPid,
              powerHydraulicLitersUsed: powerHydLiters > 0
                  ? powerHydLiters
                  : null,
              powerHydraulicCustomerProvided: powerHydCustomer,
              powerHydraulicWarehouseId: powerHydWh,
            );
            cardWritten = true;
            savedId = widget.editOrderId;
            final editId = widget.editOrderId!;
            if (_editInvoiceId <= 0 || widget.amendInvoicedOrder) {
              try {
                if (_stockFromWarehouseEnabled) {
                  final newOilVoucherId = await OilChangeStockService.instance
                      .syncStockOnEdit(
                        orderId: editId,
                        existingVoucherId: _editStockVoucherId,
                        previousLiters: _editOilLitersUsed,
                        previousProductId: _editOilProductId,
                        previousWarehouseId: _editOilWarehouseId,
                        previousCustomerProvided: _editOilCustomerProvided,
                        newCustomerProvided: oilCustomer,
                        newProductId: oilPid,
                        newWarehouseId: oilWh,
                        newLiters: oilLiters,
                        allowNegative: _stockOverrideApproved,
                      );
                  await OilChangeOrdersRepository.instance.updateOilChangeOrder(
                    editId,
                    patchOilStockFields: true,
                    stockVoucherId: newOilVoucherId ?? 0,
                    oilProductId: oilPid,
                    oilLitersUsed: oilLiters > 0 ? oilLiters : null,
                    oilCustomerProvided: oilCustomer,
                    oilWarehouseId: oilWh,
                  );
                }
                if (_gearHydraulicStockEnabled) {
                  final newGearVoucherId = await OilChangeStockService.instance
                      .syncStockOnEdit(
                        orderId: editId,
                        existingVoucherId: _gearHydraulic.editStockVoucherId,
                        previousLiters: _gearHydraulic.editLitersUsed,
                        previousProductId: _gearHydraulic.editProductId,
                        previousWarehouseId: _gearHydraulic.editWarehouseId,
                        previousCustomerProvided:
                            _gearHydraulic.editCustomerProvided,
                        newCustomerProvided: hydCustomer,
                        newProductId: hydPid,
                        newWarehouseId: hydWh,
                        newLiters: hydLiters,
                        allowNegative: _stockOverrideApproved,
                      );
                  await OilChangeOrdersRepository.instance.updateOilChangeOrder(
                    editId,
                    patchHydraulicStockFields: true,
                    hydraulicStockVoucherId: newGearVoucherId ?? 0,
                    hydraulicProductId: hydPid,
                    hydraulicLitersUsed: hydLiters > 0 ? hydLiters : null,
                    hydraulicCustomerProvided: hydCustomer,
                    hydraulicWarehouseId: hydWh,
                  );
                }
                await _syncFilterStockAfterSave(editId);
                if (_powerHydraulicStockEnabled) {
                  final newPowerVoucherId = await OilChangeStockService.instance
                      .syncStockOnEdit(
                        orderId: editId,
                        existingVoucherId: _powerHydraulic.editStockVoucherId,
                        previousLiters: _powerHydraulic.editLitersUsed,
                        previousProductId: _powerHydraulic.editProductId,
                        previousWarehouseId: _powerHydraulic.editWarehouseId,
                        previousCustomerProvided:
                            _powerHydraulic.editCustomerProvided,
                        newCustomerProvided: powerHydCustomer,
                        newProductId: powerHydPid,
                        newWarehouseId: powerHydWh,
                        newLiters: powerHydLiters,
                        allowNegative: _stockOverrideApproved,
                      );
                  await OilChangeOrdersRepository.instance.updateOilChangeOrder(
                    editId,
                    patchPowerHydraulicStockFields: true,
                    powerHydraulicStockVoucherId: newPowerVoucherId ?? 0,
                    powerHydraulicProductId: powerHydPid,
                    powerHydraulicLitersUsed: powerHydLiters > 0
                        ? powerHydLiters
                        : null,
                    powerHydraulicCustomerProvided: powerHydCustomer,
                    powerHydraulicWarehouseId: powerHydWh,
                  );
                }
              } catch (e) {
                // في المعاملة الواحدة يُلغى تعديل البطاقة مع الصرف.
                if (oneTxn) rethrow;
                if (!mounted) return (aborted: true, job: null);
                _rebuild(() => _saving = false);
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(e.toString())));
                return (aborted: true, job: null);
              }
            } else if (_editInvoiceId > 0 &&
                (oilCustomer != _editOilCustomerProvided ||
                    oilPid != _editOilProductId ||
                    oilWh != _editOilWarehouseId ||
                    (oilLiters - _editOilLitersUsed).abs() > 1e-9)) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'تم حفظ البطاقة. المخزون لم يُغيّر لأنها مرتبطة بفاتورة — '
                      'عدّل الفاتورة يدوياً إن لزم.',
                    ),
                  ),
                );
              }
            }
            savedOrder = await OilChangeOrdersRepository.instance
                .getOilChangeOrderById(widget.editOrderId!);
          } else {
            // لوحة قديمة ناقصة أكّد الموظف أنها هذه السيارة: تُكمَّل قبل الحفظ
            // فتُربط البطاقة بالسيارة نفسها لا بسيارة جديدة.
            final adoptGid = _adoptVehicleGid;
            if (adoptGid != null &&
                OilChangeLookupNormalize.normalizePlateKey(serialOut) ==
                    _adoptPlateKey) {
              await OilChangeOrdersRepository.instance
                  .adoptVehiclePlate(adoptGid, serialOut);
            }
            savedId = await OilChangeOrdersRepository.instance
                .createOilChangeOrder(
                  customerId: _customerId,
                  customerNameSnapshot: customerNameOut,
                  deviceName: deviceNameOut,
                  deviceSerial: serialOut,
                  serviceId: _serviceId,
                  estimatedPriceFils: estF,
                  agreedPriceFils: agreedFOrNull,
                  advancePaymentFils: advF,
                  status: _status,
                  issueDescription: _issue.text.trim(),
                  expectedDurationMinutes: etaMins,
                  promisedDeliveryAt: null,
                  carModel: _carModelForSave,
                  engineSize: _engineSize.text.trim(),
                  odometerCurrent: _odometerCurrentForSave,
                  odometerNext: _odometerNextForSave,
                  oilType: _oilType.text.trim(),
                  oilViscosity: _selectedViscosity,
                  oilSize: sizeVal,
                  filterType: _filterTypeSummaryForSave(),
                  oilFiltersJson: _oilFiltersJsonForSave(),
                  engineFilterName:
                      _filterSlotFor(OilChangeFilterKind.engine).hasSelection
                      ? _filterSlotFor(OilChangeFilterKind.engine).name
                      : null,
                  engineFilterPriceFils:
                      _filterSlotFor(OilChangeFilterKind.engine).hasSelection
                      ? _filterSlotFor(OilChangeFilterKind.engine).priceFils
                      : null,
                  airFilterName:
                      _filterSlotFor(OilChangeFilterKind.air).hasSelection
                      ? _filterSlotFor(OilChangeFilterKind.air).name
                      : null,
                  airFilterPriceFils:
                      _filterSlotFor(OilChangeFilterKind.air).hasSelection
                      ? _filterSlotFor(OilChangeFilterKind.air).priceFils
                      : null,
                  gearFilterName:
                      _filterSlotFor(OilChangeFilterKind.gear).hasSelection
                      ? _filterSlotFor(OilChangeFilterKind.gear).name
                      : null,
                  gearFilterPriceFils:
                      _filterSlotFor(OilChangeFilterKind.gear).hasSelection
                      ? _filterSlotFor(OilChangeFilterKind.gear).priceFils
                      : null,
                  requestedServices: _oilServiceNamesForSave(),
                  customerPhone: _customerPhone.text.trim(),
                  technicianName: _technicianName.text.trim(),
                  oilProductId: oilPid,
                  oilLitersUsed: oilLiters > 0 ? oilLiters : null,
                  oilCustomerProvided: oilCustomer,
                  oilWarehouseId: oilWh,
                  oilSellPerLiterFils: oilSellPerLiterFils,
                  extraColumns: _cardPricingColumnsForSave(),
                  hydraulicType: _gearHydraulic.type.text.trim(),
                  hydraulicGrade: _gearHydraulic.selectedGrade,
                  hydraulicSize: hydSizeVal,
                  hydraulicProductId: hydPid,
                  hydraulicLitersUsed: hydLiters > 0 ? hydLiters : null,
                  hydraulicCustomerProvided: hydCustomer,
                  hydraulicWarehouseId: hydWh,
                  powerHydraulicType: _powerHydraulic.type.text.trim(),
                  powerHydraulicGrade: _powerHydraulic.selectedGrade,
                  powerHydraulicSize: powerHydSizeVal,
                  powerHydraulicProductId: powerHydPid,
                  powerHydraulicLitersUsed: powerHydLiters > 0
                      ? powerHydLiters
                      : null,
                  powerHydraulicCustomerProvided: powerHydCustomer,
                  powerHydraulicWarehouseId: powerHydWh,
                );
            cardWritten = true;
            createdNewCardId = savedId;
            _draftDone = true;
            unawaited(OilCardDraftStore.instance.clear());
            if (!widget.isEdit && !suspending) {
              await _issueNewCardStockInParallel(
                savedId: savedId!,
                oilCustomer: oilCustomer,
                oilPid: oilPid,
                oilWh: oilWh,
                oilLiters: oilLiters,
                hydCustomer: hydCustomer,
                hydPid: hydPid,
                hydWh: hydWh,
                hydLiters: hydLiters,
                powerHydCustomer: powerHydCustomer,
                powerHydPid: powerHydPid,
                powerHydWh: powerHydWh,
                powerHydLiters: powerHydLiters,
              );
              await _syncFilterStockAfterSave(savedId!);
            }
          }
          if (savedId != null) {
            await _recordStockOverride(savedId!);
            // في التعديل تُحفظ القائمة دائماً حتى لو فرغت: إعادة تعليق بعد حذف كل
            // المنتجات يجب أن تمسحها فعلاً.
            if (!suspending || widget.isEdit || _oilProductLines.isNotEmpty) {
              await _persistOilProductLines(savedId!);
            }
            if (widget.amendInvoicedOrder) {
              // لا إعادة قراءة من DB — لقطة النموذج كافية لمسار التصحيح المحلي.
              savedOrder = _orderSnapshotFromForm();
              savedOrder!['id'] = savedId;
              if (_editInvoiceId > 0) {
                savedOrder!['invoiceId'] = _editInvoiceId;
              }
            } else {
              savedOrder = await OilChangeOrdersRepository.instance
                  .getOilChangeOrderById(savedId!);
            }
          }
          if (!mounted) return (aborted: true, job: null);

          final job = await _buildOilPostSaveJob(
            savedOrder: savedOrder,
            orderId: savedId,
            openInvoice: openInvoice,
            // واتساب فقط عند الحفظ/البيع — لا عند التعليق ولا إعادة التعليق ولا الإسقاط.
            wasSuspendedSave: false,
            completingSuspendedSale: completingSuspendedSale && openInvoice,
          );
          if (oneTxn && oldDebtPayF > 0) {
            // فشل التسديد يلغي البيع كله مع البطاقة.
            await _collectOldDebtFromCard(orderId: savedId!, fils: oldDebtPayF);
          }
          return (aborted: false, job: job);
        }

        final persisted = oneTxn
            ? await DatabaseHelper().runInOneTransaction(persist)
            : await persist();
        if (persisted.aborted) return;
        final postSaveJob = persisted.job;
        if (!mounted) return;

        if (suspending) {
          _rebuild(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.isEdit
                    ? 'تم إعادة تعليق البطاقة'
                    : 'تم تعليق الفاتورة — يمكنك استكمالها لاحقاً',
              ),
            ),
          );
          // لا جدول واتساب عند التعليق — النقل للمعلّقة فقط.
          if (widget.isEdit) {
            _leaveGateAllowPop = true;
            Navigator.pop(context, true);
            return;
          }
          unawaited(
            Navigator.of(context).pushReplacement(
              contentMaterialRoute(
                routeId: AppContentRoutes.oilChangeCreate,
                breadcrumbTitle: 'بطاقة غيار زيت جديدة',
                builder: (_) => const OilChangeFormScreen(),
              ),
            ),
          );
          return;
        }

        _rebuild(() => _saving = false);

        final soldOk =
            postSaveJob != null &&
            postSaveJob.checkoutError == null &&
            (postSaveJob.invoiceId ?? 0) > 0;
        final amendOk =
            widget.amendInvoicedOrder &&
            postSaveJob != null &&
            postSaveJob.checkoutError == null &&
            (postSaveJob.invoiceId ?? 0) > 0;

        if (widget.amendInvoicedOrder &&
            postSaveJob != null &&
            (postSaveJob.checkoutError ?? '').trim().isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(postSaveJob.checkoutError!),
              duration: const Duration(seconds: 7),
            ),
          );
          return;
        }

        AppLogger.info(
          'oil_change_save',
          'saved id=$savedId invoice=${postSaveJob?.invoiceId} '
              'openInvoice=$openInvoice amend=${widget.amendInvoicedOrder} '
              'phoneWa=${postSaveJob?.sendWhatsappForPhoneChange} '
              'err=${postSaveJob?.checkoutError}',
        );

        // تصحيح مفوتر: أغلق فوراً بدون أنيميشن ~2ث — العمل محلي.
        // واتساب (إن تغيّر الرقم) يُجدول بعد الإغلاق عبر نفس مسار post-save.
        if (amendOk) {
          _leaveGateAllowPop = true;
          Navigator.pop(context, true);
          _scheduleOilPostSaveJob(postSaveJob);
          return;
        }

        // البيع فشل بعد حفظ البطاقة: رسالة واضحة تبقى حتى يقرأها، لا نجاح ثم
        // تنبيه عابر. الإكمال من السجل (مسار التعديل) حتى لا تتكرر البطاقة.
        final checkoutFailed =
            openInvoice &&
            postSaveJob != null &&
            (postSaveJob.checkoutError ?? '').trim().isNotEmpty;
        if (checkoutFailed) {
          await _showCardSavedButNotSoldDialog(postSaveJob.checkoutError!);
          if (!mounted) return;
          _leaveGateAllowPop = true;
          Navigator.pop(context, true);
          _scheduleOilPostSaveJob(postSaveJob, checkoutErrorShown: true);
          return;
        }

        // البطاقة محفوظة فعلاً حتى لو تعذّر البيع؛ تفصيل البيع يصل في تنبيه لاحق.
        if (savedId != null && savedId! > 0) {
          await showOilChangeSaveSuccessOverlay(
            context,
            message: soldOk ? 'تم الحفظ والبيع بنجاح' : 'تم حفظ البطاقة بنجاح',
          );
          if (!mounted) return;
        }

        _leaveGateAllowPop = true;
        Navigator.pop(context, true);
        if (postSaveJob != null) {
          _scheduleOilPostSaveJob(postSaveJob);
        }
      } catch (e) {
        if (soldInOneTxn) {
          // المعاملة أُلغيت كلها: لا بطاقة ولا صرف ولا فاتورة. تبقى الشاشة
          // بمحتواها ليصحّح الموظف السبب ويعيد المحاولة.
          cardWritten = false;
          createdNewCardId = null;
          _draftDone = false;
          if (!mounted) return;
          _rebuild(() => _saving = false);
          if (!widget.isEdit) unawaited(_autosaveDraft());
          await _showSaleNotSavedDialog(_friendlyError(e));
          return;
        }
        if (!mounted) return;
        if ((createdNewCardId ?? 0) > 0) {
          _rebuild(() => _saving = false);
          await _showCardSavedButNotSoldDialog(_friendlyError(e));
          if (!mounted) return;
          _leaveGateAllowPop = true;
          Navigator.pop(context, true);
          return;
        }
        _rebuild(() {
          _error = e;
          _errorText = _friendlyError(e);
          _saving = false;
        });
      }
    } finally {
      if (!cardWritten) _status = statusBeforeSubmit;
      // أي خروج مبكر (تحقق فاشل) يحرّر القفل؛ مسارات النجاح تضبط _saving=false مسبقاً.
      if (_saving) {
        _saving = false;
        if (mounted) _rebuild(() {});
      }
    }
  }

  Future<void> _submit({
    bool openInvoice = false,
    _OilSubmitIntent intent = _OilSubmitIntent.complete,
  }) async {
    await _submitOilChangeOrder(openInvoice: openInvoice, intent: intent);
  }

  /// القراءة أقل من آخر قراءة للسيارة: سؤال قبل الحفظ. «تصحيح القراءة» يعيد
  /// الموظف إلى الحقل؛ «الحفظ كما هي» لعداد تغيّر أو صُفّر.
  Future<bool> _confirmLowerOdometerIfNeeded() async {
    if (!_computeOdometerLower()) return true;
    final prev = IraqiCurrencyFormat.formatInt(_previousOdometerKm!);
    final cur = IraqiCurrencyFormat.formatInt(_currentOdometerKm!);
    final unit = OilOdometerUnit.label(_odometerUnit);
    final keep = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('القراءة أقل من السابقة'),
        content: Text(
          'القراءة الحالية $cur $unit أقل من قراءة الزيارة السابقة $prev $unit. '
          'غالباً خطأ في الكتابة. إن تغيّر العداد أو صُفّر فاحفظ كما هي.',
        ),
        actions: [
          TextButton(
            key: const Key('odoLowerKeep'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('الحفظ كما هي'),
          ),
          FilledButton(
            key: const Key('odoLowerFix'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تصحيح القراءة'),
          ),
        ],
      ),
    );
    return keep == true;
  }
}
