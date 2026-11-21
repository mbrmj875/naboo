# عزل مستأجري المنيو العام — قائمة تحقق P0

لا يُطلق توسيع قوالب قبل اجتياز هذه البنود.

## قواعد
1. `tenant_uuid` يُحلّ فقط من `tenant_slug` على السيرفر.
2. `table_slug` يُحلّ فقط مع نفس `tenant_uuid`.
3. `menu_item_id` خارج المستأجر → رفض الطلب.
4. `qr_table` يتطلب `table_slug`؛ `public_link` يرفض أي `table_slug`.
5. السلة في المتصفح مفتاحها `naboo.menu.cart.{tenant_slug}.v1`.
6. Realtime/KDS مفلترة بـ`tenant_uuid` من جلسة المطعم.

## سيناريوهات يدوية
| # | الخطوات | النتيجة المتوقعة |
|---|---------|-------------------|
| 1 | افتح `/m/A` وأضف للسلة، ثم `/m/B` | سلة B فارغة أو سلة B فقط — لا أصناف A |
| 2 | من `/m/A` أرسل طلبًا | يظهر في مطبخ A فقط |
| 3 | افتح `/m/A/t/table5` | شارة طاولة؛ الطلب يظهر «طاولة …» في KDS لنفس A |
| 4 | POST create-order بـ`tenant_slug=A` و`table_slug` لمطعم B | `table_not_found` |
| 5 | POST `channel=public_link` مع `table_slug` | `table_not_allowed_on_public_link` |
| 6 | POST `channel=qr_table` بلا `table_slug` | `table_slug_required` |
| 7 | POST أصناف من مطعم B تحت slug A | `item_unavailable` |

## Edge
- الدالة: `supabase/functions/restaurant-create-order`
- بعد التعديل: أعد نشر الدالة على المشروع المرتبط.
