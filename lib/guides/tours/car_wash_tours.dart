import '../guide_anchor.dart';
import '../guide_tour.dart';
import '../../navigation/content_navigation.dart';

/// جولات غسيل السيارات — الرئيسية، إظهار الزر، وتسجيل بطاقة.
final List<GuideTour> carWashTours = [
  GuideTour(
    id: GuideTourIds.carWashHome,
    title: 'زر غسيل السيارات',
    description: 'مكان البطاقة على الرئيسية وكيف تفتحها',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.homeCarWashCta,
        title: 'غسيل السيارات على الرئيسية',
        body:
            'هذا الزر تحت «غيار زيت جديد». منه تفتح بطاقة غسيل سريعة: لوحة، أنواع الغسيل، والدفع. إن لم يظهر الزر ففعّله من تخصيص الشاشة الرئيسية.',
        speakText:
            'زر غسيل السيارات على الرئيسية تحت غيار زيت جديد. اضغطه لفتح بطاقة غسيل. إن اختفى، فعّله من تخصيص الشاشة الرئيسية.',
        ensureRouteId: AppContentRoutes.home,
      ),
    ],
  ),
  GuideTour(
    id: GuideTourIds.carWashVisibility,
    title: 'إظهار أو إخفاء زر الغسيل',
    description: 'مفتاح زر غسيل السيارات في تخصيص الرئيسية',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.settingsCarWashToggle,
        title: 'زر غسيل السيارات',
        body:
            'من هنا تُظهر أو تُخفي زر «غسيل السيارات» على الرئيسية. الإيقاف يخفي الاختصار فقط ولا يحذف أنواع الغسيل أو الفواتير.',
        speakText:
            'هذا مفتاح زر غسيل السيارات. أوقفه لإخفائه من الرئيسية، أو شغّله ليظهر تحت غيار زيت جديد.',
        ensureRouteId: AppContentRoutes.settingsDashboardLayout,
        allowInteract: true,
      ),
    ],
  ),
  GuideTour(
    id: GuideTourIds.carWashCreate,
    title: 'تسجيل غسيل سيارة',
    description: 'من البطاقة: لوحة وأنواع الغسيل ثم حفظ',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.homeCarWashCta,
        title: 'افتح بطاقة الغسيل',
        body: 'من الرئيسية اضغط «غسيل السيارات» لفتح بطاقة جديدة.',
        speakText: 'من الرئيسية اضغط غسيل السيارات لفتح البطاقة.',
        ensureRouteId: AppContentRoutes.home,
        awaitTap: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.carWashFormPlate,
        title: 'رقم اللوحة',
        body: 'أدخل لوحة السيارة هنا لربط الزيارة والبحث لاحقاً.',
        speakText: 'اكتب رقم اللوحة هنا.',
        ensureRouteId: AppContentRoutes.carWashCreate,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.carWashFormServices,
        title: 'أنواع الغسيل',
        body:
            'اختر نوع أو أكثر من الكتالوج. لإضافة أنواع وأسعار جديدة استخدم «أنواع الغسيل وأسعارها».',
        speakText:
            'اختر أنواع الغسيل من القائمة. لإضافة أسعار جديدة ادخل أنواع الغسيل وأسعارها.',
        ensureRouteId: AppContentRoutes.carWashCreate,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.carWashFormSave,
        title: 'حفظ وبيع',
        body: 'بعد مراجعة الإجمالي والمدفوع اضغط حفظ وبيع لإقفال البطاقة.',
        speakText: 'راجع المبلغ ثم احفظ وبع لإقفال بطاقة الغسيل.',
        ensureRouteId: AppContentRoutes.carWashCreate,
      ),
    ],
  ),
];

GuideTour? carWashTourById(String id) {
  for (final tour in carWashTours) {
    if (tour.id == id) return tour;
  }
  return null;
}
