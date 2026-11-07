/** نصوص بريد صاحب الحساب. دوال نقية بلا شبكة. */

import { renderNabooEmail } from './owner_email_card.ts';

export type OwnerEmailCard = {
  subject: string;
  text: string;
  html: string;
};

function card(
  subject: string,
  title: string,
  badge: string,
  paragraphs: string[],
  ltrLines?: string[],
): OwnerEmailCard {
  const rendered = renderNabooEmail({ title, badge, paragraphs, ltrLines });
  return { subject, text: rendered.text, html: rendered.html };
}

function hello(name: string | null | undefined): string | null {
  const n = String(name ?? '').trim();
  if (!n || n.includes('@')) return null;
  return `مرحباً ${n}.`;
}

export function welcomeEmailCopy(args: {
  channel: 'email' | 'google';
  displayName?: string | null;
  recreated: boolean;
  previousTrialStartedAt?: string | null;
}): OwnerEmailCard {
  const greet = hello(args.displayName);
  const lines: string[] = [];
  if (greet) lines.push(greet);

  if (args.recreated) {
    lines.push(
      'أُنشئ حساب نابو من جديد على هذا البريد. بيانات الحساب السابق المحذوف لا تعود مع هذه الرسالة.',
    );
    lines.push(
      args.channel === 'google'
        ? 'ادخل من زر Google، ثم اختر من سيبدأ العمل وأدخل رمز PIN.'
        : 'ادخل بالبريد ورمز PIN الذي عيّنته.',
    );
    const prior = String(args.previousTrialStartedAt ?? '').trim();
    lines.push(
      prior
        ? 'مدة التجربة تبقى كما كانت على هذا البريد.'
        : 'تجربتك المجانية 15 يوماً تبدأ من فتح هذا الحساب، وهي نفسها على كل أجهزتك.',
    );
    lines.push('إن لم تطلب إنشاء الحساب فتجاهل الرسالة.');
    return card(
      'تم إنشاء حسابك من جديد — نابو',
      'حساب جديد على هذا البريد',
      'حساب جديد',
      lines,
    );
  }

  if (args.channel === 'google') {
    lines.push(
      'حساب نابو مربوط ببريد Google هذا. في المرات القادمة ادخل من زر Google، ثم اختر من سيبدأ العمل وأدخل رمز PIN.',
    );
    lines.push(
      'تجربتك المجانية 15 يوماً تبدأ من فتح هذا الحساب، وهي نفسها على كل أجهزتك.',
    );
    lines.push('إن لم تكن أنت من ربط الحساب فتجاهل الرسالة.');
    return card('أهلاً بك في نابو', 'تم ربط حساب Google', 'تم فتح الحساب', lines);
  }

  lines.push('حسابك في نابو جاهز. ادخل بالبريد ورمز PIN الذي عيّنته.');
  lines.push(
    'تجربتك المجانية 15 يوماً تبدأ من فتح هذا الحساب، وهي نفسها على كل أجهزتك.',
  );
  lines.push('إن لم تكن أنت من فتح الحساب فتجاهل الرسالة.');
  return card('أهلاً بك في نابو', 'تم فتح حسابك', 'تم فتح الحساب', lines);
}

export type WaMailMethod = 'qr' | 'cloud_api' | 'dualhook' | 'whats360';

export function waMethodFromProvider(provider: string | null | undefined): WaMailMethod {
  const id = String(provider ?? '').trim().toLowerCase();
  if (id === 'cloud_api' || id === 'ycloud') return 'cloud_api';
  if (id === 'dualhook') return 'dualhook';
  if (id === 'whats360') return 'whats360';
  return 'qr';
}

export function westernPhone(phone: string | null | undefined): string | null {
  if (!phone) return null;
  const digits = String(phone).replace(/@.*$/, '').replace(/\D/g, '');
  return digits || null;
}

function methodLine(method: WaMailMethod): string {
  if (method === 'cloud_api') return 'الطريقة: رقم المحل على Meta.';
  if (method === 'dualhook') return 'الطريقة: رقم نابو الرسمي.';
  if (method === 'whats360') return 'الطريقة: واتس360.';
  return 'الطريقة: رمز QR.';
}

export function waLinkEmailCopy(args: {
  method: WaMailMethod;
  phone?: string | null;
}): OwnerEmailCard {
  const phone = westernPhone(args.phone);
  const lines: string[] = [];
  const ltr: string[] = [];
  if (args.method === 'cloud_api') {
    lines.push(
      'رُبط رقم المحل وحساب واتساب التجاري على Meta. الرسائل تخرج من هذا الرقم.',
    );
    if (phone) ltr.push(`رقم واتساب: ${phone}`);
    lines.push('حساب واتساب مربوط.');
  } else if (args.method === 'dualhook') {
    lines.push(
      'رُبط المحل برقم نابو الرسمي. الرسائل تخرج من رقم نابو لا من رقم شخصي.',
    );
    if (phone) ltr.push(`رقم واتساب: ${phone}`);
    lines.push('حساب واتساب: رقم نابو الرسمي.');
  } else if (args.method === 'whats360') {
    lines.push('رُبط واتس360 بالتطبيق. الرسائل تخرج من الرقم المربوط.');
    if (phone) ltr.push(`رقم واتساب: ${phone}`);
  } else {
    lines.push(
      'رُبط رقم واتساب المحل بالتطبيق بعد مسح رمز QR. الرسائل التلقائية تخرج من هذا الرقم.',
    );
    if (phone) ltr.push(`رقم واتساب: ${phone}`);
  }
  lines.push('إن لم تكن أنت من ربط الجلسة فافصل واتساب من التطبيق.');
  return card(
    'تم ربط واتساب المحل — نابو',
    'تم ربط واتساب',
    'تم الربط',
    lines,
    ltr,
  );
}

