/// نص توقف الربط من whatsapp_onboarding_state، بلا أي نص خام من Meta.
abstract class WhatsappOnboardingCopy {
  WhatsappOnboardingCopy._();

  static const _byError = <String, String>{
    'phone_register_failed':
        'لم نتمكن من تسجيل الرقم عند Meta. إن كان الرقم محميًا برمز تحقق بخطوتين، أزله ثم أعد المحاولة.',
    'webhook_subscription_failed':
        'تم التفويض، لكن استقبال الرسائل لم يكتمل. أعد المحاولة.',
    'ambiguous_assets':
        'في حسابك أكثر من رقم أو حساب واتساب. أعد الربط واختر الحساب المطلوب داخل Meta.',
    'meta_waba_rate_limited':
        'أوقفت Meta القراءة مؤقتًا بسبب كثرة المحاولات. انتظر ساعة ثم أعد الربط مرة واحدة.',
    'missing_waba_or_phone':
        'لم تصلنا بيانات الرقم من Meta. أكمل كل خطوات النافذة ثم أعد المحاولة.',
    'phone_not_verified': 'لم تؤكد Meta هذا الرقم، فلم نكمل الربط. أعد الربط.',
    'shared_sender_unverified':
        'تعذّر التأكد من رقم نابو عند Meta الآن، ولم يتغير شيء في ربطك. أعد المحاولة بعد قليل.',
  };

  static const _generic = 'لم يكتمل الربط. أعد المحاولة، وإن تكرر فراسل الدعم.';

  /// null عندما لا يوجد توقف يستحق الشرح.
  static String? stopReasonAr({String? step, String? errorCode}) {
    if (step == 'meta_opened') {
      return 'لم يكتمل الربط، ولم يتغير شيء في رقمك.';
    }
    if (step != 'failed') return null;
    final code = (errorCode ?? '').trim();
    if (code.contains('oauth')) {
      return 'انتهت جلسة التفويض أو لم تكتمل. أعد الربط من التطبيق.';
    }
    return _byError[code] ?? _generic;
  }
}
