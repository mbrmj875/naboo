-- الملاحظة النصية تُنسب للفني مثل الرقم تماماً، وتُحصى كلها لا الأحدث فقط.
-- المتوسط وحده يعتمد آخر رد لكل بطاقة حتى لا يتكرر تقييم البطاقة الواحدة.

-- إسقاط ثم إنشاء: ترتيب الأعمدة تغيّر بإضافة replies_count
DROP VIEW IF EXISTS public.oil_change_employee_rating_summary;

CREATE VIEW public.oil_change_employee_rating_summary
WITH (security_invoker = true) AS
WITH base AS (
  SELECT
    tenant_user_id,
    COALESCE(NULLIF(btrim(employee_name), ''), 'غير محدد') AS employee_name,
    COALESCE(order_ref, id::text) AS card_key,
    score,
    note,
    created_at
  FROM public.oil_change_service_ratings
  WHERE deleted_at IS NULL
),
latest_per_card AS (
  SELECT DISTINCT ON (tenant_user_id, card_key)
    tenant_user_id,
    employee_name,
    score
  FROM base
  ORDER BY tenant_user_id, card_key, created_at DESC
),
scores AS (
  SELECT
    tenant_user_id,
    employee_name,
    COUNT(*) FILTER (WHERE score IS NOT NULL) AS ratings_count,
    ROUND(AVG(score) FILTER (WHERE score IS NOT NULL), 2) AS average_score
  FROM latest_per_card
  GROUP BY 1, 2
),
replies AS (
  SELECT
    tenant_user_id,
    employee_name,
    COUNT(*) AS replies_count,
    COUNT(*) FILTER (WHERE note IS NOT NULL) AS notes_count,
    MAX(created_at) AS last_rating_at
  FROM base
  GROUP BY 1, 2
)
SELECT
  r.tenant_user_id,
  r.employee_name,
  COALESCE(s.ratings_count, 0) AS ratings_count,
  s.average_score,
  r.notes_count,
  r.replies_count,
  r.last_rating_at
FROM replies r
LEFT JOIN scores s
  ON s.tenant_user_id = r.tenant_user_id
 AND s.employee_name = r.employee_name;

COMMENT ON VIEW public.oil_change_employee_rating_summary IS
  'ملخص تقييمات الفني: المتوسط من آخر رد لكل بطاقة، والملاحظات والردود تُحصى كلها';
