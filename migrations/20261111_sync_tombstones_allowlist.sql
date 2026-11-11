-- البند 4.4: جدول شاهد الحذف sync_tombstones يُرفع في اللقطة، فيُضاف إلى
-- قائمة الجداول المسموحة قبل التحويل إلى وضع الرفض.
-- الرجوع:
--   delete from public.sync_guard_allowed_tables where table_name = 'sync_tombstones';
insert into public.sync_guard_allowed_tables (table_name)
values ('sync_tombstones')
on conflict do nothing;
