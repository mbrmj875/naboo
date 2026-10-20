import '../guide_anchor.dart';
import '../guide_tour.dart';
import '../../navigation/content_navigation.dart';

/// جولات إضافة منتج وأنواع المخزون الأساسي والتسعير.
final List<GuideTour> inventoryProductTours = [
  const GuideTour(
    id: GuideTourIds.productAddOverview,
    title: 'إضافة منتج جديد',
    description: 'من القائمة إلى بيانات المنتج وشرح نوع المخزون',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.productListTitle,
        title: 'قائمة المنتجات',
        body:
            'من المخزون → قائمة المنتجات. هنا كتالوج بضاعتك: بحث، تعديل، وإضافة منتج جديد.',
        speakText: 'هذه قائمة المنتجات. منها تضيف منتجاً جديداً.',
        ensureRouteId: AppContentRoutes.inventoryProducts,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productListAddCta,
        title: 'منتج جديد',
        body:
            'اضغط «+ منتج جديد» لفتح نموذج الإضافة. سنشرح كل خانة: ماذا تعني وهل هي مهمة.',
        speakText: 'اضغط منتج جديد لفتح النموذج.',
        ensureRouteId: AppContentRoutes.inventoryProducts,
        awaitTap: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormName,
        title: 'اسم المنتج (إلزامي)',
        body:
            'مهم جداً: يظهر في البيع والبحث والفواتير. اختر اسماً واضحاً يميّز الصنف عن غيره.',
        speakText: 'اكتب اسم المنتج هنا. هذا الحقل إلزامي.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormDescription,
        title: 'الوصف (اختياري مفيد)',
        body:
            'ليس شرط البيع، لكنه يوضح للموظفين المواصفات أو ملاحظات الاستخدام. اتركه فارغاً إن لم تحتج.',
        speakText: 'الوصف اختياري. اكتبه إن أردت توضيحاً للموظفين.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormImage,
        title: 'صورة المنتج (اختياري قوي)',
        body:
            'تسرّع التعرف عند البيع. إن لم يظهر الحقل فالسياسة أخفته من إعدادات شاشة الإضافة.',
        speakText: 'الصورة اختيارية وتساعد عند البيع.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormCategory,
        title: 'التصنيف (مهم عملياً)',
        body:
            'يرتب المنتجات للتصفية والتقارير. بدون تصنيف يصعب البحث لاحقاً. اكتب أو اختر من القائمة.',
        speakText: 'اختر أو اكتب التصنيف. مهم لتنظيم القائمة.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormBrand,
        title: 'الماركة (مفيدة)',
        body:
            'تميّز المنتجات المتشابهة. شبه مهمة لعائلات الزيت والهيدروليك لأن اسم العائلة/الماركة يربط الدرجات.',
        speakText: 'أدخل الماركة إن وجدت. مفيدة خصوصاً للزيوت.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormWarehouse,
        title: 'المخزن',
        body:
            'مهم إن لديك أكثر من مخزن: يحدد أين يُحسب الرصيد. مع مخزن واحد اختره أو اتركه حسب سياستك.',
        speakText: 'اختر المخزن إن كان لديك أكثر من مستودع.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormStockType,
        title: 'نوع المخزون الأساسي (الأهم)',
        body:
            'يحدد شكل الكمية والتسعير: عدد بالقطعة، حجم باللتر، عائلة هيدروليك بدرجات، أو عائلة زيت بلزوجات. غيّره قبل ملء الأسعار والكميات. بعدها استخدم جولات التنفيذ لكل نوع.',
        speakText:
            'نوع المخزون هو الأهم: عدد أو حجم أو عائلة هيدروليك أو عائلة زيت.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormSupplier,
        title: 'المورد (اختياري تشغيلي)',
        body:
            'يسهّل الشراء وإعادة الطلب وليس شرط البيع اليومي. كود المورد اختياري إضافي.',
        speakText: 'المورد اختياري لتسهيل المشتريات.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
    ],
  ),
  const GuideTour(
    id: GuideTourIds.productStockCount,
    title: 'منتج بالعدد (قطعة)',
    description: 'تنفيذ عملي: نوع عدد + تسعير + كمية',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.productFormStockType,
        title: 'اختر: عدد (قطعة)',
        body:
            'مناسب لفلتر أو قطعة غيار أو أي صنف يُباع بالقطعة. سيتم ضبط النوع تلقائياً إن لزم، أو اختره من القائمة.',
        speakText: 'اختر نوع المخزون عدد قطعة.',
        ensureRouteId: AppContentRoutes.addProduct,
        action: 'product.set_stock_type_count',
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormName,
        title: 'سمِّ المنتج',
        body: 'اكتب اسماً واضحاً لهذا الصنف بالقطعة.',
        speakText: 'اكتب اسم المنتج.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormPricing,
        title: 'التسعير على المنتج',
        body:
            'لمنتج العدد: سعر الشراء وسعر البيع (وأقل سعر إن لزم) على بطاقة التسعير مباشرة.',
        speakText: 'أدخل أسعار الشراء والبيع هنا.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormTrackInventory,
        title: 'تتبع المخزون',
        body:
            'شغّله لتسجيل الكميات مع البيع والشراء. عند الإيقاف لا تُحسب كمية لهذا المنتج.',
        speakText: 'فعّل تتبع المخزون إن أردت رصيداً.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormQty,
        title: 'الكمية وتنبيه النفاد',
        body:
            'أدخل الكمية بالقطعة وحدّ التنبيه. يمكنك الحفظ لاحقاً؛ البيانات التجريبية قابلة للتعديل.',
        speakText: 'أدخل الكمية وحد التنبيه.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormSave,
        title: 'حفظ المنتج',
        body:
            'عند الجاهزية اضغط «حفظ المنتج». يمكنك تعديل الصنف لاحقاً من قائمة المنتجات.',
        speakText: 'احفظ المنتج عند الانتهاء.',
        ensureRouteId: AppContentRoutes.addProduct,
        awaitTap: true,
      ),
    ],
  ),
  const GuideTour(
    id: GuideTourIds.productStockVolume,
    title: 'منتج بالحجم (لتر)',
    description: 'تنفيذ عملي: زيت مفرد باللتر ووحدات إضافية',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.productFormStockType,
        title: 'اختر: حجم (لتر)',
        body:
            'لمنتج سائل واحد يُباع باللتر و/أو بالعلبة عبر وحدات إضافية. ليس عائلة لزوجات متعددة.',
        speakText: 'اختر حجم لتر كأساس.',
        ensureRouteId: AppContentRoutes.addProduct,
        action: 'product.set_stock_type_volume',
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormName,
        title: 'اسم المنتج باللتر',
        body: 'مثال: زيت معين بحجم واحد وليس عائلة بلزوجات متعددة.',
        speakText: 'اكتب اسم المنتج.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormExtraUnits,
        title: 'وحدات البيع الإضافية',
        body:
            'أضف لتر (معامل 1) وعلبة (مثال معامل 5) إن بعت بالعلبة. كل وحدة لها سعر وباركود اختياري.',
        speakText: 'أضف وحدات البيع مثل اللتر والعلبة.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormPricing,
        title: 'التسعير',
        body: 'سعر الشراء والبيع للأساس باللتر؛ أسعار الوحدات الإضافية في صفوف الوحدات إن وُجدت.',
        speakText: 'راجع أسعار الشراء والبيع.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormQty,
        title: 'الكمية باللتر',
        body: 'الرصيد يُحسب بأساس اللتر. عيّن الكمية وتنبيه الحد الأدنى.',
        speakText: 'أدخل الكمية باللتر.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormSave,
        title: 'حفظ',
        body: 'احفظ عند الانتهاء. يمكن التعديل لاحقاً من القائمة.',
        speakText: 'احفظ المنتج.',
        ensureRouteId: AppContentRoutes.addProduct,
        awaitTap: true,
      ),
    ],
  ),
  const GuideTour(
    id: GuideTourIds.productStockHydraulic,
    title: 'عائلة هيدروليك',
    description: 'تنفيذ عملي: درجات وعبوات هيدروليك',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.productFormStockType,
        title: 'اختر: هيدروليك — عائلة',
        body:
            'منتج أب (ماركة/عائلة) مع درجات وعبوات متعددة. الأسعار على جدول الدرجات وليس بطاقة التسعير الرئيسية.',
        speakText: 'اختر هيدروليك عائلة.',
        ensureRouteId: AppContentRoutes.addProduct,
        action: 'product.set_stock_type_hydraulic',
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormBrand,
        title: 'الماركة / اسم العائلة',
        body: 'اربط العائلة بماركة واضحة ثم عبّئ درجات الهيدروليك أدناه.',
        speakText: 'أدخل الماركة أو اسم العائلة.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormFluidGrades,
        title: 'درجات وعبوات الهيدروليك',
        body:
            'أضف درجة واحدة على الأقل مع عبوات وأسعار الشراء/البيع لكل درجة. هذا بديل بطاقة التسعير العادية.',
        speakText: 'عبّئ جدول درجات الهيدروليك والأسعار.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormPricing,
        title: 'بطاقة التسعير',
        body:
            'لعائلة الهيدروليك تظهر هنا ملاحظة فقط — الأسعار الحقيقية في الجدول أعلاه.',
        speakText: 'التسعير التفصيلي في جدول الدرجات.',
        ensureRouteId: AppContentRoutes.addProduct,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormSave,
        title: 'حفظ العائلة',
        body: 'احفظ لإنشاء العائلة ودرجاتها. راجع القائمة بعد الحفظ.',
        speakText: 'احفظ عائلة الهيدروليك.',
        ensureRouteId: AppContentRoutes.addProduct,
        awaitTap: true,
      ),
    ],
  ),
  const GuideTour(
    id: GuideTourIds.productStockOil,
    title: 'عائلة زيت',
    description: 'تنفيذ عملي: لزوجات وعبوات زيت',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.productFormStockType,
        title: 'اختر: زيت — عائلة',
        body:
            'ماركة زيت مع عدة لزوجات وعبوات. الأسعار لكل لزوجة في الجدول؛ ليست على بطاقة التسعير الرئيسية.',
        speakText: 'اختر زيت عائلة.',
        ensureRouteId: AppContentRoutes.addProduct,
        action: 'product.set_stock_type_oil',
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormBrand,
        title: 'ماركة الزيت',
        body: 'اسم العائلة/الماركة التي ستظهر مع اللزوجات.',
        speakText: 'أدخل ماركة الزيت.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormFluidGrades,
        title: 'اللزوجات والعبوات',
        body:
            'أضف اللزوجات (مثل 5W-30) وعبوات البيع وأسعار كل صف. هذا قلب عائلة الزيت.',
        speakText: 'عبّئ اللزوجات والعبوات والأسعار.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormPricing,
        title: 'ملاحظة التسعير',
        body: 'بطاقة التسعير هنا تلميح فقط — الأسعار في جدول اللزوجات.',
        speakText: 'الأسعار في جدول اللزوجات أعلاه.',
        ensureRouteId: AppContentRoutes.addProduct,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormSave,
        title: 'حفظ عائلة الزيت',
        body: 'احفظ لإنشاء العائلة. يمكن التعديل لاحقاً من المنتجات.',
        speakText: 'احفظ عائلة الزيت.',
        ensureRouteId: AppContentRoutes.addProduct,
        awaitTap: true,
      ),
    ],
  ),
  const GuideTour(
    id: GuideTourIds.productPricingInventory,
    title: 'التسعير وإدارة المخزون',
    description: 'شرح خانات التسعير والتتبع والكمية',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.productFormPricing,
        title: 'بطاقة التسعير',
        body:
            'سعر الشراء، سعر البيع، الضريبة/الخصم إن فُعّلا، وأقل سعر بيع لحماية هامشك. لعائلات الزيت/الهيدروليك الأسعار على الدرجات لا هنا.',
        speakText: 'راجع حقول التسعير ومعانيها.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormTrackInventory,
        title: 'تتبع المخزون',
        body:
            'مهم: يشغّل خصم/زيادة الرصيد مع العمليات. أوقفه فقط لمنتج لا تريد تتبع كميته.',
        speakText: 'هذا مفتاح تتبع المخزون.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormQty,
        title: 'الكمية',
        body: 'الرصيد الابتدائي بوحدة الأساس (قطعة أو لتر). لا يظهر بنفس الشكل لكل عائلات السوائل ذات الدرجات.',
        speakText: 'أدخل الكمية في المخزون.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormLowStock,
        title: 'تنبيه النفاد',
        body: 'عندما يقل الرصيد عن هذا الحد يظهر تنبيه لإعادة الطلب.',
        speakText: 'عيّن حد التنبيه.',
        ensureRouteId: AppContentRoutes.addProduct,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.productFormSave,
        title: 'حفظ',
        body: 'احفظ بعد مراجعة التسعير والمخزون.',
        speakText: 'احفظ المنتج.',
        ensureRouteId: AppContentRoutes.addProduct,
        awaitTap: true,
      ),
    ],
  ),
];

GuideTour? inventoryProductTourById(String id) {
  for (final tour in inventoryProductTours) {
    if (tour.id == id) return tour;
  }
  return null;
}