export function waUnlinkEmailCopy(args: {
  method: WaMailMethod;
  phone?: string | null;
}): OwnerEmailCard {
  const phone = westernPhone(args.phone);
  const lines = [
    'أُلغي ربط واتساب عن التطبيق بطلب من الحساب. لن تُرسل رسائل الزبائن حتى يُعاد الربط.',
    methodLine(args.method),
  ];
  const ltr = phone ? [`رقم واتساب: ${phone}`] : [];
  lines.push('إن لم تطلب إلغاء الربط فافتح التطبيق وأعد الربط، أو راسل الدعم.');
  return card(
    'تم إلغاء ربط واتساب — نابو',
    'تم إلغاء الربط',
    'أُلغي الربط',
    lines,
    ltr,
  );
}

export function waDropEmailCopy(args: {
  permanent: boolean;
  method: WaMailMethod;
}): OwnerEmailCard {
  if (args.permanent && args.method === 'qr') {
    return card(
      'انقطع ربط واتساب المحل — يلزم إعادة المسح — نابو',
      'انقطع الربط',
      'يلزم إعادة الربط',
      [
        'لن تُرسل الرسائل حتى يُمسح رمز QR من جديد.',
        methodLine(args.method),
      ],
    );
  }
  if (args.permanent) {
    return card(
      'انقطع ربط واتساب المحل — نابو',
      'انقطع الربط',
      'انقطع الربط',
      [
        'أعد الربط من شاشة واتساب في التطبيق.',
        methodLine(args.method),
      ],
    );
  }
  return card(
    'انقطع اتصال واتساب المحل مؤقتاً — نابو',
    'انقطاع مؤقت',
    'انقطاع مؤقت',
    [
      'نحاول الإعادة. إن استمر الانقطاع أعد الربط من التطبيق.',
      methodLine(args.method),
    ],
  );
}

export function templateDisplayName(args: {
  templateKey?: string | null;
  templateName?: string | null;
}): string {
  const key = String(args.templateKey ?? '');
  const name = String(args.templateName ?? '');
  if (key === 'oil_change_followup') return 'تذكير غيار الزيت';
  if (name === 'oil_card_lines_ar') return 'بطاقة غيار الزيت';
  if (name === 'oil_change_card_ar') return 'بطاقة غيار الزيت المختصرة';
  if (key === 'oil_change_card') return 'بطاقة غيار الزيت';
  return 'قالب واتساب';
}

export type TemplateMailKind = 'pending' | 'approved' | 'rejected' | 'submit_failed';

export function templateStatusEmailCopy(args: {
  kind: TemplateMailKind;
  templateKey?: string | null;
  templateName?: string | null;
  language?: string | null;
}): OwnerEmailCard {
  const label = templateDisplayName(args);
  const tech = `${String(args.templateName ?? '').trim() || 'template'} · ${
    String(args.language ?? 'ar').trim() || 'ar'
  }`;

  if (args.kind === 'submit_failed') {
    return card(
      `تعذّر إرسال قالب ${label} إلى واتساب — نابو`,
      'القالب لم يصل إلى واتساب',
      'لم يصل',
      [
        'المحاولة لم تنشئ قالباً في إدارة القوالب. اضغط إرسال القالب للمراجعة مرة أخرى.',
      ],
      [tech],
    );
  }
  if (args.kind === 'pending') {
    return card(
      `تم إرسال قالب ${label} للمراجعة — نابو`,
      'تم إرسال القالب للمراجعة',
      'قيد المراجعة',
      [
        'أرسلنا القالب إلى واتساب وحالته قيد المراجعة. من دقائق إلى يومين. لا حاجة لفعل شيء حتى تصل رسالة الموافقة.',
        'يظهر في إدارة قوالب نفس الرقم.',
      ],
      [tech],
    );
  }
  if (args.kind === 'approved') {
    const body = args.templateKey === 'oil_change_followup' ||
        String(args.templateName ?? '').startsWith('oil_fu_')
      ? 'واتساب اعتمد القالب. التذكير يشتغل على الغيارات الجديدة حسب المدة المحفوظة.'
      : 'يمكن إرسال بطاقة الغيار للزبائن من التطبيق.';
    return card(
      `تمت الموافقة على قالب ${label} — نابو`,
      'تمت الموافقة على القالب',
      'تمت الموافقة',
      [body],
      [tech],
    );
  }
  return card(
    `لم تُعتمد قالب ${label} — نابو`,
    'لم تُعتمد القالب',
    'لم تُعتمد',
    [
      'واتساب لم تعتمد القالب. افتح الشاشة، عدّل النص، ثم أعد الإرسال.',
    ],
    [tech],
  );
}
