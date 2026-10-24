import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../utils/app_logger.dart';
import 'wa_message_pricing.dart';

class WaWalletSnapshot {
  const WaWalletSnapshot({
    required this.balance,
    required this.frozen,
    required this.sendBlocked,
    required this.walletExempt,
    this.nearestExpiry,
    this.activeSubscriptionQty,
    this.monthsCredited,
    this.subscriptionEndsAt,
    this.unitPriceIqdX100 = WaMessagePricing.defaultUnitPriceIqdX100,
    this.annualFreeMonths = WaMessagePricing.defaultAnnualFreeMonths,
    this.minQty = WaMessagePricing.defaultMinQty,
    this.stepQty = WaMessagePricing.defaultStepQty,
    this.maxQty = WaMessagePricing.defaultMaxQty,
    this.enforceWallet = true,
    this.schemaMissing = false,
    this.ledger = const [],
    this.pendingOrders = const [],
  });

  final int balance;
  final bool frozen;
  final bool sendBlocked;
  final bool walletExempt;
  final DateTime? nearestExpiry;
  final int? activeSubscriptionQty;
  final int? monthsCredited;
  final DateTime? subscriptionEndsAt;
  final int unitPriceIqdX100;
  final int annualFreeMonths;
  final int minQty;
  final int stepQty;
  final int maxQty;
  final bool enforceWallet;
  final bool schemaMissing;
  final List<WaLedgerEntry> ledger;
  final List<WaPackOrder> pendingOrders;

  bool get canSend =>
      !sendBlocked &&
      !frozen &&
      (walletExempt || !enforceWallet || balance > 0);
}

class WaLedgerEntry {
  const WaLedgerEntry({
    required this.id,
    required this.delta,
    required this.reason,
    required this.createdAt,
    this.sendKind,
  });

  final String id;
  final int delta;
  final String reason;
  final DateTime createdAt;
  final String? sendKind;

  String get reasonAr {
    switch (reason) {
      case 'purchase':
      case 'subscription_credit':
        return 'شحن رصيد';
      case 'send':
        return 'إرسال رسالة';
      case 'expire':
        return 'انتهاء صلاحية';
      case 'admin_adjust':
        return 'تعديل من المنصة';
      case 'refund_failed_send':
        return 'استرداد فشل إرسال';
      default:
        return reason;
    }
  }
}

