-- PDF بطاقة غيار الزيت عبر واتساب الرسمي بعد 5 دقائق صمت.
-- يُنفَّذ في SQL Editor قبل نشر whatsapp-oil-card-pdf-cron.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'whatsapp-oil-card-pdfs',
  'whatsapp-oil-card-pdfs',
  false,
  2097152,
  ARRAY['application/pdf']::text[]
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS "Tenants read own oil card pdfs" ON storage.objects;
CREATE POLICY "Tenants read own oil card pdfs"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'whatsapp-oil-card-pdfs'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Tenants upload own oil card pdfs" ON storage.objects;
CREATE POLICY "Tenants upload own oil card pdfs"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'whatsapp-oil-card-pdfs'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

DROP POLICY IF EXISTS "Tenants update own oil card pdfs" ON storage.objects;
CREATE POLICY "Tenants update own oil card pdfs"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'whatsapp-oil-card-pdfs'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'whatsapp-oil-card-pdfs'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE TABLE IF NOT EXISTS public.whatsapp_oil_card_pdf_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_user_id uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  order_ref text NOT NULL,
  to_phone text NOT NULL DEFAULT '',
  phone_number_id text,
  pdf_storage_path text,
  card_payload jsonb,
  status text NOT NULL DEFAULT 'awaiting_inbound'
    CHECK (status IN ('awaiting_inbound', 'pending', 'sending', 'sent', 'failed')),
  idle_after timestamptz,
  sent_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_whatsapp_oil_card_pdf_jobs_order
  ON public.whatsapp_oil_card_pdf_jobs (tenant_user_id, order_ref);

CREATE INDEX IF NOT EXISTS idx_whatsapp_oil_card_pdf_jobs_due
  ON public.whatsapp_oil_card_pdf_jobs (status, idle_after)
  WHERE status IN ('pending', 'sending');

ALTER TABLE public.whatsapp_oil_card_pdf_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS whatsapp_oil_card_pdf_jobs_own_select
  ON public.whatsapp_oil_card_pdf_jobs;
CREATE POLICY whatsapp_oil_card_pdf_jobs_own_select
  ON public.whatsapp_oil_card_pdf_jobs
  FOR SELECT
  TO authenticated
  USING (tenant_user_id = auth.uid());

DROP POLICY IF EXISTS whatsapp_oil_card_pdf_jobs_own_insert
  ON public.whatsapp_oil_card_pdf_jobs;
CREATE POLICY whatsapp_oil_card_pdf_jobs_own_insert
  ON public.whatsapp_oil_card_pdf_jobs
  FOR INSERT
  TO authenticated
  WITH CHECK (tenant_user_id = auth.uid());

DROP POLICY IF EXISTS whatsapp_oil_card_pdf_jobs_own_update
  ON public.whatsapp_oil_card_pdf_jobs;
CREATE POLICY whatsapp_oil_card_pdf_jobs_own_update
  ON public.whatsapp_oil_card_pdf_jobs
  FOR UPDATE
  TO authenticated
  USING (tenant_user_id = auth.uid())
  WITH CHECK (tenant_user_id = auth.uid());

COMMENT ON TABLE public.whatsapp_oil_card_pdf_jobs IS
  'إرسال PDF بطاقة الغيار عبر Cloud API بعد 5 دقائق صمت — مرة لكل طلب، وبعد رد الزبون فقط';

CREATE TABLE IF NOT EXISTS public.whatsapp_ops_cron_config (
  key text primary key,
  value text not null
);

INSERT INTO public.whatsapp_ops_cron_config (key, value)
VALUES
  (
    'whatsapp_oil_card_pdf_url',
    'https://rkofqwcuvbzrnmelvxhz.supabase.co/functions/v1/whatsapp-oil-card-pdf-cron'
  )
ON CONFLICT (key) DO NOTHING;

INSERT INTO public.whatsapp_ops_cron_config (key, value)
SELECT 'whatsapp_oil_card_pdf_bearer', value
FROM public.whatsapp_ops_cron_config
WHERE key IN ('whatsapp_ops_analyst_bearer', 'CRON_SECRET')
ORDER BY CASE key WHEN 'whatsapp_ops_analyst_bearer' THEN 0 ELSE 1 END
LIMIT 1
ON CONFLICT (key) DO NOTHING;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid)
    from cron.job
    where jobname = 'whatsapp-oil-card-pdf';

    perform cron.schedule(
      'whatsapp-oil-card-pdf',
      '* * * * *',
      $cron$
      select net.http_post(
        url := (select value from public.whatsapp_ops_cron_config where key = 'whatsapp_oil_card_pdf_url'),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (
            select value from public.whatsapp_ops_cron_config where key = 'whatsapp_oil_card_pdf_bearer'
          )
        ),
        body := '{"source":"pg_cron"}'::jsonb
      );
      $cron$
    );
  else
    raise notice 'pg_cron غير مفعّل — استخدم Dashboard Schedules (* * * * *).';
  end if;
exception
  when undefined_table then
    raise notice 'pg_net غير متاح — استخدم Dashboard Schedules.';
  when others then
    raise notice 'تخطّي جدولة whatsapp-oil-card-pdf: %', sqlerrm;
end $$;
