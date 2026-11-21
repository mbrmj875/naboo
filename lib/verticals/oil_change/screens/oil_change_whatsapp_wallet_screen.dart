import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../navigation/content_navigation.dart';
import '../../../theme/design_tokens.dart';
import '../services/wa_message_pricing.dart';
import '../services/wa_message_wallet_service.dart';
import '../widgets/oil_change_form_theme.dart';
import 'oil_change_whatsapp_messages_screen.dart';

/// شاشة محفظة واتساب — رصيد، عدّاد، شهري/سنوي، سجل.
/// حركات خفيفة فقط (بدون نبض مستمر) لتفادي تهنيگ وdebugNeedsLayout.
class OilChangeWhatsappWalletScreen extends StatefulWidget {
  const OilChangeWhatsappWalletScreen({super.key});

  static Future<void> open(BuildContext context) {
    return Navigator.of(context).push<void>(
      FastContentPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => const OilChangeWhatsappWalletScreen(),
      ),
    );
  }

  @override
  State<OilChangeWhatsappWalletScreen> createState() =>
      _OilChangeWhatsappWalletScreenState();
}

class _OilChangeWhatsappWalletScreenState
    extends State<OilChangeWhatsappWalletScreen> {
  WaWalletSnapshot? _snap;
  Object? _error;
  bool _loading = true;
  bool _submitting = false;

  int _qty = WaMessagePricing.defaultMinQty;
  WaBillingCycle _cycle = WaBillingCycle.monthly;

  final _dateFmt = DateFormat('d MMMM y', 'ar_SA');

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await WaMessageWalletService.instance.load();
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _qty = WaMessagePricing.clampQty(
          _qty,
          minQty: snap.minQty,
          stepQty: snap.stepQty,
          maxQty: snap.maxQty,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _bumpQty(int dir) {
    final snap = _snap;
    if (snap == null) return;
    final next = WaMessagePricing.clampQty(
      _qty + (dir * snap.stepQty),
      minQty: snap.minQty,
      stepQty: snap.stepQty,
      maxQty: snap.maxQty,
    );
    if (next == _qty) return;
    HapticFeedback.selectionClick();
    setState(() => _qty = next);
  }

  Future<void> _submitOrder() async {
    final snap = _snap;
    if (snap == null || snap.schemaMissing || _submitting) return;
    setState(() => _submitting = true);
    try {
      final order = await WaMessageWalletService.instance.createOrder(
        qty: _qty,
        cycle: _cycle,
      );
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      final cycleAr = _cycle == WaBillingCycle.annual ? 'سنوي' : 'شهري';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            order == null
                ? 'تعذّر إنشاء الطلب'
                : 'تم إرسال طلب $_qty رسالة ($cycleAr) '
                    'بمبلغ ${WaMessagePricing.formatIqd(order.amountIqd)} د.ع — '
                    'بانتظار تأكيد المنصة',
          ),
        ),
      );
      await _reload();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّر إرسال طلب الاشتراك')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: OilChangeFormTheme.wrap(context, base),
      child: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;
          return Scaffold(
            backgroundColor: cs.surface,
            appBar: OilChangeFormTheme.appBar(
              context: context,
              title: 'محفظة WhatsApp',
              actions: [
                IconButton(
                  tooltip: 'تحديث',
                  onPressed: _loading ? null : () => unawaited(_reload()),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            body: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _ErrorBody(onRetry: () => unawaited(_reload()))
                    : _buildBody(context),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final snap = _snap!;
    if (snap.schemaMissing) {
      return _SchemaMissingBody(onRetry: () => unawaited(_reload()));
    }

    final monthly = WaMessagePricing.monthlyIqd(
      _qty,
      unitPriceIqdX100: snap.unitPriceIqdX100,
    );
    final yearlyPay = WaMessagePricing.yearlyPayIqd(
      _qty,
      unitPriceIqdX100: snap.unitPriceIqdX100,
      annualFreeMonths: snap.annualFreeMonths,
    );
    final yearlyFull = WaMessagePricing.yearlyFullIqd(
      _qty,
      unitPriceIqdX100: snap.unitPriceIqdX100,
    );
    final savings = WaMessagePricing.yearlySavingsIqd(
      _qty,
      unitPriceIqdX100: snap.unitPriceIqdX100,
      annualFreeMonths: snap.annualFreeMonths,
    );
    final price = _cycle == WaBillingCycle.annual ? yearlyPay : monthly;
    final equivMonth = yearlyPay ~/ 12;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 36),
      children: [
        _BalanceHero(
          balance: snap.balance,
          nearestExpiry: snap.nearestExpiry,
          frozen: snap.frozen,
          sendBlocked: snap.sendBlocked,
          dateFmt: _dateFmt,
        ),
        if (snap.activeSubscriptionQty != null) ...[
          const SizedBox(height: 12),
          _SubscriptionChip(
            qty: snap.activeSubscriptionQty!,
            months: snap.monthsCredited ?? 0,
            endsAt: snap.subscriptionEndsAt,
            dateFmt: _dateFmt,
          ),
        ],
        if (snap.pendingOrders.isNotEmpty) ...[
          const SizedBox(height: 12),
          _PendingBanner(order: snap.pendingOrders.first),
        ],
        const SizedBox(height: 22),
        const _SectionLabel(text: 'اختر عدد الرسائل'),
        const SizedBox(height: 10),
        _QtyStepper(
          qty: _qty,
          onMinus: () => _bumpQty(-1),
          onPlus: () => _bumpQty(1),
          canMinus: _qty > snap.minQty,
          canPlus: _qty < snap.maxQty,
        ),
        const SizedBox(height: 16),
        _BillingToggle(
          cycle: _cycle,
          annualFreeMonths: snap.annualFreeMonths,
          onChanged: (c) {
            HapticFeedback.selectionClick();
            setState(() => _cycle = c);
          },
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _PriceCard(
            key: ValueKey('${_cycle.name}_$_qty'),
            cycle: _cycle,
            qty: _qty,
            price: price,
            yearlyFull: yearlyFull,
            savings: savings,
            monthly: monthly,
            equivMonth: equivMonth,
            annualFreeMonths: snap.annualFreeMonths,
          ),
        ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _submitting ? null : () => unawaited(_submitOrder()),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: AppColors.primary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : Text(
                  _cycle == WaBillingCycle.annual
                      ? 'اطلب الاشتراك السنوي'
                      : 'اطلب الاشتراك الشهري',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
        ),
        const SizedBox(height: 8),
        Text(
          'يصل الطلب للمنصة للتأكيد بعد الدفع — لا يُشحن الرصيد تلقائياً قبل الموافقة.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            height: 1.4,
            color: OilChangeFormTheme.secondaryText(context),
          ),
        ),
        const SizedBox(height: 28),
        const _SectionLabel(text: 'سجل الاستهلاك'),
        const SizedBox(height: 10),
        if (snap.ledger.isEmpty)
          const _EmptyLedger()
        else
          ...snap.ledger.take(20).map((e) => _LedgerTile(entry: e)),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () =>
              unawaited(OilChangeWhatsappMessagesScreen.open(context)),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
          label: const Text('سجل الرسائل المرسلة'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
        ),
      ],
    );
  }
}

class _BalanceHero extends StatelessWidget {
  const _BalanceHero({
    required this.balance,
    required this.nearestExpiry,
    required this.frozen,
    required this.sendBlocked,
    required this.dateFmt,
  });

  final int balance;
  final DateTime? nearestExpiry;
  final bool frozen;
  final bool sendBlocked;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    final low = balance > 0 && balance <= 20;
    final empty = balance <= 0;
    final accent = sendBlocked || frozen
        ? Theme.of(context).colorScheme.error
        : empty
            ? const Color(0xFFEA580C)
            : low
                ? OilChangeFormTheme.gold
                : const Color(0xFF00C853);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            accent.withValues(alpha: 0.16),
            AppColors.primary.withValues(alpha: 0.07),
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.18),
            ),
            child: Icon(
              sendBlocked || frozen
                  ? Icons.lock_outline_rounded
                  : Icons.account_balance_wallet_rounded,
              size: 36,
              color: accent,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'الرصيد المتبقي',
            style: TextStyle(
              color: OilChangeFormTheme.secondaryText(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$balance',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: OilChangeFormTheme.emphasisText(context),
                  height: 1.05,
                ),
          ),
          Text(
            'رسالة',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: OilChangeFormTheme.accentText(context),
            ),
          ),
          if (nearestExpiry != null) ...[
            const SizedBox(height: 10),
            Text(
              'أقرب انتهاء: ${dateFmt.format(nearestExpiry!)}',
              style: TextStyle(
                fontSize: 12.5,
                color: OilChangeFormTheme.secondaryText(context),
              ),
            ),
          ],
          if (frozen || sendBlocked) ...[
            const SizedBox(height: 10),
            Text(
              sendBlocked
                  ? 'تم إيقاف الإرسال من المنصة'
                  : 'المحفظة مجمّدة — تواصل مع الدعم',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.onMinus,
    required this.onPlus,
    required this.canMinus,
    required this.canPlus,
  });

  final int qty;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final bool canMinus;
  final bool canPlus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border.all(
          color: OilChangeFormTheme.gold.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          _RoundIconBtn(
            icon: Icons.remove_rounded,
            onTap: canMinus ? onMinus : null,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Column(
                key: ValueKey(qty),
                children: [
                  Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style:
                        Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: OilChangeFormTheme.emphasisText(context),
                            ),
                  ),
                  Text(
                    'رسالة / شهر',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: OilChangeFormTheme.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _RoundIconBtn(
            icon: Icons.add_rounded,
            onTap: canPlus ? onPlus : null,
            filled: true,
          ),
        ],
      ),
    );
  }
}

