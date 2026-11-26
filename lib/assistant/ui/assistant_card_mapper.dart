import '../../utils/iraqi_currency_format.dart';
import '../assistant_tool_result.dart';
import 'assistant_card_mapper_b4.dart';
import 'assistant_view_models.dart';

/// يحوّل نتيجة أداة (بعد الحارس) إلى بطاقة تُرسم (م2-4).
///
/// البطاقة تُبنى من الصفوف المحفوظة في الهاتف، لا من نص النموذج. المبالغ
/// (`*_fils`) تُنسَّق بدالة الشاشات. الحقول المالية المحذوفة بالحارس لا تظهر
/// لأنها غير موجودة أصلاً. أداة بلا بطاقة تُرجع null.
abstract final class AssistantCardMapper {
  static AssistantCardData? fromResult(AssistantToolResult r) {
    if (!r.ok && r.tool == 'memory_save' && r.error == 'memory_full') {
      return const AssistantNoticeCard(
        kind: 'memory_full',
        text: 'الذاكرة ممتلئة (40). احذف معلومة من «ما أعرفه عنك».',
      );
    }
    if (!r.ok) return null;
    final rows = r.rows;
    switch (r.tool) {
      case 'stock_search' || 'stock_low':
        if (rows.isEmpty) return null;
        return AssistantStockCard(
          title: r.tool == 'stock_low' ? 'الأصناف الناقصة' : 'المخزون',
          total: r.total,
          rows: [for (final x in rows) _stockRow(x)],
        );
      case 'product_detail':
        if (rows.isEmpty) return null;
        final x = rows.first;
        return AssistantProductCard(
          name: _s(x['name']),
          details: [
            if (x['qty'] != null) ('الموجود', '${_num(x['qty'])} ${_s(x['unit'])}'.trim()),
            if (x['sell_price_fils'] != null) ('سعر البيع', money(x['sell_price_fils'])),
            if (x['buy_price_fils'] != null) ('سعر الشراء', money(x['buy_price_fils'])),
            if (x['viscosity'] != null) ('اللزوجة', _s(x['viscosity'])),
          ],
        );
      case 'sales_summary':
        if (rows.isEmpty) return null;
        final x = rows.first;
        return AssistantFactsCard(
          kind: 'sales',
          title: 'المبيعات${_periodLabel(x['period'])}',
          route: 'app_reports',
          openLabel: 'افتح التقارير',
          facts: [
            if (x['count'] != null) ('عدد الفواتير', _num(x['count'])),
            if (x['total_fils'] != null) ('الإجمالي', money(x['total_fils'])),
            if (x['avg_fils'] != null) ('متوسط الفاتورة', money(x['avg_fils'])),
            if (x['returns'] != null) ('المرتجعات', _num(x['returns'])),
          ],
        );
      case 'cash_summary':
        if (rows.isEmpty) return null;
        final x = rows.first;
        return AssistantFactsCard(
          kind: 'cash',
          title: 'الصندوق',
          route: 'app_cash',
          openLabel: 'افتح الصندوق',
          facts: [
            if (x['balance_fils'] != null) ('الرصيد الآن', money(x['balance_fils'])),
            if (x['in_fils'] != null) ('داخل اليوم', money(x['in_fils'])),
            if (x['out_fils'] != null) ('خارج اليوم', money(x['out_fils'])),
          ],
        );
      case 'debts_summary':
        if (rows.isEmpty) return null;
        final head = rows.first;
        final perCustomer = rows.where((x) => x['customer'] != null).toList();
        return AssistantFactsCard(
          kind: 'debts',
          title: 'الديون',
          route: 'app_debts',
          openLabel: 'افتح الديون',
          total: r.total,
          facts: [
            if (head['open_total_fils'] != null) ('المفتوح', money(head['open_total_fils'])),
            if (head['debtors'] != null) ('عدد المدينين', _num(head['debtors'])),
          ],
          rows: [
            for (final x in perCustomer)
              AssistantListRow(
                _s(x['customer']),
                subtitle: x['invoices'] == null ? null : '${_num(x['invoices'])} فاتورة',
                trailing: x['amount_fils'] == null ? null : money(x['amount_fils']),
              ),
          ],
        );
      case 'staff_status':
        if (rows.isEmpty) return null;
        final x = rows.first;
        final staff = x['staff'] is List ? (x['staff'] as List).map((e) => e.toString()).join('، ') : null;
        return AssistantFactsCard(
          kind: 'staff',
          title: 'الوردية',
          facts: [
            if (x['open_shift'] != null) ('الوردية', x['open_shift'] == true ? 'مفتوحة' : 'مغلقة'),
            if (staff != null && staff.isNotEmpty) ('الشغالين', staff),
            if (x['invoices'] != null) ('فواتير الوردية', _num(x['invoices'])),
          ],
        );
      case 'oil_card_find':
        return AssistantFactsCard(
          kind: 'oil_card',
          title: 'البطاقات',
          total: r.total,
          route: 'app_oil_services_log',
          openLabel: 'افتح سجل الخدمات',
          rows: [
            for (final x in rows)
              AssistantListRow(
                'بطاقة ${_s(x['no'] ?? x['id'])}',
                subtitle: [_s(x['plate']), _s(x['customer'])].where((e) => e.isNotEmpty).join(' · '),
                flag: x['status']?.toString(),
              ),
          ],
        );
      case 'car_history':
        return AssistantFactsCard(
          kind: 'car_history',
          title: 'سجل السيارة',
          total: r.total,
          route: 'app_oil_services_log',
          openLabel: 'افتح سجل الخدمات',
          rows: [
            for (final x in rows)
              AssistantListRow(
                [
                  _s(x['oil']),
                  if (x['liters'] != null) '${_num(x['liters'])} لتر',
                ].where((e) => e.isNotEmpty).join(' · '),
                subtitle: _s(x['date']),
                trailing: x['odometer'] == null
                    ? null
                    : '${_num(x['odometer'])}${x['next_odometer'] == null ? '' : ' ← ${_num(x['next_odometer'])}'}',
              ),
          ],
        );
      case 'car_spec':
        if (rows.isEmpty) return null;
        final x = rows.first;
        return AssistantCarSpecCard(
          title: _s(x['model']),
          subtitle: 'من دليل نابو للسيارات',
          confidence: x['confidence'] == 'verified' ? AssistantConfidence.verified : AssistantConfidence.singleSource,
          specs: [
            if (x['capacity_l'] != null) ('سعة الزيت', '${_num(x['capacity_l'])} لتر مع الفلتر'),
            if (x['oil'] != null) ('اللزوجة', _s(x['oil'])),
            if (x['spec'] != null) ('المواصفة', _s(x['spec'])),
            if (x['filter'] != null) ('فلتر الزيت', _s(x['filter'])),
            if (x['interval_km'] != null) ('الفترة', '${_num(x['interval_km'])} كم (تقريبية)'),
          ],
          sources: [
            if (x['sources'] is List)
              for (final s in x['sources'] as List)
                if (s is Map) AssistantSource(_s(s['title']), _host(_s(s['url']))),
          ],
        );
      case 'memory_save':
        if (rows.isEmpty) return null;
        final id = rows.first['id'];
        return AssistantMemoryCard(id: id is num ? id.toInt() : 0, text: _s(rows.first['text']));
      case 'support_handoff':
        return const AssistantNoticeCard(kind: 'support', text: 'وصلت مشكلتك لفريق نابو، وراح يتواصلون وياك.');
      case 'prepare_oil_card' || 'prepare_car_wash' || 'prepare_customer' || 'prepare_expense' || 'prepare_product':
        if (rows.isNotEmpty && rows.first['exists'] == true) return null;
        final fields = r.extra['fields'];
        final stock = r.extra['stock'];
        final alts = stock is Map && stock['alternatives'] is List ? stock['alternatives'] as List : const [];
        return AssistantDraftCard(
          title: switch (r.tool) {
            'prepare_oil_card' => 'بطاقة غيار جديدة',
            'prepare_car_wash' => 'غسيل جديد',
            'prepare_customer' => 'زبون جديد',
            'prepare_product' => 'صنف جديد',
            _ => 'مصروف جديد',
          },
          route: r.extra['route']?.toString(),
          actionId: r.extra['action_id']?.toString(),
          fields: [
            if (fields is List)
              for (final f in fields)
                if (f is Map)
                  AssistantDraftField(
                    _s(f['label']),
                    f['missing'] == true ? 'تكمله أنت بالشاشة' : _fieldValue(f),
                    missing: f['missing'] == true,
                  ),
          ],
          warnings: [
            if (stock is Map && stock['short'] == true)
              'المتوفر من ${_s(stock['requested'])}: ${_num(stock['available'])} ${_s(stock['unit'])}'
                  '${stock['needed'] == null ? '' : '، والمطلوب ${_num(stock['needed'])}'}.'
                  '${alts.isEmpty ? ' ما عندك بديل بنفس اللزوجة يكفي.' : ''}',
          ],
          openLabel: stock is Map && stock['short'] == true ? 'أكمل بالمطلوب' : 'افتح وراجع',
          choices: [
            for (final a in alts)
              if (a is Map) _s(a['name']),
          ],
          choicesLabel: 'أو افتحها ببديل متوفر:',
        );
      case 'propose_price_change':
        final id = r.extra['action_id']?.toString();
        if (id == null) return null;
        return AssistantConfirmCard(
          title: 'تغيير سعر ${_s(r.extra['product'])}',
          actionId: id,
          changes: [('سعر البيع', money(r.extra['before_fils']), money(r.extra['after_fils']))],
          warnings: [if (r.extra['below_cost'] == true) 'السعر الجديد أقل من سعر الشراء.'],
          doneText: 'تغيّر السعر.',
        );
      case 'propose_stock_adjust':
        final id = r.extra['action_id']?.toString();
        if (id == null) return null;
        final unit = _s(r.extra['unit']);
        return AssistantConfirmCard(
          title: 'تعديل كمية ${_s(r.extra['product'])}',
          actionId: id,
          changes: [('الكمية', '${_num(r.extra['before_qty'])} $unit', '${_num(r.extra['after_qty'])} $unit')],
          facts: [('السبب', _s(r.extra['reason']))],
          doneText: 'انسجل السند وتعدّلت الكمية.',
        );
      case 'propose_product_deactivate':
        final id = r.extra['action_id']?.toString();
        if (id == null) return null;
        return AssistantConfirmCard(
          title: 'إيقاف ${_s(r.extra['product'])}',
          actionId: id,
          facts: [
            ('الكمية الحالية', '${_num(r.extra['qty'])} ${_s(r.extra['unit'])}'),
            ('بعد الإيقاف', 'يختفي من البيع والقوائم، وسجلاته تبقى'),
          ],
          warnings: [if (((r.extra['qty'] as num?) ?? 0) > 0) 'باقي منه كمية بالمخزون.'],
          confirmLabel: 'أوقفه',
          doneText: 'توقّف الصنف. ترجّعه من شاشة المخزون إذا احتجته.',
        );
      case 'propose_product_edit':
        final id = r.extra['action_id']?.toString();
        if (id == null) return null;
        final unit = _s(r.extra['unit']);
        String val(String field, Object? v) => switch (field) {
          'sell_fils' || 'min_sell_fils' || 'buy_fils' => v == null ? '—' : money(v),
          'low_stock' => '${_num(v)} $unit'.trim(),
          _ => _s(v).isEmpty ? '—' : _s(v),
        };
        const labels = {
          'name': 'الاسم',
          'barcode': 'الباركود',
          'sell_fils': 'سعر البيع',
          'min_sell_fils': 'أدنى سعر',
          'buy_fils': 'سعر الشراء',
          'low_stock': 'حد التنبيه',
        };
        final list = (r.extra['changes'] as List?) ?? const [];
        return AssistantConfirmCard(
          title: 'تعديل ${_s(r.extra['product'])}',
          actionId: id,
          changes: [
            for (final c in list)
              if (c is Map)
                (
                  labels['${c['field']}'] ?? '${c['field']}',
                  val('${c['field']}', c['field'] == 'buy_fils' ? r.extra['buy_before_fils'] : c['before']),
                  val('${c['field']}', c['after']),
                ),
          ],
          warnings: [if (r.extra['below_cost'] == true) 'سعر البيع أقل من سعر الشراء.'],
          confirmLabel: 'عدّل',
          doneText: 'تعدّل الصنف.',
        );
      case 'propose_product_reactivate':
        final id = r.extra['action_id']?.toString();
        if (id == null) return null;
        return AssistantConfirmCard(
          title: 'إرجاع ${_s(r.extra['product'])}',
          actionId: id,
          facts: [('الكمية', _num(r.extra['qty'])), ('بعد الإرجاع', 'يرجع للبيع والقوائم')],
          confirmLabel: 'رجّعه',
          doneText: 'رجع الصنف.',
        );
      case 'undo_last_action':
        final id = r.extra['action_id']?.toString();
        if (id == null) return null;
        return AssistantConfirmCard(
          title: 'تراجع',
          actionId: id,
          facts: [('العملية', _s(r.extra['undo'])), ('كيف', 'عملية عكسية تُسجَّل، ولا يُمحى شي')],
          confirmLabel: 'ارجعها',
          doneText: 'رجعت العملية.',
        );
      case 'propose_stock_transfer':
        final id = r.extra['action_id']?.toString();
        if (id == null) return null;
        final unit = _s(r.extra['unit']);
        final q = (r.extra['qty'] as num?)?.toDouble() ?? 0;
        final fb = (r.extra['from_before'] as num?)?.toDouble();
        final tb = (r.extra['to_before'] as num?)?.toDouble() ?? 0;
        return AssistantConfirmCard(
          title: 'نقل ${_s(r.extra['product'])}',
          actionId: id,
          changes: [
            if (fb != null) (_s(r.extra['from']), '${_num(fb)} $unit', '${_num(fb - q)} $unit'),
            (_s(r.extra['to']), '${_num(tb)} $unit', '${_num(tb + q)} $unit'),
          ],
          facts: [('الكمية', '${_num(q)} $unit')],
          warnings: [if (r.extra['short'] == true) 'الكمية بمخزن ${_s(r.extra['from'])} أقل من المطلوب.'],
          confirmLabel: 'انقل',
          doneText: 'انسجل سند التحويل.',
        );
      case 'propose_debt_payment':
        final id = r.extra['action_id']?.toString();
        if (id == null) return null;
        return AssistantConfirmCard(
          title: 'تسديد دين ${_s(r.extra['customer'])}',
          actionId: id,
          changes: [('الدين', money(r.extra['debt_before_fils']), money(r.extra['debt_after_fils']))],
          facts: [('المبلغ المستلم', money(r.extra['pay_fils']))],
          warnings: [if (r.extra['capped'] == true) 'المبلغ أكثر من الدين، فسجّلت الدين كله فقط.'],
          confirmLabel: 'سجّل التسديد',
          doneText: 'انسجل التسديد ودخل الصندوق، وهذا الوصل.',
        );
      case 'reminder_set':
        final id = r.extra['action_id']?.toString();
        if (id == null) return null;
        return AssistantConfirmCard(
          title: 'تذكير',
          actionId: id,
          facts: [('النص', _s(r.extra['text'])), ('الموعد', _when(r.extra['when']))],
          confirmLabel: 'ذكّرني',
          doneText: 'راح أذكّرك بوقتها.',
        );
      case 'propose_supplier_intake' || 'propose_stock_count':
        final id = r.extra['action_id']?.toString();
        if (id == null) return null;
        final count = r.tool == 'propose_stock_count';
        return AssistantDraftCard(
          title: count ? 'جرد: قائمة مراجعة' : 'فاتورة مورّد: قائمة مراجعة',
          actionId: id,
          openLabel: 'افتح المراجعة',
          fields: [
            if (r.extra['supplier'] != null) AssistantDraftField('المورّد', _s(r.extra['supplier'])),
            AssistantDraftField('الأصناف', _num(r.extra['lines'])),
            AssistantDraftField('مطابق', _num(r.extra['matched'])),
            if ((r.extra['likely'] as num? ?? 0) > 0)
              AssistantDraftField('تختاره أنت', _num(r.extra['likely']), missing: true),
            if ((r.extra['new'] as num? ?? 0) > 0)
              AssistantDraftField('غير موجود بالمخزون', _num(r.extra['new']), missing: true),
          ],
        );
    }
    return AssistantCardMapperB4.fromResult(r);
  }

