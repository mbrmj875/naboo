-- كل رد رقمي من العميل يُحفظ تقييماً حقيقياً، والمتوسط يعتمد آخر رد لكل بطاقة.
-- قبله كان القيد يحوّل الرد الثاني إلى ملاحظة نصية «تقييم مكرر: N».

-- 1) رفع القيد الذي منع تسجيل الرد الثاني كرقم
DROP INDEX IF EXISTS public.idx_oil_ratings_one_score_per_order;

-- 2) ترميم الصفوف التي حُفظت ملاحظةً بدل رقم
UPDATE public.oil_change_service_ratings
SET
  score = (regexp_match(note, '^تقييم مكرر:\s*(\d{1,2})$'))[1]::int,
  note = NULL
WHERE deleted_at IS NULL
  AND score IS NULL
  AND note ~ '^تقييم مكرر:\s*(\d{1,2})$'
  AND (regexp_match(note, '^تقييم مكرر:\s*(\d{1,2})$'))[1]::int BETWEEN 1 AND 10;

-- 3) المتوسط على آخر تقييم لكل بطاقة — رد العميل الأخير هو رأيه النهائي،
--    والردود بلا بطاقة معروفة تُحسب كل واحدة على حدة.
CREATE OR REPLACE VIEW public.oil_change_employee_rating_summary
WITH (security_invoker = true) AS
WITH latest_per_card AS (
  SELECT DISTINCT ON (tenant_user_id, COALESCE(order_ref, id::text))
    tenant_user_id,
    employee_name,
    score,
    note,
    created_at
  FROM public.oil_change_service_ratings
  WHERE deleted_at IS NULL
  ORDER BY
    tenant_user_id,
    COALESCE(order_ref, id::text),
    created_at DESC
)
SELECT
  tenant_user_id,
  COALESCE(NULLIF(btrim(employee_name), ''), 'غير محدد') AS employee_name,
  COUNT(*) FILTER (WHERE score IS NOT NULL) AS ratings_count,
  ROUND(AVG(score) FILTER (WHERE score IS NOT NULL), 2) AS average_score,
  COUNT(*) FILTER (WHERE score IS NULL AND note IS NOT NULL) AS notes_count,
  MAX(created_at) AS last_rating_at
FROM latest_per_card
GROUP BY 1, 2;

COMMENT ON VIEW public.oil_change_employee_rating_summary IS
  'متوسط تقييمات كل فني بناءً على آخر رد لكل بطاقة — يرث RLS من الجدول الأساسي';
