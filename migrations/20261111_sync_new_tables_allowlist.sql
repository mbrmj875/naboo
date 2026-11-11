-- البندان 4.4 و4.1: جدولا sync_tombstones وstock_ledger يُرفعان في اللقطة، فيُضافان
-- إلى قائمة الجداول المسموحة قبل التحويل إلى وضع الرفض.
-- الرجوع:
--   delete from public.sync_guard_allowed_tables
--   where table_name in ('sync_tombstones', 'stock_ledger');
insert into public.sync_guard_allowed_tables (table_name)
values ('sync_tombstones'), ('stock_ledger')
on conflict do nothing;
