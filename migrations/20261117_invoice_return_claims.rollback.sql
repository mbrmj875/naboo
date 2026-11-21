/* تراجع 20261117_invoice_return_claims.sql — يحذف المطالبات والدالتين. */
begin;
drop function if exists public.rpc_void_return_claim(uuid);
drop function if exists public.rpc_claim_invoice_return(uuid, uuid, jsonb, numeric, text);
drop table if exists public.invoice_return_claims;
commit;
