-- تراجع 20261130_public_receipts.sql: يحذف الدوال والجدول (روابط الزبائن تتوقف).
drop function if exists public.receipt_owner_lookup(text);
drop function if exists public.receipt_public_get(text);
drop function if exists public.receipt_set_state(text, text);
drop function if exists public.receipt_publish(text, integer, text, jsonb);
drop table if exists public.public_receipts;
