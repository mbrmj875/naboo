import '../../navigation/content_navigation.dart';
import '../assistant_tool_result.dart';
import 'assistant_card_mapper.dart';
import 'assistant_view_models.dart';

/// بطاقات أدوات ب4 (القراءة الإضافية والأدوات الجديدة). منفصلة عن
/// [AssistantCardMapper] حتى يبقى ملفاً قصيراً؛ تُستدعى منه.
abstract final class AssistantCardMapperB4 {
  static AssistantCardData? fromResult(AssistantToolResult r) {
    final rows = r.rows;
    final x = rows.isEmpty ? const <String, Object?>{} : rows.first;
    switch (r.tool) {
      case 'top_products':
        if (rows.isEmpty) return null;
        return AssistantFactsCard(
          kind: 'sales',
          title: 'الأكثر مبيعاً${_period(x['period'])}',
          route: 'app_reports',
          openLabel: 'افتح التقارير',
          total: r.total,
          rows: [
            for (final p in rows)
              AssistantListRow(
                _s(p['name']),
                subtitle: p['sold_qty'] == null ? null : '${_n(p['sold_qty'])} ${_s(p['unit'])}'.trim(),
                trailing: p['amount_fils'] == null ? null : _m(p['amount_fils']),
              ),
          ],
        );
      case 'ratings_summary':
        if (rows.isEmpty) return null;
        return AssistantFactsCard(
          kind: 'staff',
          title: 'تقييم الزبائن',
          rows: [
            for (final p in rows)
              AssistantListRow(
                _s(p['employee']).isEmpty ? 'المحل' : _s(p['employee']),
                subtitle: '${_n(p['count'])} تقييم',
                trailing: p['avg'] == null ? null : '${(p['avg'] as num).toStringAsFixed(1)} من 5',
              ),
          ],
        );
      case 'wa_status':
        if (rows.isEmpty) return null;
        return AssistantFactsCard(
          kind: 'generic',
          title: 'واتساب${_period(x['period'])}',
          facts: [
            if (x['connected'] != null) ('الربط', x['connected'] == true ? 'مربوط' : 'غير مربوط'),
            if (x['sent'] != null) ('المرسلة', _n(x['sent'])),
            if (x['delivered'] != null) ('الواصلة', _n(x['delivered'])),
            if (x['failed'] != null) ('الفاشلة', _n(x['failed'])),
          ],
        );
      case 'customer_find':
        if (rows.isEmpty) return null;
        if (rows.length == 1) {
          return AssistantCustomerCard(
            customerId: _int(x['id']),
            name: _s(x['name']),
            facts: [
              if (x['last_visit'] != null) ('آخر زيارة', _s(x['last_visit'])),
              if (x['open_debt_fils'] != null && _int(x['open_debt_fils']) > 0) ('عليه', _m(x['open_debt_fils'])),
            ],
          );
        }
        return AssistantFactsCard(
          kind: 'generic',
          title: 'الزبائن',
          route: AppContentRoutes.customers,
          openLabel: 'افتح الزبائن',
          rows: [
            for (final p in rows)
              AssistantListRow(
                _s(p['name']),
                subtitle: p['last_visit'] == null ? null : 'آخر زيارة ${_s(p['last_visit'])}',
                trailing: _int(p['open_debt_fils']) > 0 ? _m(p['open_debt_fils']) : null,
              ),
          ],
        );
      case 'reorder_suggest':
        if (rows.isEmpty) return null;
        return AssistantFactsCard(
          kind: 'generic',
          title: 'اقتراح الطلب',
          route: 'app_inventory',
          openLabel: 'افتح المخزون',
          total: r.total,
          rows: [
            for (final p in rows)
              AssistantListRow(
                _s(p['name']),
                subtitle: [
                  'الموجود ${_n(p['qty'])}',
                  if (p['days_left'] != null) 'يكفي ${_n(p['days_left'])} يوم',
                ].join(' · '),
                trailing: p['suggest_qty'] == null ? null : 'اطلب ${_n(p['suggest_qty'])} ${_s(p['unit'])}'.trim(),
                flag: _int(p['qty']) <= 0 ? 'out' : 'low',
              ),
          ],
        );
      case 'due_customers':
        if (rows.isEmpty) return null;
        return AssistantFactsCard(
          kind: 'oil_card',
          title: 'زبائن موعدهم قريب',
          route: AppContentRoutes.oilServicesLog,
          openLabel: 'افتح سجل الخدمات',
          total: r.total,
          rows: [
            for (final p in rows)
              AssistantListRow(
                [_s(p['customer']), _s(p['plate'])].where((e) => e.isNotEmpty).join(' · '),
                subtitle: p['last_visit'] == null ? null : 'آخر غيار ${_s(p['last_visit'])}',
                trailing: _int(p['overdue_days']) > 0
                    ? 'متأخر ${_n(p['overdue_days'])} يوم'
                    : (p['due_date'] == null ? null : 'موعده ${_s(p['due_date'])}'),
                flag: _int(p['overdue_days']) > 0 ? 'pending' : null,
              ),
          ],
        );
      case 'compare_periods':
        if (rows.length < 2) return null;
        final a = rows.firstWhere((e) => e['side'] == 'a', orElse: () => rows.first);
        final b = rows.firstWhere((e) => e['side'] == 'b', orElse: () => rows.last);
        final la = _periodName(a['period']);
        final lb = _periodName(b['period']);
        return AssistantFactsCard(
          kind: 'sales',
          title: 'مقارنة: $la و$lb',
          route: 'app_reports',
          openLabel: 'افتح التقارير',
          facts: [
            ('الفواتير', '${_n(a['count'])} ← ${_n(b['count'])}'),
            if (a['total_fils'] != null) ('الإجمالي', '${_m(a['total_fils'])} ← ${_m(b['total_fils'])}'),
            if (r.extra['total_diff_fils'] != null) ('الفرق', _signed(r.extra['total_diff_fils'])),
          ],
          rows: [
            if (r.extra['product_moves'] is List)
              for (final p in (r.extra['product_moves'] as List).whereType<Map>())
                AssistantListRow(_s(p['name']), trailing: _signed(_int(p['a_fils']) - _int(p['b_fils']))),
          ],
        );
      case 'account_audit':
        if (rows.isEmpty) return null;
        final issues = rows.where((e) => e['ok'] == false).toList();
        return AssistantFactsCard(
          kind: 'generic',
          title: issues.isEmpty ? 'دققت حساباتك: كلها سليمة' : 'تدقيق الحسابات: ${issues.length} ملاحظة',
          rows: [
            for (final p in rows)
              AssistantListRow(
                _s(p['title']),
                trailing: p['ok'] == true ? 'سليم' : _n(p['count']),
                flag: p['ok'] == true ? 'ok' : 'pending',
              ),
          ],
          route: issues.isEmpty ? null : _s(issues.first['route']),
          openLabel: issues.isEmpty ? null : 'افتح أول ملاحظة',
        );
      case 'calc':
        if (rows.isEmpty) return null;
        return AssistantFactsCard(
          kind: 'generic',
          title: 'الحساب',
          facts: [
            if (x['liter_price_fils'] != null) ('سعر اللتر', _m(x['liter_price_fils'])),
            if (x['bottles'] != null) ('عدد العلب', _n(x['bottles'])),
            if (x['leftover_l'] != null) ('يبقى', '${_n(x['leftover_l'])} لتر'),
            if (x['next_km'] != null) ('الغيار الجاي', '${_n(x['next_km'])} كم'),
            if (x['oil_fils'] != null) ('الزيت', _m(x['oil_fils'])),
            if (_int(x['filter_fils']) > 0) ('الفلتر', _m(x['filter_fils'])),
            if (_int(x['labor_fils']) > 0) ('الأجرة', _m(x['labor_fils'])),
            if (x['total_fils'] != null) ('المجموع', _m(x['total_fils'])),
          ],
        );
      case 'my_performance':
        if (rows.isEmpty) return null;
        return AssistantFactsCard(
          kind: 'staff',
          title: 'شغلك${_period(x['period'])}',
          facts: [
            ('بطاقات اليوم', _n(x['cards_today'])),
            ('بطاقات الفترة', _n(x['cards'])),
            if (x['rating_avg'] != null)
              ('تقييم زبائنك', '${(x['rating_avg'] as num).toStringAsFixed(1)} من 5 (${_n(x['rating_count'])})'),
          ],
        );
      case 'day_summary':
        if (rows.isEmpty) return null;
        return AssistantFactsCard(
          kind: 'sales',
          title: 'ملخص اليوم',
          facts: [
            if (x['sales_count'] != null) ('الفواتير', _n(x['sales_count'])),
            if (x['sales_fils'] != null) ('المبيعات', _m(x['sales_fils'])),
            if (x['cash_in_fils'] != null) ('داخل الصندوق', _m(x['cash_in_fils'])),
            if (x['cash_out_fils'] != null) ('خارج الصندوق', _m(x['cash_out_fils'])),
            if (x['expenses_fils'] != null) ('المصاريف', _m(x['expenses_fils'])),
            if (x['pending_cards'] != null) ('بطاقات معلّقة', _n(x['pending_cards'])),
            if (x['low_stock'] != null) ('أصناف ناقصة', _n(x['low_stock'])),
            if (x['open_debts_fils'] != null) ('الديون المفتوحة', _m(x['open_debts_fils'])),
          ],
        );
      case 'purchase_history':
        if (rows.isEmpty) return null;
        return AssistantFactsCard(
          kind: 'generic',
          title: r.extra['product'] == null ? 'آخر الشراء' : 'آخر شراء: ${r.extra['product']}',
          route: 'app_inventory',
          openLabel: 'افتح المخزون',
          rows: [
            for (final p in rows)
              AssistantListRow(
                _s(p['supplier']).isEmpty ? 'مورّد غير محدد' : _s(p['supplier']),
                subtitle: [
                  _s(p['date']),
                  if (p['qty'] != null) '${_n(p['qty'])} قطعة',
                ].where((e) => e.isNotEmpty).join(' · '),
                trailing: p['unit_price_fils'] == null ? null : _m(p['unit_price_fils']),
              ),
          ],
        );
      case 'naboo_account':
        if (rows.isEmpty) return null;
        return AssistantFactsCard(
          kind: 'generic',
          title: 'حسابك في نابو',
          facts: [
            if (x['plan'] != null) ('الباقة', _s(x['plan'])),
            if (x['status'] != null) ('الحالة', _status(x['status'])),
            if (x['days_left'] != null) ('باقي', '${_n(x['days_left'])} يوم'),
            if (x['wa_balance'] != null) ('رصيد رسائل واتساب', _n(x['wa_balance'])),
          ],
        );
    }
    return null;
  }

