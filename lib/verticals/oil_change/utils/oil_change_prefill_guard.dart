/// قواعد حماية تعديلات المستخدم عند فتح بطاقة غيار من صف الجدول.
bool shouldBlockFluidReconcileAfterPrefill({
  required bool isPrefillFromLog,
  required bool prefillCatalogSyncedOnce,
}) =>
    isPrefillFromLog && prefillCatalogSyncedOnce;

bool shouldBlockAutoVisitLookup({
  required bool isPrefillFromLog,
  required bool allowAutoVisitLookup,
  bool force = false,
}) =>
    !force && isPrefillFromLog && !allowAutoVisitLookup;
