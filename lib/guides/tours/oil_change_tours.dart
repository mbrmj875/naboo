import '../guide_anchor.dart';
import '../guide_tour.dart';
import '../../navigation/content_navigation.dart';

/// جولات غيار الزيت — شرح عملي: ماذا تفعل هنا ولماذا يهم المحل.
final List<GuideTour> oilChangeTours = [
  GuideTour(
    id: GuideTourIds.oilFirstRun,
    title: 'تسجيل غيار زيت',
    description: 'من السجل إلى كل أقسام البطاقة ثم الحفظ وواتساب',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.hubNewCard,
        title: 'بطاقة غيار زيت جديدة',
        body:
            'كل زيارة غيار زيت تُسجَّل كبطاقة مستقلة: العميل، السيارة، الزيت، الدفع، وواتساب. اضغط هنا لفتح بطاقة جديدة وابدأ التسجيل.',
        speakText:
            'أهلاً بك. كل زيارة غيار تُسجَّل كبطاقة مستقلة. اضغط على زر بطاقة غيار زيت جديدة لنبدأ معاً.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
        awaitTap: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formCustomer,
        title: 'بطاقة بيانات العميل',
        body:
            'هنا بيانات الزبون. بدونها يصعب البحث لاحقاً، ولن تصل رسالة واتساب بعد الحفظ. التالي يشرح كل حقل ولماذا تحتاجه.',
        speakText:
            'هنا بيانات الزبون. بدونها يصعب البحث لاحقاً، ولن تصل رسالة واتس آب. اضغط التالي لمعرفة أهمية كل حقل.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formCustomerName,
        title: 'لماذا اسم العميل؟',
        body:
            'الاسم يظهر في السجل والبحث والفاتورة، ويُستخدم في رسالة واتساب («أهلاً فلان»). بدونه تبدو الزيارة مجهولة ويصعب تمييز الزبائن المتكررين.',
        speakText:
            'اكتب اسم العميل هنا. يظهر في السجل والفاتورة، ويُستخدم في رسالة واتس آب. بدونه يصعب تمييز الزبائن والبحث عنهم لاحقاً.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formCustomerPhone,
        title: 'لماذا رقم الواتساب؟',
        body:
            'هذا الرقم يُرسل إليه واتساب بعد الحفظ: ملخص الغيار، تذكير الزيارة القادمة، وطلب التقييم. بدون رقم صحيح لا تصل أي رسالة للزبون — حتى لو ربطت واتساب المحل.',
        speakText:
            'هنا رقم هاتف الزبون لواتس آب. بعد الحفظ تُرسل له رسالة الملخص والتذكير وطلب التقييم. بدون رقم صحيح لن تصل الرسالة، حتى لو كان واتس آب المحل مربوطاً.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formCar,
        title: 'بطاقة بيانات السيارة',
        body:
            'هنا تربط الزيارة بسيارة محددة. اللوحة والموديل يسهّلان الجلب التلقائي عند عودة نفس السيارة، وتجنّب الخلط بين سيارات الزبون.',
        speakText:
            'هنا بيانات السيارة. تربط الزيارة بسيارة محددة، وتسهّل جلب آخر زيارة عند عودة نفس اللوحة.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formPlate,
        title: 'لماذا رقم اللوحة؟',
        body:
            'اللوحة مفتاح السيارة في النظام. عند إدخالها قد تُجلب تلقائياً: اسم الزبون، الهاتف، نوع الزيت السابق، والعداد — فتوفّر وقتاً وتقلّل أخطاء الكتابة.',
        speakText:
            'رقم اللوحة مفتاح السيارة. عند إدخاله قد يُجلب تلقائياً اسم الزبون والهاتف ونوع الزيت السابق، فتوفّر الوقت وتقلّل الأخطاء.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formOil,
        title: 'بطاقة تغيير الزيت',
        body:
            'هنا جوهر الخدمة: العداد ونوع الزيت. منها يُحسب موعد الغيار القادم ويُبنى تذكير واتساب للزبون.',
        speakText:
            'هنا جوهر الخدمة: العداد ونوع الزيت. منها يُحسب موعد الغيار القادم وتذكير واتس آب.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formOdoCurrent,
        title: 'لماذا قراءة العداد؟',
        body:
            'القراءة الحالية أساس حساب الكيلومترات للغيار القادم. بدونها لا يقدر النظام على تذكير الزبون في الوقت المناسب، ويصعب معرفة متى يجب أن يعود.',
        speakText:
            'اكتب قراءة العداد الحالية. منها يُحسب موعد الغيار القادم. بدونها لا يصل تذكير واتس آب في الوقت المناسب.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formOilBrand,
        title: 'لماذا اسم الزيت واللزوجة؟',
        body:
            'يسجّل ما استُخدم فعلاً في هذه الزيارة. عند العودة تعرف ماذا وضعت سابقاً، وتتجنّب خلط الأنواع، ويظهر في الرسالة والسجل للمرجعية.',
        speakText:
            'اختر اسم الزيت واللزوجة. يُحفظ في السجل والرسالة، وعند عودة السيارة تعرف ماذا استخدمت سابقاً.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formExtras,
        title: 'متى تستخدم الإضافات؟',
        body:
            'افتحها فقط عند الحاجة: فلتر زيت، منتجات، هيدروليك الكير أو الباور، أو خدمات إضافية. تُضاف للمبلغ الإجمالي وتظهر في الفاتورة — لا تتركها فارغة إن بعت شيئاً مع الغيار.',
        speakText:
            'الإضافات اختيارية: فلاتر ومنتجات وهيدروليك. افتحها إذا بعت شيئاً مع الغيار، لأنها تدخل في الإجمالي والفاتورة.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formTechnician,
        title: 'لماذا الفني والملاحظات؟',
        body:
            'اسم الفني يربط البطاقة بمن نفّذ العمل: مفيد للمتابعة، تقييم الأداء، ومعرفة من المسؤول عند شكوى أو تقييم واتساب.\n\n'
            'الملاحظات للأمور الخاصة بهذه الزيارة: تسريب، صوت غريب، طلب الزبون، أو مشكلة تحتاج متابعة في الزيارة القادمة. بدون ملاحظات تضيع التفاصيل مع الوقت.',
        speakText:
            'اختر اسم الفني لربط البطاقة بمن نفّذ العمل، للمتابعة والتقييم عند الشكوى. وفي الملاحظات اكتب أي مشكلة أو ملاحظة خاصة، مثل تسريب أو طلب الزبون، حتى لا تُنسى في الزيارة القادمة.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formPayment,
        title: 'لماذا قسم الدفع؟',
        body:
            'هنا تتأكد أن المبلغ صحيح قبل الحفظ: الإجمالي، ما استلمه المحل، والمتبقي إن وُجد دين. أي خطأ هنا يؤثر على الصندوق والتقارير.',
        speakText:
            'راجع الإجمالي والمدفوع والمتبقي قبل الحفظ. أي خطأ هنا يؤثر على الصندوق والتقارير.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        allowInteract: true,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formSuspend,
        title: 'متى تعلّق الفاتورة؟',
        body:
            'إذا الزبون ينتظر أو العمل لم يكتمل (مثلاً ينقص فلتر أو لم يُدفع بعد)، علّق الفاتورة بدل إغلاقها ناقصة. تظهر لاحقاً في تبويب «المعلّقة» لتكملها دون فقدان البيانات.',
        speakText:
            'إذا العمل لم يكتمل بعد، استخدم تعليق الفاتورة. تظهر في تبويب المعلّقة لتكملها لاحقاً بدون فقدان البيانات.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formSave,
        title: 'ماذا يفعل حفظ وبيع؟',
        body:
            'يحفظ البطاقة في السجل، يحدّث المخزون والصندوق حسب الإعدادات، ويطلق إرسال واتساب للزبون إن كان الرقم مربوطاً والواتساب مفعّلاً. اضغطه فقط بعد مراجعة البيانات.',
        speakText:
            'حفظ وبيع يحفظ البطاقة، ويحدّث الصندوق، ويرسل واتس آب للزبون إن كان الرقم جاهزاً. اضغطه بعد مراجعة البيانات.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.hubPendingTab,
        title: 'فائدة تبويب المعلّقة',
        body:
            'كل بطاقة علّقتها تظهر هنا. منه تفتحها وتكمل الدفع أو الحفظ لاحقاً — مناسب لأوقات الذروة حتى لا تفقد الزيارة أو تعيد الكتابة من الصفر.',
        speakText:
            'تبويب المعلّقة يجمع البطاقات غير المكتملة. منه تكمل الدفع أو الحفظ لاحقاً بدون إعادة الكتابة.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
        action: 'oil.select_pending_tab',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.hubWhatsappConnect,
        title: 'لماذا ربط واتساب المحل؟',
        body:
            'هذا ربط مرة واحدة لرقم المحل. بدونه لن تخرج رسائل للزبائن حتى لو كتبت أرقامهم في البطاقة. بعد الربط تصل رسائل الملخص والتذكير والتقييم من رقم محلك.',
        speakText:
            'اربط واتس آب المحل مرة واحدة من هنا. بدونه لن تخرج رسائل للزبائن، حتى لو كتبت أرقامهم في البطاقة.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.hubSettings,
        title: 'ماذا تضبط في الإعدادات؟',
        body:
            'من هنا تختار: إرسال واتساب تلقائي بعد الحفظ أو يدوياً، وطلب تقييم الزبون بعد الخدمة. اضبطها حسب أسلوب عملك في المحل.',
        speakText:
            'من الإعدادات تختار إرسال واتس آب تلقائي أو يدوي بعد الحفظ، وهل تطلب تقييم الزبون بعد الخدمة.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
      ),
    ],
  ),
  GuideTour(
    id: GuideTourIds.oilWhatsapp,
    title: 'ربط وفصل واتساب',
    description: 'الطرق الثلاث + إعادة الربط وإلغاء الربط',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.hubWhatsappConnect,
        title: 'افتح شاشة الربط',
        body:
            'من أيقونة QR هنا تفتح شاشة ربط واتساب المحل. كل الرسائل للزبائن تعتمد على هذا الربط.',
        speakText:
            'من أيقونة كيو آر هنا تفتح شاشة ربط واتس آب المحل. كل الرسائل للزبائن تعتمد على هذا الربط. اضغط التالي.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.waStatus,
        title: 'حالة الربط الحالية',
        body:
            'إن ظهر «متصل» فالإرسال جاهز من رقم المحل أو رقم نابو حسب الطريقة. إن لم يكن متصلاً ستظهر لك بطاقات اختيار الطريقة.',
        speakText:
            'هذه حالة الربط. إذا كان متصلاً فالإرسال جاهز. إذا لم يكن متصلاً ستختار إحدى الطرق الثلاث. التالي لشرح الطرق.',
        ensureRouteId: AppContentRoutes.oilWhatsappConnect,
        action: 'wa.show_connected',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.waMethodIntro,
        title: 'ثلاث طرق للربط',
        body:
            'أمامك ثلاثة مسارات فقط: رقم نابو الرسمي (موصى به)، Meta مباشرة برقم محلك، أو مسح QR السريع. اختر حسب استقرارك واحتياجك.',
        speakText:
            'أمامك ثلاث طرق فقط لربط واتس آب. رقم نابو الرسمي موصى به، أو ميتا مباشرة برقم محلك، أو مسح كيو آر السريع. التالي لشرح كل طريقة.',
        ensureRouteId: AppContentRoutes.oilWhatsappConnect,
        action: 'wa.show_methods',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.waMethodNaboo,
        title: '١) رقم نابو الرسمي',
        body:
            'الرسائل تخرج من رقم نابو عبر Meta — بدون أن تربط رقم محلك. الأنسب للاستقرار والقوالب والتقييم، وموصى به لمعظم المحلات.',
        speakText:
            'الطريقة الأولى: الإرسال من رقم نابو الرسمي. الرسائل تخرج من رقم نابو عبر ميتا، بدون ربط رقم محلك. هي الأكثر استقراراً وموصى بها.',
        ensureRouteId: AppContentRoutes.oilWhatsappConnect,
        action: 'wa.show_methods',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.waMethodMeta,
        title: '٢) Meta مباشرة (رقمك)',
        body:
            'تربط رقم واتساب محلك رسمياً عبر Meta من داخل نابو. الإرسال والقوالب من رقمك أنت — يحتاج إكمال تسجيل Meta مرة واحدة.',
        speakText:
            'الطريقة الثانية: ربط رسمي عبر ميتا مباشرة. تربط رقم واتس آب محلك، فترسل القوالب من رقمك. تحتاج إكمال تسجيل ميتا مرة واحدة.',
        ensureRouteId: AppContentRoutes.oilWhatsappConnect,
        action: 'wa.show_methods',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.waMethodQr,
        title: '٣) مسح QR السريع',
        body:
            'امسح الرمز من واتساب → الأجهزة المرتبطة. أسرع للبدء، لكنه قد ينقطع أكثر من الرسمي. مناسب كخيار احتياطي وليس الأفضل دائماً.',
        speakText:
            'الطريقة الثالثة: ربط سريع بمسح كيو آر من واتس آب، الأجهزة المرتبطة. أسرع، لكنه قد ينقطع أكثر. استخدمه احتياطياً إن لزم.',
        ensureRouteId: AppContentRoutes.oilWhatsappConnect,
        action: 'wa.show_methods',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.waContinue,
        title: 'زر متابعة',
        body:
            'بعد اختيار الطريقة اضغط «متابعة» لإكمال الربط. في وضع الشرح لا ننفّذ الربط — فقط لتتعرّف على الزر.',
        speakText:
            'بعد اختيار الطريقة اضغط متابعة لإكمال الربط. الآن التالي لشرح الفصل وإعادة الربط.',
        ensureRouteId: AppContentRoutes.oilWhatsappConnect,
        action: 'wa.show_methods',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.waRelink,
        title: 'لماذا إعادة الربط؟',
        body:
            'استخدمها عند تغيير الرقم أو انقطاع الجلسة أو الانتقال لطريقة أخرى. تفصل الربط الحالي ثم تبدأ ربطاً جديداً — ويتطلب PIN المالك.',
        speakText:
            'إعادة الربط عند تغيير الرقم أو انقطاع الجلسة. تفصل الحالي ثم تبدأ ربطاً جديداً، وتتطلب رمز المالك.',
        ensureRouteId: AppContentRoutes.oilWhatsappConnect,
        action: 'wa.show_connected',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.waDisconnect,
        title: 'لماذا إلغاء الربط؟',
        body:
            'يوقف إرسال واتساب من المحل على كل الأجهزة حتى تعيد الربط. لا تستخدمه إلا عند الحاجة — ويتطلب PIN المالك لحماية المحل.',
        speakText:
            'إلغاء الربط يوقف إرسال واتس آب على كل الأجهزة حتى تعيد الربط. لا تستخدمه إلا عند الحاجة، ويتطلب رمز المالك.',
        ensureRouteId: AppContentRoutes.oilWhatsappConnect,
        action: 'wa.show_connected',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.waTips,
        title: 'ملاحظات مهمة',
        body:
            'الرسمي أكثر استقراراً، وQR احتياطي. الربط للحساب كله مرة واحدة، ولا تعِد الربط من جهاز ثانٍ بلا داعٍ حتى لا تفصل الجلسة عن الجميع.',
        speakText:
            'تذكر: الرسمي أكثر استقراراً، وكيو آر احتياطي. الربط مرة واحدة للحساب كله. ولا تضغط إعادة الربط من جهاز آخر بلا سبب حتى لا ينفصل عن الجميع.',
        ensureRouteId: AppContentRoutes.oilWhatsappConnect,
        action: 'wa.show_connected',
      ),
    ],
  ),
  GuideTour(
    id: GuideTourIds.oilPendingTab,
    title: 'الفواتير المعلّقة',
    description: 'تبويب المعلّقة في السجل',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.hubPendingTab,
        title: 'فائدة المعلّقة',
        body:
            'هنا البطاقات التي علّقتها قبل اكتمال البيع. افتح أي بطاقة وأكمل الدفع أو الحفظ — مفيد عندما يكون الزبون ينتظر أو ينقص صنف.',
        speakText:
            'تبويب المعلّقة للبطاقات غير المكتملة. افتح البطاقة وأكمل الدفع أو الحفظ لاحقاً.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
        action: 'oil.select_pending_tab',
      ),
    ],
  ),
  GuideTour(
    id: GuideTourIds.oilPlateAutofill,
    title: 'جلب بيانات اللوحة',
    description: 'حقل رقم اللوحة',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.formCar,
        title: 'بيانات السيارة',
        body:
            'عند تكرار زيارة نفس السيارة، رقم اللوحة هو أسرع طريق لجلب بياناتها السابقة بدل إعادة الكتابة.',
        speakText:
            'رقم اللوحة أسرع طريقة لجلب بيانات السيارة السابقة عند تكرار الزيارة.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.formPlate,
        title: 'أدخل اللوحة للجلب',
        body:
            'أدخل اللوحة هنا. إن وُجدت زيارة سابقة قد يُعبَّأ الاسم والهاتف ونوع الزيت تلقائياً — راجعها ثم أكمل العداد والدفع.',
        speakText:
            'أدخل رقم اللوحة هنا. إن وُجدت زيارة سابقة قد تُجلب البيانات تلقائياً. راجعها ثم أكمل.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        allowInteract: true,
      ),
    ],
  ),
  GuideTour(
    id: GuideTourIds.oilHubSettings,
    title: 'إعدادات غيار الزيت',
    description: 'لوحة مفاتيح السجل: مخزون وواتساب وتقييم',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.hubSettings,
        title: 'افتح إعدادات غيار الزيت',
        body:
            'من أيقونة الضبط هنا تُفتح لوحة إعدادات تشغيل غيار الزيت: صرف المخزون وواتساب والتقييم.',
        speakText:
            'من أيقونة الضبط تفتح إعدادات غيار الزيت. التالي لشرح كل مفتاح.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.settingsStockOil,
        title: 'صرف الزيت من المخزون',
        body:
            'عند التشغيل يخصم لترات الزيت من عائلة المخزون عند الحفظ. عند الإيقاف يبقى التسجيل يدوياً بلا خصم.',
        speakText:
            'صرف الزيت من المخزون: عند التشغيل يخصم اللترات عند الحفظ. عند الإيقاف تسجيل بلا خصم.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
        action: 'oil.open_hub_settings',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.settingsStockHydraulic,
        title: 'صرف الهيدروليك من المخزون',
        body:
            'نفس الفكرة للهيدروليك: خصم لترات من عائلات المخزون عند الحفظ إن كان مفعّلاً.',
        speakText:
            'صرف الهيدروليك من المخزون يعمل بنفس فكرة الزيت لعائلات الهيدروليك.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
        action: 'oil.open_hub_settings',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.settingsWaAuto,
        title: 'إرسال تلقائي للزبون',
        body:
            'بعد حفظ بطاقة جديدة تُرسل الرسالة من رقم المحل دون فتح واتساب. يحتاج ربطاً ناجحاً ورقم زبون.',
        speakText:
            'الإرسال التلقائي يرسل رسالة واتس آب بعد الحفظ من رقم المحل. يحتاج ربطاً ورقم زبون.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
        action: 'oil.open_hub_settings',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.settingsWaManual,
        title: 'فتح واتساب يدوياً',
        body:
            'يفتح واتساب برسالة جاهزة بعد الحفظ. متعارض مع التلقائي — اختر أسلوباً واحداً.',
        speakText:
            'الفتح اليدوي يفتح واتس آب برسالة جاهزة. لا يجتمع مع الإرسال التلقائي.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
        action: 'oil.open_hub_settings',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.settingsWaRating,
        title: 'طلب تقييم في الرسالة',
        body:
            'يُلحق دعوة تقييم من 1 إلى 10 أو ملاحظة قصيرة بنهاية رسالة واتساب.',
        speakText:
            'طلب التقييم يضيف دعوة تقييم في نهاية رسالة واتس آب للزبون.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
        action: 'oil.open_hub_settings',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.settingsWaConnect,
        title: 'ربط واتساب المحل',
        body:
            'من هنا تنتقل لشاشة الربط (رقم نابو أو Meta أو QR). بدونه لن تخرج رسائل للزبائن.',
        speakText:
            'من صف ربط واتساب المحل تفتح شاشة الربط. بدونه لا تخرج رسائل للزبائن.',
        ensureRouteId: AppContentRoutes.oilServicesLog,
        action: 'oil.open_hub_settings',
      ),
    ],
  ),
  GuideTour(
    id: GuideTourIds.oilCatalogOil,
    title: 'كتالوج الزيت واللزوجات',
    description: 'إضافة ماركة ولزوجة للأسعار على البطاقة',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.formOilCatalogBtn,
        title: 'زر كتالوج الزيت',
        body:
            'من هنا تضيف أسماء زيوت ولزوجات بأسعار البيع/لتر لتختارها لاحقاً في البطاقة. هذا كتالوج أسعار وليس مخزون العائلات.',
        speakText:
            'زر إضافة كتالوج الزيت بجانب حقل الماركة. منه تضيف لزوجات وأسعارها للبطاقة.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.catalogOilTitle,
        title: 'ورقة كتالوج الزيت',
        body:
            'هنا قائمة الماركات واللزوجات. أضف صنفاً مرة واحدة ثم اختره من القوائم في البطاقة.',
        speakText:
            'هذه ورقة كتالوج الزيت واللزوجات. أضف الماركة واللزوجة والسعر ثم اخترها في البطاقة.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        action: 'oil.open_oil_catalog',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.catalogOilAdd,
        title: 'إضافة زيت أو لزوجة',
        body:
            'اضغط «إضافة زيت / لزوجة» لتسجيل ماركة ولزوجة وسعر بيع لكل لتر. السعر الأساسي لتبديل الزيت يُضبط من شاشة الخدمات وليس هنا.',
        speakText:
            'من زر الإضافة تسجّل ماركة ولزوجة وسعر اللتر. سعر تبديل الزيت الأساسي من شاشة الخدمات.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        action: 'oil.open_oil_catalog',
      ),
    ],
  ),
  GuideTour(
    id: GuideTourIds.oilCatalogFilter,
    title: 'كتالوج الفلاتر',
    description: 'أسعار فلاتر المحرك والهواء والكير',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.formFilterCatalogBtn,
        title: 'زر كتالوج الفلاتر',
        body:
            'من قسم الإضافات في البطاقة تضيف أسعار فلاتر المحرك أو الهواء أو الكير للكتالوج.',
        speakText:
            'زر إضافة كتالوج الفلاتر في قسم الإضافات. منه تدير أسعار الفلاتر.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        action: 'oil.expand_extras',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.catalogFilterTitle,
        title: 'ورقة كتالوج الفلاتر',
        body:
            'أضف اسم الفلتر وفئته وسعره. عند البيع تختاره من البطاقة فيدخل الإجمالي.',
        speakText:
            'كتالوج الفلاتر لإضافة الاسم والفئة والسعر ثم اختياره في البطاقة.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        action: 'oil.open_filter_catalog',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.catalogFilterAdd,
        title: 'إضافة فلتر',
        body: 'استخدم زر الإضافة لتسجيل فلتر جديد بسعره في الكتالوج.',
        speakText: 'من زر الإضافة تسجّل فلترًا جديدًا بسعره.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        action: 'oil.open_filter_catalog',
      ),
    ],
  ),
  GuideTour(
    id: GuideTourIds.oilCatalogHydraulic,
    title: 'كتالوج الهيدروليك',
    description: 'ماركة ودرجة وسعر هيدروليك',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.formHydraulicCatalogBtn,
        title: 'زر كتالوج الهيدروليك',
        body:
            'من قسم الهيدروليك في البطاقة تضيف ماركة ودرجة وسعر بيع/لتر للاختيار لاحقاً.',
        speakText:
            'زر إضافة كتالوج الهيدروليك بجانب حقول الهيدروليك في البطاقة.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        action: 'oil.expand_extras',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.catalogHydraulicTitle,
        title: 'ورقة كتالوج الهيدروليك',
        body:
            'هنا تدير درجات الهيدروليك وأسعارها. لخصم المخزون فعّل صرف الهيدروليك وجهّز عائلات المخزون من المنتجات.',
        speakText:
            'كتالوج الهيدروليك للدرجات والأسعار. خصم المخزون يحتاج تفعيل الصرف وعائلات المنتجات.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        action: 'oil.open_hydraulic_catalog',
      ),
      GuideStep(
        anchorId: OilGuideAnchors.catalogHydraulicAdd,
        title: 'إضافة هيدروليك',
        body: 'أضف ماركة ودرجة وسعر اللتر من زر الإضافة.',
        speakText: 'من زر الإضافة تسجّل ماركة هيدروليك ودرجة وسعر اللتر.',
        ensureRouteId: AppContentRoutes.oilChangeCreate,
        action: 'oil.open_hydraulic_catalog',
      ),
    ],
  ),
  GuideTour(
    id: GuideTourIds.oilServicesBase,
    title: 'الخدمات والسعر الأساسي',
    description: 'سعر تبديل الزيت والخدمات الإضافية',
    steps: [
      GuideStep(
        anchorId: OilGuideAnchors.servicesBasePrice,
        title: 'سعر تبديل الزيت الأساسي',
        body:
            'هذا مبلغ ثابت يُضاف لكل بطاقة غيار جديدة. يختلف عن سعر اللتر في كتالوج الماركات.',
        speakText:
            'سعر تبديل الزيت الأساسي يُضاف لكل بطاقة جديدة، وهو غير سعر لتر الماركة في الكتالوج.',
        ensureRouteId: AppContentRoutes.oilChangeServices,
      ),
      GuideStep(
        anchorId: OilGuideAnchors.servicesExtrasList,
        title: 'خدمات إضافية',
        body:
            'هنا كتالوج خدمات بأسماء وأسعار تختارها داخل البطاقة عند الحاجة.',
        speakText:
            'الخدمات الإضافية كتالوج تُختار من البطاقة عند الحاجة.',
        ensureRouteId: AppContentRoutes.oilChangeServices,
      ),
    ],
  ),
];

GuideTour? oilChangeTourById(String id) {
  for (final tour in oilChangeTours) {
    if (tour.id == id) return tour;
  }
  return null;
}
