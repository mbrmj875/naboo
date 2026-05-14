/// سياسة صف [tenant_access] على السيرفر (Supabase).
///
/// المستخدم يُعتبر «مسموحاً بالعمل» فقط إذا:
/// `kill_switch == false` **و** `valid_until` بعد الوقت الموثوق (يفضّل وقت السيرفر، وليس ساعة الجهاز وحدها).
bool tenantCloudAccessAllowsUsage({
  required bool killSwitch,
  required DateTime validUntil,
  required DateTime trustedNow,
}) {
  return !killSwitch && validUntil.isAfter(trustedNow);
}