  /// أزرار الاختيار للسؤال الغامض (ق78): حتى ثمانية، وإلا لا أزرار.
  static List<String> choicesFrom(List<AssistantToolResult> results) {
    for (final r in results.reversed) {
      if (r.extra['ambiguous'] != true) continue;
      final c = r.extra['candidates'];
      if (c is! List) continue;
      final labels = [
        for (final e in c)
          if (e is Map && '${e['label'] ?? ''}'.trim().isNotEmpty) '${e['label']}'.trim(),
      ];
      final total = r.extra['candidates_total'] is num ? (r.extra['candidates_total'] as num).toInt() : labels.length;
      if (labels.isEmpty || total > 8) return const [];
      return labels.toSet().take(8).toList();
    }
    return const [];
  }

  static String _s(Object? v) => v == null ? '' : '$v';
  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static String _m(Object? fils) => AssistantCardMapper.money(fils);

  static String _n(Object? v) {
    if (v is num) return v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
    return _s(v);
  }

  static String _signed(Object? fils) {
    final f = _int(fils);
    return '${f > 0
        ? '+'
        : f < 0
        ? '−'
        : ''}${_m(f.abs())}';
  }

  static String _status(Object? s) => switch (s) {
    'active' => 'فعّال',
    'trial' => 'تجربة',
    'expired' => 'منتهي',
    'grace' => 'مهلة',
    _ => _s(s),
  };

  static String _period(Object? p) {
    final n = _periodName(p);
    return n.isEmpty ? '' : ' · $n';
  }

  static String _periodName(Object? p) => switch (p) {
    'today' => 'اليوم',
    'yesterday' => 'أمس',
    'this_week' => 'هذا الأسبوع',
    'last_week' => 'الأسبوع الماضي',
    'this_month' => 'هذا الشهر',
    'last_month' => 'الشهر الماضي',
    'custom' => 'فترة محددة',
    _ => '',
  };
}
