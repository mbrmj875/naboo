import '../guide_anchor.dart';
import '../guide_tour.dart';
import '../../navigation/content_navigation.dart';

/// جولات إدارة المستخدمين والموظفين والهويات والورديات.
final List<GuideTour> usersStaffTours = [
  const GuideTour(
    id: GuideTourIds.usersModuleOverview,
    title: 'دليل وحدة المستخدمين',
    description: 'إدارة المستخدمين + الورديات + الهويات',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.usersListTitle,
        title: 'إدارة المستخدمين',
        body:
            'من الشريط السفلي «المستخدمين» → «إدارة المستخدمين». هنا قائمة الموظفين: إضافة، تعديل، تعطيل، و⋮ لبطاقة الهوية. كل حساب يظهر لاحقاً في «من سيبدأ العمل؟» بعد PIN.',
        speakText:
            'هذه إدارة المستخدمين. منها تضيف وتعدّل الموظفين الذين يدخلون من بوابة من سيبدأ العمل.',
        ensureRouteId: AppContentRoutes.users,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.usersShiftsTitle,
        title: 'ورديات الموظفين (أسبوع)',
        body:
            'الباب الثاني في قائمة المستخدمين: تقويم من السبت للجمعة يعرض أشرطة الدخول والخروج واسم موظف الوردية. الورديات تُنشأ عند فتح/إغلاق الوردية اليومي — هنا للمتابعة.',
        speakText:
            'هذه ورديات الموظفين الأسبوعية. تتابع أوقات الدخول والخروج لكل موظف.',
        ensureRouteId: AppContentRoutes.staffShiftsWeek,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.usersIdentityTitle,
        title: 'هويات الموظفين',
        body:
            'الباب الثالث: بطاقة هوية لكل موظف (باركود وQR ورمز وردية). تُفتح أيضاً من ⋮ على بطاقة المستخدم في إدارة المستخدمين. مفيدة للتعريف والطباعة دون كشف PIN الدخول.',
        speakText:
            'هذه هويات الموظفين. افتح البطاقة لعرض الباركود ورمز الوردية.',
        ensureRouteId: AppContentRoutes.employeeIdentity,
      ),
    ],
  ),
  const GuideTour(
    id: GuideTourIds.usersAddStaff,
    title: 'إضافة مستخدم / موظف',
    description: 'من القائمة إلى نموذج مستخدم جديد بالتفصيل',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.usersListTitle,
        title: 'إدارة المستخدمين',
        body:
            'افتح «المستخدمين» من الشريط السفلي ثم «إدارة المستخدمين». هنا تظهر كل حسابات الموظفين النشطة (غير صاحب العمل).',
        speakText: 'افتح إدارة المستخدمين من قائمة المستخدمين.',
        ensureRouteId: AppContentRoutes.users,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.usersFabAdd,
        title: 'مستخدم جديد',
        body:
            'اضغط الشريط الذهبي «مستخدم جديد» أعلى قائمة المستخدمين. يظهر لمن يدخل بحساب صاحب العمل أو لديه صلاحية إدارة المستخدمين.',
        speakText: 'اضغط مستخدم جديد أعلى القائمة.',
        ensureRouteId: AppContentRoutes.users,
        awaitTap: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.usersFormName,
        title: 'الاسم',
        body:
            'في «بيانات الموظف» اكتب الاسم الظاهر في بوابة «من سيبدأ العمل؟» وفي الورديات والهويات. اختر اسماً واضحاً يميّز الموظف.',
        speakText: 'اكتب اسم الموظف هنا.',
        ensureRouteId: AppContentRoutes.userForm,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.usersFormPin,
        title: 'رمز الدخول PIN',
        body:
            'رمز من 4 أرقام + تأكيد. يستخدمه الموظف عند اختيار حسابه في «من سيبدأ العمل؟». تجنّب الرموز الضعيفة مثل 1234. عند التعديل لاحقاً اتركه فارغاً إن لم تُرد تغييره.',
        speakText: 'عيّن رمز دخول من أربعة أرقام وأكّده.',
        ensureRouteId: AppContentRoutes.userForm,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.usersFormPerms,
        title: 'مستوى الصلاحية',
        body:
            'محدود: أساسي للبيع والصندوق. كامل: كل الشاشات تقريباً. تخصيص يدوي: تختار الصلاحيات واحدةً واحدة. هذا يحدّد ماذا يرى الموظف بعد الدخول.',
        speakText: 'اختر مستوى الصلاحية المناسب للموظف.',
        ensureRouteId: AppContentRoutes.userForm,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.usersFormSave,
        title: 'حفظ',
        body:
            'اضغط «حفظ». يظهر الحساب في القائمة وفي بوابة الدخول. غالباً تُفتح بعده بطاقة الهوية لعرض/طباعة الباركود. الفائدة: دخول منفصل وربطه بالوردية والصلاحيات دون مشاركة حساب المالك.',
        speakText: 'احفظ لإتمام إنشاء المستخدم.',
        ensureRouteId: AppContentRoutes.userForm,
        awaitTap: true,
      ),
    ],
  ),
  const GuideTour(
    id: GuideTourIds.usersIdentity,
    title: 'هويات الموظفين',
    description: 'عرض بطاقة الهوية ورمز الوردية',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.usersIdentityTitle,
        title: 'شاشة الهويات',
        body:
            'من «المستخدمين» → «هويات الموظفين». اختر موظفاً لتوسيع بطاقته: باركود وQR ورمز وردية. يمكن فتحها أيضاً من ⋮ → بطاقة الهوية في إدارة المستخدمين.',
        speakText: 'هذه شاشة هويات الموظفين. افتح بطاقة أي موظف لعرضها.',
        ensureRouteId: AppContentRoutes.employeeIdentity,
      ),
    ],
  ),
  const GuideTour(
    id: GuideTourIds.usersShifts,
    title: 'ورديات الموظفين',
    description: 'التقويم الأسبوعي للورديات',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.usersShiftsTitle,
        title: 'التقويم الأسبوعي',
        body:
            'من «المستخدمين» → «ورديات الموظفين (أسبوع)». أسبوع من السبت للجمعة مع أشرطة وقت الدخول/الخروج واسم الموظف. تنقّل بين الأسابيع لمتابعة الحضور. الورديات تُنشأ عند فتح وإغلاق الوردية اليومي.',
        speakText: 'هذه ورديات الأسبوع. تتابع أوقات عمل كل موظف.',
        ensureRouteId: AppContentRoutes.staffShiftsWeek,
      ),
    ],
  ),
];

GuideTour? usersStaffTourById(String id) {
  for (final tour in usersStaffTours) {
    if (tour.id == id) return tour;
  }
  return null;
}