  /// كل بطاقات الرد. سؤال السيارة: «المتوفر عندك» من stock_search يُدمج في
  /// بطاقة السيارة نفسها بدل بطاقة مخزون منفصلة (4.9).
  static List<AssistantCardData> fromResults(List<AssistantToolResult> results) {
    final cards = [for (final r in results) ?fromResult(r)];
    final car = cards.whereType<AssistantCarSpecCard>().firstOrNull;
    final stock = cards.whereType<AssistantStockCard>().where((c) => c.title == 'المخزون').firstOrNull;
    if (car == null || stock == null) return cards;
    final merged = AssistantCarSpecCard(
      title: car.title,
      subtitle: car.subtitle,
      specs: car.specs,
      confidence: car.confidence,
      sources: car.sources,
      available: stock.rows,
    );
    return [
      for (final c in cards)
        if (identical(c, car)) merged else if (!identical(c, stock)) c,
    ];
  }

  static AssistantStockRow _stockRow(Map<String, Object?> x) => AssistantStockRow(
    name: _s(x['name']),
    qty: x['qty'] is num ? x['qty']! as num : 0,
    unit: _s(x['unit']),
    price: x['sell_price_fils'] == null ? null : money(x['sell_price_fils']),
    low:
        x['alert'] == 'low' ||
        (x['threshold'] is num && x['qty'] is num && (x['qty']! as num) <= (x['threshold']! as num)),
  );