class _RoundIconBtn extends StatefulWidget {
  const _RoundIconBtn({
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  State<_RoundIconBtn> createState() => _RoundIconBtnState();
}

class _RoundIconBtnState extends State<_RoundIconBtn> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final bg = widget.filled
        ? AppColors.primary.withValues(alpha: enabled ? 1 : 0.35)
        : OilChangeFormTheme.gold.withValues(alpha: enabled ? 0.16 : 0.06);
    final fg = widget.filled
        ? Colors.white
        : OilChangeFormTheme.gold.withValues(alpha: enabled ? 1 : 0.4);

    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onTap?.call();
            }
          : null,
      onTapCancel: () => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: bg,
          ),
          child: Icon(widget.icon, color: fg, size: 26),
        ),
      ),
    );
  }
}

class _BillingToggle extends StatelessWidget {
  const _BillingToggle({
    required this.cycle,
    required this.annualFreeMonths,
    required this.onChanged,
  });

  final WaBillingCycle cycle;
  final int annualFreeMonths;
  final ValueChanged<WaBillingCycle> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.55),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToggleChip(
              label: 'شهري',
              selected: cycle == WaBillingCycle.monthly,
              onTap: () => onChanged(WaBillingCycle.monthly),
            ),
          ),
          Expanded(
            child: _ToggleChip(
              label: 'سنوي',
              badge: annualFreeMonths == 2
                  ? 'شهران مجاناً'
                  : '$annualFreeMonths أشهر مجاناً',
              selected: cycle == WaBillingCycle.annual,
              onTap: () => onChanged(WaBillingCycle.annual),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? Colors.white
                      : OilChangeFormTheme.emphasisText(context),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(height: 2),
                Text(
                  badge!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.9)
                        : const Color(0xFF00A63E),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({
    super.key,
    required this.cycle,
    required this.qty,
    required this.price,
    required this.yearlyFull,
    required this.savings,
    required this.monthly,
    required this.equivMonth,
    required this.annualFreeMonths,
  });

  final WaBillingCycle cycle;
  final int qty;
  final int price;
  final int yearlyFull;
  final int savings;
  final int monthly;
  final int equivMonth;
  final int annualFreeMonths;

  @override
  Widget build(BuildContext context) {
    final annual = cycle == WaBillingCycle.annual;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: annual
              ? const Color(0xFF00C853).withValues(alpha: 0.4)
              : OilChangeFormTheme.gold.withValues(alpha: 0.35),
        ),
        color: annual
            ? const Color(0xFF00C853).withValues(alpha: 0.08)
            : OilChangeFormTheme.gold.withValues(alpha: 0.06),
      ),
      child: Column(
        children: [
          Text(
            annual ? 'الاشتراك السنوي' : 'الاشتراك الشهري',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: OilChangeFormTheme.secondaryText(context),
            ),
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: WaMessagePricing.formatIqd(price),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: OilChangeFormTheme.emphasisText(context),
                      ),
                ),
                TextSpan(
                  text: annual ? ' د.ع / سنة' : ' د.ع / شهر',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: OilChangeFormTheme.accentText(context),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$qty رسالة كل شهر',
            style: TextStyle(
              color: OilChangeFormTheme.secondaryText(context),
            ),
          ),
          if (annual) ...[
            const SizedBox(height: 12),
            Text(
              'بدلاً من ${WaMessagePricing.formatIqd(yearlyFull)} د.ع — '
              'تدفع ${WaMessagePricing.formatIqd(price)} د.ع فقط',
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF00C853).withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'توفر ${WaMessagePricing.formatIqd(savings)} د.ع خلال السنة',
                style: const TextStyle(
                  color: Color(0xFF007A33),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'يعني حوالي ${WaMessagePricing.formatIqd(equivMonth)} د.ع '
              'في الشهر بدل ${WaMessagePricing.formatIqd(monthly)}',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: OilChangeFormTheme.secondaryText(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              annualFreeMonths == 2
                  ? 'اشترك سنوياً — شهران مجاناً (تدفع 10 أشهر فقط)'
                  : 'اشترك سنوياً — $annualFreeMonths أشهر مجاناً',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: OilChangeFormTheme.accentText(context),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: OilChangeFormTheme.emphasisText(context),
          ),
    );
  }
}

