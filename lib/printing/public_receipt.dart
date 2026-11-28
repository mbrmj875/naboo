/// رابط الفاتورة للزبون: `https://naboo.fun/r/{token}?g={global_id}`.
///
/// - الرمز عشوائي (22 حرفاً ≈ 131 بت) يولّده الجهاز، فيُطبع حتى بلا إنترنت.
/// - تُرفع نسخة ثابتة من الإيصال عند الطباعة أو المشاركة فقط.
/// - `g` لا تقرؤه الصفحة؛ يقرؤه التطبيق عند المسح ليفتح الفاتورة بلا إنترنت
///   (المعرّف العالمي عشوائي ولا يكشف شيئاً).
/// - الرابط لا يُطبع في QR قبل أن يقبل الخادم أول رفع (الصفحة جاهزة)؛ قبلها
///   يبقى رمز التطبيق القديم `basrainvoice://` كما هو.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/print_settings_data.dart';
import '../services/database_helper.dart';
import '../services/tenant_context_service.dart';
import '../utils/app_logger.dart';
import '../utils/invoice_deep_link.dart';
import 'receipt_design.dart';
import 'receipt_model.dart';

/// مرجع مقروء من رابط naboo.fun/r.
class PublicReceiptRef {
  const PublicReceiptRef(this.token, this.globalId);

  final String token;

  /// المعرّف العالمي للفاتورة إن كان في الرابط.
  final String? globalId;
}

abstract final class PublicReceiptLink {
  static const host = 'naboo.fun';
  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  static final _token = RegExp(r'^[A-Za-z0-9]{22,64}$');
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  static String newToken([Random? rng]) {
    final r = rng ?? Random.secure();
    return String.fromCharCodes(
      List.generate(22, (_) => _alphabet.codeUnitAt(r.nextInt(62))),
    );
  }

  static String url(String token, {String? globalId}) {
    final g = globalId?.trim() ?? '';
    return g.isEmpty ? 'https://$host/r/$token' : 'https://$host/r/$token?g=$g';
  }

  static PublicReceiptRef? parse(Uri uri) {
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    if (uri.host != host && uri.host != 'www.$host') return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length != 2 || segs[0] != 'r' || !_token.hasMatch(segs[1])) {
      return null;
    }
    final g = uri.queryParameters['g']?.trim();
    if (g != null && g.isNotEmpty && !_uuid.hasMatch(g)) return null;
    return PublicReceiptRef(
      segs[1],
      (g == null || g.isEmpty) ? null : g.toLowerCase(),
    );
  }
}

/// النسخة التي تعرضها الصفحة: ما يظهر في الإيصال المطبوع فقط.
abstract final class PublicReceiptSnapshot {
  static String _hex(int argb) =>
      '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// رقم واتساب دولي للعراق من أول هاتف للمحل (07xx → 9647xx).
  static String? whatsappNumber(List<String> phones) {
    for (final p in phones) {
      var d = p.replaceAll(RegExp(r'[^0-9]'), '');
      if (d.startsWith('00')) d = d.substring(2);
      if (d.startsWith('07') && d.length == 11) d = '964${d.substring(1)}';
      if (d.startsWith('7') && d.length == 10) d = '964$d';
      if (d.startsWith('964') && d.length == 13) return d;
    }
    return null;
  }