class WaPackOrder {
  const WaPackOrder({
    required this.id,
    required this.qty,
    required this.billingCycle,
    required this.amountIqd,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final int qty;
  final WaBillingCycle billingCycle;
  final int amountIqd;
  final String status;
  final DateTime createdAt;
}

/// قراءة محفظة الرسائل وطلب الاشتراك من Supabase (RLS).
class WaMessageWalletService {
  WaMessageWalletService._();

  static final WaMessageWalletService instance = WaMessageWalletService._();

  SupabaseClient get _client => Supabase.instance.client;

  String? get _uid => _client.auth.currentUser?.id;

  Future<WaWalletSnapshot> load() async {
    final uid = _uid;
    if (uid == null) {
      return const WaWalletSnapshot(
        balance: 0,
        frozen: false,
        sendBlocked: false,
        walletExempt: false,
        schemaMissing: false,
      );
    }

    try {
      final settingsRow = await _client
          .from('wa_message_platform_settings')
          .select()
          .eq('id', 1)
          .maybeSingle();

      final walletRow = await _client
          .from('wa_message_wallet')
          .select()
          .eq('tenant_user_id', uid)
          .maybeSingle();

      final lots = await _client
          .from('wa_message_lots')
          .select('expires_at, messages_remaining, status')
          .eq('tenant_user_id', uid)
          .eq('status', 'active')
          .gt('messages_remaining', 0)
          .order('expires_at', ascending: true)
          .limit(1);

      final subs = await _client
          .from('wa_message_subscriptions')
          .select('qty, months_credited, ends_at, status')
          .eq('tenant_user_id', uid)
          .eq('status', 'active')
          .order('created_at', ascending: false)
          .limit(1);

      final ledgerRows = await _client
          .from('wa_message_ledger')
          .select('id, delta, reason, created_at, send_kind')
          .eq('tenant_user_id', uid)
          .order('created_at', ascending: false)
          .limit(40);

      final orderRows = await _client
          .from('wa_message_pack_orders')
          .select('id, qty, billing_cycle, amount_iqd, status, created_at')
          .eq('tenant_user_id', uid)
          .eq('status', 'pending_payment')
          .order('created_at', ascending: false)
          .limit(5);

      DateTime? nearest;
      final lotsList = lots as List<dynamic>;
      if (lotsList.isNotEmpty) {
        final raw = (lotsList.first as Map)['expires_at']?.toString();
        if (raw != null && raw.isNotEmpty) {
          nearest = DateTime.tryParse(raw)?.toLocal();
        }
      }

      Map<String, dynamic>? sub;
      final subsList = subs as List<dynamic>;
      if (subsList.isNotEmpty) {
        sub = Map<String, dynamic>.from(subsList.first as Map);
      }

      final settings = settingsRow != null
          ? Map<String, dynamic>.from(settingsRow)
          : <String, dynamic>{};
      final wallet = walletRow != null
          ? Map<String, dynamic>.from(walletRow)
          : <String, dynamic>{};

      return WaWalletSnapshot(
        balance: _asInt(wallet['balance']),
        frozen: wallet['frozen'] == true,
        sendBlocked: wallet['send_blocked'] == true,
        walletExempt: wallet['wallet_exempt'] == true,
        nearestExpiry: nearest,
        activeSubscriptionQty: sub == null ? null : _asInt(sub['qty']),
        monthsCredited: sub == null ? null : _asInt(sub['months_credited']),
        subscriptionEndsAt: sub == null
            ? null
            : DateTime.tryParse(sub['ends_at']?.toString() ?? '')?.toLocal(),
        unitPriceIqdX100: _asInt(
          settings['unit_price_iqd_x100'],
          WaMessagePricing.defaultUnitPriceIqdX100,
        ),
        annualFreeMonths: _asInt(
          settings['annual_free_months'],
          WaMessagePricing.defaultAnnualFreeMonths,
        ),
        minQty: _asInt(settings['min_qty'], WaMessagePricing.defaultMinQty),
        stepQty: _asInt(settings['step_qty'], WaMessagePricing.defaultStepQty),
        maxQty: _asInt(settings['max_qty'], WaMessagePricing.defaultMaxQty),
        enforceWallet: settings['enforce_wallet'] != false,
        ledger: _parseLedger(ledgerRows),
        pendingOrders: _parseOrders(orderRows),
      );
    } on PostgrestException catch (e) {
      if (_isMissingRelation(e)) {
        AppLogger.warn('wa_wallet', 'schema missing: ${e.message}');
        return const WaWalletSnapshot(
          balance: 0,
          frozen: false,
          sendBlocked: false,
          walletExempt: false,
          schemaMissing: true,
          enforceWallet: false,
        );
      }
      rethrow;
    } catch (e, st) {
      AppLogger.error('wa_wallet', 'load failed', e, st);
      rethrow;
    }
  }

  Future<WaPackOrder?> createOrder({
    required int qty,
    required WaBillingCycle cycle,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('not_authenticated');

    final snap = await load();
    final q = WaMessagePricing.clampQty(
      qty,
      minQty: snap.minQty,
      stepQty: snap.stepQty,
      maxQty: snap.maxQty,
    );
    final amount = WaMessagePricing.amountForCycle(
      q,
      cycle,
      unitPriceIqdX100: snap.unitPriceIqdX100,
      annualFreeMonths: snap.annualFreeMonths,
    );

    final row = await _client
        .from('wa_message_pack_orders')
        .insert({
          'tenant_user_id': uid,
          'qty': q,
          'billing_cycle':
              cycle == WaBillingCycle.annual ? 'annual' : 'monthly',
          'amount_iqd': amount,
          'status': 'pending_payment',
        })
        .select('id, qty, billing_cycle, amount_iqd, status, created_at')
        .single();

    return WaPackOrder(
      id: row['id'].toString(),
      qty: _asInt(row['qty']),
      billingCycle: row['billing_cycle'] == 'annual'
          ? WaBillingCycle.annual
          : WaBillingCycle.monthly,
      amountIqd: _asInt(row['amount_iqd']),
      status: row['status']?.toString() ?? 'pending_payment',
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }

  static int _asInt(Object? v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  static bool _isMissingRelation(PostgrestException e) {
    final m = e.message.toLowerCase();
    final c = (e.code ?? '').toLowerCase();
    return c == '42p01' ||
        m.contains('does not exist') ||
        m.contains('schema cache');
  }

  static List<WaLedgerEntry> _parseLedger(dynamic rows) {
    if (rows is! List) return const [];
    return rows.map((raw) {
      final m = raw as Map;
      return WaLedgerEntry(
        id: m['id'].toString(),
        delta: _asInt(m['delta']),
        reason: m['reason']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
        sendKind: m['send_kind']?.toString(),
      );
    }).toList();
  }

  static List<WaPackOrder> _parseOrders(dynamic rows) {
    if (rows is! List) return const [];
    return rows.map((raw) {
      final m = raw as Map;
      return WaPackOrder(
        id: m['id'].toString(),
        qty: _asInt(m['qty']),
        billingCycle: m['billing_cycle'] == 'annual'
            ? WaBillingCycle.annual
            : WaBillingCycle.monthly,
        amountIqd: _asInt(m['amount_iqd']),
        status: m['status']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal() ??
                DateTime.now(),
      );
    }).toList();
  }
}