class _SubscriptionChip extends StatelessWidget {
  const _SubscriptionChip({
    required this.qty,
    required this.months,
    required this.endsAt,
    required this.dateFmt,
  });

  final int qty;
  final int months;
  final DateTime? endsAt;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Text(
        'اشتراك سنوي نشط: $qty رسالة/شهر'
        '${months > 0 ? ' · شُحن $months من 12' : ''}'
        '${endsAt != null ? ' · حتى ${dateFmt.format(endsAt!)}' : ''}',
        style: const TextStyle(height: 1.35, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.order});
  final WaPackOrder order;

  @override
  Widget build(BuildContext context) {
    final cycleAr =
        order.billingCycle == WaBillingCycle.annual ? 'سنوي' : 'شهري';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: OilChangeFormTheme.gold.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: OilChangeFormTheme.gold.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        'طلب معلّق: ${order.qty} رسالة ($cycleAr) — '
        '${WaMessagePricing.formatIqd(order.amountIqd)} د.ع بانتظار التأكيد',
        style: const TextStyle(height: 1.35, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry});
  final WaLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final positive = entry.delta > 0;
    final color = entry.delta == 0
        ? OilChangeFormTheme.secondaryText(context)
        : positive
            ? const Color(0xFF00A63E)
            : Theme.of(context).colorScheme.error;
    final fmt = DateFormat('d MMM · h:mm a', 'ar_SA');
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Material(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          dense: true,
          leading: CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.14),
            child: Icon(
              positive
                  ? Icons.south_west_rounded
                  : entry.delta == 0
                      ? Icons.remove_rounded
                      : Icons.north_east_rounded,
              color: color,
              size: 18,
            ),
          ),
          title: Text(
            entry.reasonAr,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(fmt.format(entry.createdAt)),
          trailing: Text(
            entry.delta == 0 ? '—' : '${positive ? '+' : ''}${entry.delta}',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: color,
              fontSize: 16,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 40,
            color: OilChangeFormTheme.secondaryText(context),
          ),
          const SizedBox(height: 8),
          Text(
            'لا حركة بعد — ابدأ بالاشتراك لإرسال الرسائل',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: OilChangeFormTheme.secondaryText(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 44),
            const SizedBox(height: 12),
            const Text('تعذّر تحميل المحفظة'),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('إعادة')),
          ],
        ),
      ),
    );
  }
}

class _SchemaMissingBody extends StatelessWidget {
  const _SchemaMissingBody({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.construction_rounded,
              size: 48,
              color: OilChangeFormTheme.gold,
            ),
            const SizedBox(height: 14),
            const Text(
              'محفظة الرسائل قيد التفعيل على الخادم.\nحدّث الصفحة بعد قليل.',
              textAlign: TextAlign.center,
              style: TextStyle(height: 1.45),
            ),
            const SizedBox(height: 14),
            FilledButton(onPressed: onRetry, child: const Text('تحديث')),
          ],
        ),
      ),
    );
  }
}