  static Map<String, dynamic> build(
    ReceiptDocument doc, {
    required PrintSettingsData settings,
    required ReceiptTemplate template,
    ReceiptDesign? design,
  }) {
    bool shows(ReceiptSection? s) => s == null || template.shows(s);
    final pal = (design ?? const ReceiptDesign()).palette;
    final phones = [
      for (final p in settings.storePhones)
        if (p.trim().isNotEmpty) p.trim(),
    ];
    final loyalty = doc.loyalty;
    return {
      'v': 1,
      'kind': doc.kind.name,
      'title': doc.title,
      if (doc.number != null) 'number': doc.number,
      'date': DateFormat('yyyy/MM/dd  HH:mm', 'en').format(doc.date),
      if ((doc.status ?? '').isNotEmpty) 'status': doc.status,
      'store': {
        'name': settings.storeTitleLine.trim(),
        if (settings.storeAddress.trim().isNotEmpty)
          'address': settings.storeAddress.trim(),
        if (phones.isNotEmpty) 'phone': phones.first,
        'whatsapp': ?whatsappNumber(phones),
      },
      'colors': {
        'accent': _hex(pal.accent),
        'onAccent': _hex(pal.of(ReceiptColorSlot.onAccent)),
      },
      'fields': [
        for (final f in doc.fields)
          if (shows(f.section)) [f.label, f.value],
      ],
      'highlights': [
        for (final h in doc.highlights)
          if (shows(h.section)) [h.label, h.value],
      ],
      'lines': [
        for (final l in doc.lines)
          {
            'name': l.name,
            'qty': ?l.quantity,
            'unit': ?l.unit,
            'price': ?l.unitPriceFils,
            'total': l.totalFils,
          },
      ],
      'totals': [
        for (final t in doc.totals)
          if (shows(t.section))
            {'label': t.label, 'fils': t.fils, if (t.emphasis) 'main': true},
      ],
      'notes': [
        for (final n in doc.notes)
          if (!n.contains('توقيع')) n,
      ],
      if (loyalty != null && template.shows(ReceiptSection.loyalty))
        'loyalty': {
          'line': ?loyalty.line,
          if (loyalty.hasProgress) 'done': loyalty.done,
          if (loyalty.hasProgress) 'total': loyalty.total,
          'visit': ?loyalty.visit,
        },
    };
  }
}

/// الروابط على هذا الجهاز ورفعها للخادم.
abstract final class PublicReceiptLinks {
  static const _readyKey = 'public_receipts_server_ready_v1';

