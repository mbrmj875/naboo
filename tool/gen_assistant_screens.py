"""يولّد قائمة شاشات المساعد للوحة الإدارة وللخادم من خريطة الشاشات في التطبيق.

  python3 tool/gen_assistant_screens.py

المخرجات:
  admin-web/lib/assistant-screens.ts      (صفحة فيديوهات المساعد)
  supabase/functions/assistant-chat/screens.ts (المسارات المعروفة للنموذج)
الاختبار test/assistant/screen_map_sync_test.dart يفشل إن نُسي التوليد.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GROUPS = {
    'home': 'أخرى', 'oil': 'الزيت', 'wash': 'الغسيل', 'whatsapp': 'واتساب', 'inventory': 'المخزون',
    'customers': 'العملاء والديون', 'money': 'المال', 'reports': 'التقارير والطباعة', 'staff': 'الموظفون',
    'settings': 'الإعدادات',
}


def screens():
    src = (ROOT / 'lib/assistant/screen_map/oil_screen_map.dart').read_text()
    nav = (ROOT / 'lib/navigation/content_navigation.dart').read_text()
    consts = dict(re.findall(r"static const (\w+) =\s*'([^']+)';", nav))
    out = []
    for m in re.finditer(r"AppScreenSpec\(\s*routeId: ([\w.]+),\s*title: '([^']+)',\s*group: ScreenGroup\.(\w+)", src):
        ref = m.group(1)
        rid = 'app_reports_0' if ref == '_reports' else consts[ref.split('.')[1]]
        out.append((rid, m.group(2), GROUPS[m.group(3)]))
    return out


def main():
    items = screens()
    head = ['// مولَّد من lib/assistant/screen_map/oil_screen_map.dart — لا تعدّله يدوياً.',
            '// أعد التوليد: python3 tool/gen_assistant_screens.py']
    ts = head + ['export type AssistantScreen = { routeId: string; title: string; group: string };', '',
                 'export const ASSISTANT_SCREENS: AssistantScreen[] = [']
    ts += [f'  {{ routeId: "{r}", title: "{t}", group: "{g}" }},' for r, t, g in items]
    ts.append('];')
    (ROOT / 'admin-web/lib/assistant-screens.ts').write_text('\n'.join(ts) + '\n')

    fn = head + ['/** كل شاشات التطبيق التي يعرفها المساعد: المعرّف والعنوان. الوصف الكامل',
                 ' *  بأزرارها يطلبه النموذج من الهاتف بأداة ui_describe. */',
                 'export const SCREEN_IDS: ReadonlyArray<readonly [string, string]> = [']
    fn += [f'  ["{r}", "{t}"],' for r, t, _ in items]
    fn.append('];')
    (ROOT / 'supabase/functions/assistant-chat/screens.ts').write_text('\n'.join(fn) + '\n')
    print(len(items), 'screens')


if __name__ == '__main__':
    main()
