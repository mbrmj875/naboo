import 'package:flutter_test/flutter_test.dart';
import 'package:naboo/assistant/assistant_local_intents.dart';
import 'package:naboo/assistant/assistant_local_router.dart';

void main() {
  const router = AssistantLocalRouter();
  bool all(String _) => true;
  LocalRoute? r(String q, {bool Function(String)? can}) => router.route(q, canUseTool: can ?? all);

  group('التحيات', () {
    test('تحية وشكر ووداع', () {
      expect((r('السلام عليكم') as LocalReply).kind, LocalIntentKind.greeting);
      expect((r('هلا حبيبي 👋') as LocalReply).kind, LocalIntentKind.greeting);
      expect((r('شكراً') as LocalReply).kind, LocalIntentKind.thanks);
      expect((r('تسلم ايدك حبيبي') as LocalReply).kind, LocalIntentKind.thanks);
      expect((r('مع السلامة') as LocalReply).kind, LocalIntentKind.bye);
    });
    test('تحية مع سؤال لا تُعامل كتحية', () {
      expect(r('هلا شكد باقي عدنا زيت للكورولا'), isNull);
      expect(r('السلام عليكم شلون اسوي فاتورة'), isNull);
    });
  });

  group('فتح الشاشات', () {
    test('أمر فتح صريح', () {
      expect((r('افتح المخزون') as LocalOpenScreen).screen.routeId, 'app_inventory');
      expect((r('وديني للديون') as LocalOpenScreen).screen.routeId, 'app_debts');
      expect((r('افتحلي سجل الخدمات') as LocalOpenScreen).screen.routeId, 'app_oil_services_log');
    });
    test('«وين» سؤال وليس أمر فتح', () {
      expect(r('وين المخزون'), isNull);
    });
  });

  group('أسئلة البيانات', () {
    test('شكد باقي من 5W-30', () {
      final a = r('شكد باقي من 5W-30') as LocalToolAnswer;
      expect(a.intent.tool, 'stock_search');
      expect(a.args['query'], '5W-30');
      expect(a.args['kind'], 'oil');
    });
    test('لزوجة بالأرقام العربية وبالكلمات', () {
      expect((r('اكو ٥ ٣٠؟') as LocalToolAnswer).args['query'], '5W-30');
      expect((r('عدنا خمسة ثلاثين') as LocalToolAnswer).args['query'], '5W-30');
      expect((r('موجود 10w40') as LocalToolAnswer).args['query'], '10W-40');
    });
    test('النواقص ومبيعات اليوم والمعلقات', () {
      expect((r('النواقص') as LocalToolAnswer).intent.tool, 'stock_low');
      final s = r('مبيعات اليوم') as LocalToolAnswer;
      expect(s.intent.tool, 'sales_summary');
      expect(s.args['period'], 'today');
      expect((r('اكو بطاقات معلقة؟') as LocalToolAnswer).intent.tool, 'oil_card_find');
    });
    test('سجل لوحة', () {
      final a = r('سجل لوحة 12345 ب') as LocalToolAnswer;
      expect(a.intent.tool, 'car_history');
      expect(a.args['plate'], '12345 ب');
    });
    test('كلمات المنع ترسل السؤال للنموذج', () {
      expect(r('شكد باقي 5W-30 يناسب الكورولا'), isNull);
      expect(r('مبيعات اليوم قارنها بامس'), isNull);
      expect(r('النواقص اطلبها من المورد'), isNull);
    });
    test('بلا لزوجة أو لوحة لا تُجاب محلياً', () {
      expect(r('شكد باقي زيت'), isNull);
      expect(r('سجل السيارة'), isNull);
    });
    test('سؤال طويل يذهب للنموذج', () {
      expect(r('شكد باقي من 5W-30 وشكد بعنا منه هذا الاسبوع وشنو اكثر زبون اشترى منه'), isNull);
    });
    test('الأسئلة الشائعة الخمسة عشر بصيغها (قائمة البذور 2)', () {
      const cases = {
        'cards_today': ['شكد بطاقة اليوم', 'كم سيارة بدلنا اليوم', 'عدد الغيارات اليوم', 'شكد سيارة اجت اليوم', 'بطاقات اليوم'],
        'cards_pending': ['البطاقات المعلقة', 'اكو بطاقة ما مدفوعة', 'شنو المعلق', 'البطاقات اللي ما انحسبت'],
        'cards_last': ['آخر بطاقة', 'اخر سيارة', 'شنو اخر غيار', 'البطاقة الأخيرة', 'آخر وحدة سويناها'],
        'debts_all': ['الديون', 'منو مطلوب', 'ديون الزباين'],
        'cash_now': ['شكد بالقاصة', 'رصيد الصندوق', 'شكد بالدرج', 'الكاش اللي عندنا', 'شكد بالصندوق هسه'],
        'expenses_today': ['مصاريف اليوم', 'شكد صرفنا اليوم', 'صرفيات اليوم'],
        'staff_now': ['منو شغال', 'منو بالوردية', 'الوردية مفتوحة؟', 'منو موجود اليوم', 'الموظفين اليوم'],
        'washes_today': ['شكد غسلنا اليوم', 'غسيل اليوم', 'كم سيارة غسلنا', 'حساب الغسيل اليوم', 'الغسلات اليوم'],
        'top_week': ['شنو اكثر زيت انباع', 'الأكثر بيعاً', 'شنو ماشي هالأسبوع', 'اكثر صنف بعناه', 'الزيت الطالب'],
        'due_soon': ['منو موعده قريب', 'الزباين اللي لازم يبدلون', 'منو مستحق غيار', 'منو لازم نذكره', 'السيارات اللي فات موعدها'],
        'stock_low': ['شنو النواقص', 'شنو اللي خالص', 'الزيوت اللي خلصت', 'المخزون الناقص'],
        'sales_today': ['مبيعات اليوم', 'شكد بعت اليوم', 'شكد دخلنا اليوم'],
      };
      for (final e in cases.entries) {
        for (final q in e.value) {
          final a = r(q);
          expect(a, isA<LocalToolAnswer>(), reason: q);
          expect((a! as LocalToolAnswer).intent.id, e.key, reason: q);
        }
      }
      expect((r('غسيل اليوم') as LocalToolAnswer).args['channel'], 'wash');
      expect((r('الأكثر بيعاً') as LocalToolAnswer).args['period'], 'this_week');
    });
    test('أسئلة أعقد من الشائعة تذهب للنموذج', () {
      expect(r('دين ابو علي'), isNull); // دين زبون باسمه: النموذج يستخرج الاسم.
      expect(r('ديون الموردين'), isNull);
      expect(r('مصاريف اليوم قارنها بامس'), isNull);
      expect(r('منو شغال وشكد راتبه'), isNull);
      expect(r('غسيل اليوم شنو العرض'), isNull);
      expect(r('الزباين اللي لازم يبدلون ارسلهم رسالة'), isNull);
    });
    test('كل نية محلية تستعمل أداة معروفة بوسائط صحيحة', () {
      const known = {'stock_search', 'stock_low', 'sales_summary', 'car_history', 'oil_card_find', 'debts_summary',
        'cash_summary', 'staff_status', 'top_products', 'due_customers'};
      final ids = <String>{};
      for (final i in AssistantLocalIntents.dataIntents) {
        expect(known, contains(i.tool), reason: i.id);
        expect(ids.add(i.id), isTrue, reason: 'مكرر ${i.id}');
        final p = i.args['period'];
        if (p != null) expect({'today', 'this_week'}, contains(p), reason: i.id);
      }
      expect(ids.length, greaterThanOrEqualTo(14));
    });
    test('أداة غير مسموحة لا تُستعمل', () {
      expect(r('النواقص', can: (t) => t != 'stock_low'), isNull);
    });
  });

  test('استخراج اللوحة بالحرف قبل الرقم', () {
    expect(extractPlate('ب 4567'), '4567 ب');
    expect(extractPlate('ماكو لوحة'), isNull);
  });
}
