# جرد مسارات التطبيق والروابط العميقة (Routes & Deep Links Inventory)

**حالة الوثيقة:** عقد مُجمّد (Frozen Contract).
**الغرض:** يمنع منعاً باتاً كسر أو تغيير أسماء هذه المسارات أو توقيع المعطيات (Arguments) أو بروتوكول الروابط العميقة أثناء ترحيل الشاشات في عملية إعادة الهيكلة (Adaptive UI).

---

## 1. المسارات الأساسية (Named Routes)
هذه المسارات مسجلة في `lib/main.dart` ولا يجوز تغييرها:

| المسار (Route) | الشاشة المربوطة (Screen) | المعطيات (Arguments) المتوقعة |
| :--- | :--- | :--- |
| `/` | `_LicenseAwareRoot` | `null` |
| `/login` | `LoginScreen` | `null` |
| `/home` | `HomeScreen` | `null` |
| `/open-shift` | `OpenShiftScreen` | `null` |
| `/onboarding` | `BusinessSetupWizardScreen` | `null` |
| `/dev/stress` | `StressToolsScreen` | `null` |

---

## 2. الروابط العميقة (Deep Links Protocol)
تتم معالجتها من خلال باقة `app_links` ويتم الاستماع لها في `InvoiceDeepLinkListener`. يجب عدم كسر التوقيع أو الهيكلة (URL Scheme & Host).

| الوظيفة | بروتوكول الرابط (URI Protocol) | المعلمات (Parameters) | الإجراء (Action) |
| :--- | :--- | :--- | :--- |
| **فواتير المبيعات / الأقساط** | `basrainvoice://invoice/{id}` | `id` (int): يمثل المعرف الفريد للفاتورة. | يعرض نافذة/شاشة تفاصيل الفاتورة عبر `showInvoiceDetailSheet` |
| **ديون / حسابات العملاء** | `basrainvoice://customer-debt/{id}` | `id` (int): يمثل المعرف الفريد للعميل `registeredCustomerId`. | يعرض شاشة `CustomerDebtDetailScreen` |

---

## 3. الشاشات الديناميكية الحرجة (Dynamic Pushed Routes)
هذه الشاشات تُفتح عبر `Navigator.push` أو يتم تضمينها مستقبلاً في شاشات مزدوجة (Master-Detail). العقد هنا هو **توقيع منشئ الفئة (Constructor Arguments)** الذي يجب ألا يتم حذفه لتظل الشاشات قابلة للاستدعاء من أي مكان.

| الشاشة الهدف (Target Screen) | المعطيات المطلوبة إجبارياً (Required Arguments) | الاستخدام المتوقع في الـ Adaptive UI |
| :--- | :--- | :--- |
| `ProductDetailScreen` | `required int productId` | قد تُفتح كشاشة منفصلة (موبايل) أو تُعرض في النصف الأيسر (تابلت/كمبيوتر). |
| `CustomerDebtDetailScreen` | `required int registeredCustomerId` | يتم استدعاؤها من قائمة العملاء أو من رابط عميق (Deep Link). |
| `InvoiceDetailScreen` / `Sheet` | `required int invoiceId` | قد تُفتح فوق قائمة الفواتير أو داخلها كـ Detail. |
| `ServiceOrderDetailScreen` | `required int serviceOrderId` | تُعرض بجانب قائمة طلبات الصيانة في الكمبيوتر. |

> **ملاحظة للمطور:**
> تغيير اسم المسار الثابت، أو تغيير الـ Scheme، أو إزالة المعطيات الإلزامية في أي Constructor لشاشة رئيسية يعتبر **كسراً للعقد (Contract Violation)** ويُرفض الـ PR فوراً. تأكد أن كل شاشة (Detail) يمكن أن تستقبل الـ ID بنفس الكفاءة وتجلب بياناتها داخلياً.
