import '../models/recent_activity_entry.dart';

/// معايير تصفية نشاط الموظف في لوحة المالك.
class StaffActivityFilter {
  const StaffActivityFilter({this.userId, this.names = const {}});

  final int? userId;
  final Set<String> names;

  bool get isActive =>
      (userId != null && userId! > 0) || names.isNotEmpty;
}

/// يُضيف مفتاح اسم للتطابق (بدون مفاتيح فارغة).
void addStaffActivityNameKey(Set<String> keys, String raw) {
  final t = raw.trim();
  if (t.isEmpty) return;
  keys.add(t.toLowerCase());
  final norm = normalizeStaffActivityKey(t);
  if (norm.isNotEmpty && norm != t.toLowerCase()) {
    keys.add(norm);
  }
}

/// أسماء رقمية بالكامل (مثل «3») تُحفَظ كما هي؛ بادئة أرقام فقط تُزال عند وجود نص بعدها.
String normalizeStaffActivityKey(String name) {
  final s = name.trim().toLowerCase();
  if (s.isEmpty) return s;
  if (RegExp(r'^\d+$').hasMatch(s)) return s;
  final stripped = s.replaceFirst(RegExp(r'^\d+'), '').trim();
  return stripped.isEmpty ? s : stripped;
}

/// هل النشاط يخص الموظف المحدد؟ يعتمد على [actorUserId] ثم تطابق الاسم الحرفي.
bool activityMatchesStaffFilter(
  RecentActivityEntry entry,
  StaffActivityFilter filter,
) {
  if (!filter.isActive) return true;

  final uid = filter.userId;
  if (uid != null && uid > 0 && entry.actorUserId == uid) {
    return true;
  }

  final actor = entry.actorName?.trim() ?? '';
  if (actor.isEmpty) return false;

  final lower = actor.toLowerCase();
  if (filter.names.contains(lower)) return true;

  final norm = normalizeStaffActivityKey(actor);
  if (norm.isNotEmpty && filter.names.contains(norm)) return true;

  return false;
}
