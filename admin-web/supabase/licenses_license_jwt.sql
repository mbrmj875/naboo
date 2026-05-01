-- JWT v2 للنسخ لاحقاً من لوحة الإدارة. نفّذ مرة واحدة في Supabase SQL Editor.

alter table public.licenses add column if not exists license_jwt text;

comment on column public.licenses.license_jwt is 'JWT RS256 كامل للعميل (v2).';
