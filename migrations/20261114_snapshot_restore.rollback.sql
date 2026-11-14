-- رجوع عن 20261114_snapshot_restore.sql. الدالة لا تُستدعى إلا يدوياً.
-- لإلغاء استرجاع تم: استرجع النسخة التي حفظها الأرشيف قبله بنفس الدالة.
drop function if exists ops_private.restore_snapshot_from_history(bigint, boolean);