  static Future<void> ensureSchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS receipt_public_links (
        token TEXT PRIMARY KEY,
        invoice_global_id TEXT NOT NULL,
        tenant_id INTEGER NOT NULL DEFAULT 1,
        snapshot TEXT NOT NULL,
        uploaded INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_receipt_public_links_gid '
      'ON receipt_public_links(invoice_global_id)',
    );
  }

  /// للاختبارات.
  @visibleForTesting
  static Future<Database> Function() database = () => DatabaseHelper().database;
  @visibleForTesting
  static Future<void> Function(String fn, Map<String, dynamic> params) rpc =
      (fn, params) => Supabase.instance.client.rpc(fn, params: params);
  @visibleForTesting
  static Future<bool> Function() serverReady = () async =>
      (await SharedPreferences.getInstance()).getBool(_readyKey) ?? false;
  @visibleForTesting
  static Future<void> Function() markServerReady = () async =>
      (await SharedPreferences.getInstance()).setBool(_readyKey, true);

  /// يجهّز رابط الفاتورة ويحفظ نسختها ويرفعها، ويُرجع الإيصال برابط naboo.fun
  /// في QR إن كان الخادم جاهزاً. أي خطأ = الإيصال كما هو (لا تتعطّل الطباعة).
  static Future<ReceiptDocument> attach(
    ReceiptDocument doc, {
    required PrintSettingsData settings,
    required ReceiptTemplate template,
    ReceiptDesign? design,
  }) async {
    try {
      final qr = doc.qrData;
      if (qr == null || qr.isEmpty) return doc;
      final ref = InvoiceDeepLink.parse(Uri.parse(qr));
      final gid = ref?.globalId;
      if (gid == null) return doc;
      final snapshot = jsonEncode(
        PublicReceiptSnapshot.build(
          doc,
          settings: settings,
          template: template,
          design: design,
        ),
      );
      final db = await database();
      await ensureSchema(db);
      final rows = await db.query(
        'receipt_public_links',
        where: 'invoice_global_id = ?',
        whereArgs: [gid],
        orderBy: 'created_at',
        limit: 1,
      );
      final String token;
      if (rows.isEmpty) {
        token = PublicReceiptLink.newToken();
        await db.insert('receipt_public_links', {
          'token': token,
          'invoice_global_id': gid,
          'tenant_id': _tenant(),
          'snapshot': snapshot,
          'uploaded': 0,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } else {
        token = rows.first['token'] as String;
        if (rows.first['snapshot'] != snapshot) {
          await db.update(
            'receipt_public_links',
            {'snapshot': snapshot, 'uploaded': 0},
            where: 'token = ?',
            whereArgs: [token],
          );
        }
      }
      // الرفع في الخلفية: الطباعة لا تنتظر الشبكة.
      unawaited(flush());
      if (!await serverReady()) return doc;
      return doc.withQr(PublicReceiptLink.url(token, globalId: gid));
    } catch (e, st) {
      AppLogger.error('PublicReceiptLinks', 'attach', e, st);
      return doc;
    }
  }

  static int _tenant() {
    try {
      return TenantContextService.instance.activeTenantId;
    } catch (_) {
      return 1;
    }
  }

  static Future<void>? _flushing;

  /// يرفع النسخ غير المرفوعة. أول رفع ناجح = الخادم جاهز.
  static Future<void> flush() =>
      _flushing ??= _flush().whenComplete(() => _flushing = null);

  static Future<void> _flush() async {
    try {
      final db = await database();
      await ensureSchema(db);
      final pending = await db.query(
        'receipt_public_links',
        where: 'uploaded = 0',
        limit: 50,
      );
      for (final r in pending) {
        final snapshot = r['snapshot'] as String;
        await rpc('receipt_publish', {
          'p_token': r['token'],
          'p_local_tenant_id': r['tenant_id'],
          'p_invoice_global_id': r['invoice_global_id'],
          'p_snapshot': jsonDecode(snapshot),
        });
        await db.update(
          'receipt_public_links',
          {'uploaded': 1},
          where: 'token = ? AND snapshot = ?',
          whereArgs: [r['token'], snapshot],
        );
        await markServerReady();
      }
    } catch (e) {
      // بلا إنترنت أو الخادم أقدم: يُعاد في الطباعة أو المزامنة التالية.
      AppLogger.warn('PublicReceiptLinks', 'flush: $e');
    }
  }

  /// فاتورة حُذفت أو استُرجعت كاملة: كل روابطها تُظهر ذلك. بلا إنترنت = لا شيء.
  static Future<void> setState(String invoiceGlobalId, String? state) async {
    try {
      final db = await database();
      await ensureSchema(db);
      final has = await db.query(
        'receipt_public_links',
        columns: ['token'],
        where: 'invoice_global_id = ?',
        whereArgs: [invoiceGlobalId],
        limit: 1,
      );
      if (has.isEmpty) return;
      await rpc('receipt_set_state', {
        'p_invoice_global_id': invoiceGlobalId,
        'p_state': state,
      });
    } catch (e) {
      AppLogger.warn('PublicReceiptLinks', 'setState: $e');
    }
  }

  /// مسح رابط naboo.fun/r داخل التطبيق: المعرّف العالمي من الرابط، أو من هذا
  /// الجهاز، أو من الخادم (رمز طُبع على جهاز آخر في المحل).
  static Future<String?> globalIdFor(PublicReceiptRef ref) async {
    if (ref.globalId != null) return ref.globalId;
    try {
      final db = await database();
      await ensureSchema(db);
      final rows = await db.query(
        'receipt_public_links',
        columns: ['invoice_global_id'],
        where: 'token = ?',
        whereArgs: [ref.token],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first['invoice_global_id'] as String;
      final g = await Supabase.instance.client.rpc(
        'receipt_owner_lookup',
        params: {'p_token': ref.token},
      );
      return g is String && g.isNotEmpty ? g : null;
    } catch (e) {
      AppLogger.warn('PublicReceiptLinks', 'globalIdFor: $e');
      return null;
    }
  }
}