  /// مبلغ بالفلس بتنسيق الشاشات.
  static String money(Object? fils) {
    final f = fils is num ? fils : num.tryParse('$fils') ?? 0;
    return IraqiCurrencyFormat.formatIqd(f / 1000);
  }

  static String _fieldValue(Map f) {
    final v = f['value'];
    return switch (f['key']) {
      'sell_price' || 'amount' => money(((num.tryParse('$v') ?? 0) * 1000).round()),
      _ => _s(v),
    };
  }

  /// موعد التذكير بصيغة يقرؤها الناس: «الثلاثاء 25/11، 9:00 ص».
  static String _when(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}');
    if (d == null) return _s(iso);
    const days = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final mm = d.minute.toString().padLeft(2, '0');
    return '${days[d.weekday - 1]} ${d.day}/${d.month}، $h:$mm ${d.hour < 12 ? 'ص' : 'م'}';
  }

  static String _s(Object? v) => v == null ? '' : v.toString();

  static String _num(Object? v) {
    if (v is num) {
      final n = v == v.roundToDouble() ? v.toInt() : v;
      return n is int && n >= 10000 ? IraqiCurrencyFormat.formatInt(n) : n.toString();
    }
    return _s(v);
  }

  static String _periodLabel(Object? p) => switch (p) {
    'today' => ' · اليوم',
    'yesterday' => ' · أمس',
    'this_week' || 'week' => ' · هذا الأسبوع',
    'last_week' => ' · الأسبوع الماضي',
    'this_month' || 'month' => ' · هذا الشهر',
    'last_month' => ' · الشهر الماضي',
    _ => '',
  };

  static String _host(String url) {
    final u = Uri.tryParse(url);
    final h = u?.host ?? '';
    return h.startsWith('www.') ? h.substring(4) : (h.isEmpty ? url : h);
  }
}
