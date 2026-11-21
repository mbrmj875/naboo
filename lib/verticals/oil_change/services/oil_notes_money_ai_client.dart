import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../utils/app_logger.dart';
import '../utils/oil_notes_money_parser.dart';

/// يستدعي Edge Function `oil-notes-money` (DeepSeek) لتحليل ملاحظات الغيار.
class OilNotesMoneyAiClient {
  OilNotesMoneyAiClient();

  /// يحلل [notes] اختيارياً مع تلميح من المحلل المحلي.
  Future<OilNotesMoneyParseResult?> analyze({
    required String notes,
    OilNotesMoneyParseResult? localHint,
  }) async {
    final text = notes.trim();
    if (text.length < 3) return null;
    if (Supabase.instance.client.auth.currentUser == null) return null;

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'oil-notes-money',
        body: {
          'notes': text.length > 1200 ? text.substring(0, 1200) : text,
          if (localHint != null && localHint.isNotEmpty)
            'local_hint': {
              'total_dinars': localHint.totalDinars,
              'items': [
                for (final h in localHint.hits.take(8))
                  {
                    'dinars': h.dinars,
                    'type': h.type.name,
                    'label': h.contextLabel,
                    'selected': h.defaultSelected,
                  },
              ],
            },
        },
      );

      final raw = response.data;
      final map = raw is Map<String, dynamic>
          ? raw
          : raw is Map
              ? Map<String, dynamic>.from(raw)
              : null;
      if (map == null) return null;
      if (map['ok'] == false) {
        AppLogger.warn(
          'oil_notes_money_ai',
          'invoke rejected: ${map['error']}',
        );
        return null;
      }
      return OilNotesMoneyParseResult.fromAiPayload(map);
    } on FunctionException catch (e) {
      AppLogger.warn('oil_notes_money_ai', 'invoke failed: ${e.details}');
      return null;
    } catch (e, st) {
      AppLogger.error('oil_notes_money_ai', 'invoke error', e, st);
      return null;
    }
  }
}
