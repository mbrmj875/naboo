-- رجوع عن 20261114_sync_queue_tenant_guard.sql.
drop trigger if exists trg_guard_tenant_row_write on public.cash_ledger;
drop trigger if exists trg_guard_tenant_row_write on public.work_shifts;
drop function if exists public.fn_guard_tenant_row_write();
