// قراءة لوحة السيارة والعدّاد من صورتين (م4-13).
//
// الخادم يقرأ فقط ويرجع رقمين للمراجعة؛ الهاتف يعرضهما دائماً في خانتين قابلتين
// للتعديل قبل فتح البطاقة، ولا يُخمَّن زبون. القياس (م0-17): اللوحات الجديدة
// دقيقة، والقديمة العربية تخطئ برقم، فتُعلَّم old ليظهر «تأكد من الأرقام».

import { MAX_IMAGE_CHARS } from './conversation.ts';

export type CarPhotoRead = {
  plate: string | null;
  plate_style: 'new' | 'old' | 'unknown';
  odometer: number | null;
};

const PROMPT = [
  'أنت تقرأ صوراً لسيارة في محل غيار زيت عراقي. أرجع JSON فقط بهذا الشكل:',
  '{"plate": "...", "plate_style": "new|old|unknown", "odometer": 123456}',
  'اللوحة: الجديدة رقم محافظة ثم حرف لاتيني ثم خمسة أرقام، اكتبها هكذا "14 B 64190".',
  'القديمة فيها سطر عربي وسطر لاتيني بنفس الرقم واسم المحافظة؛ اكتب الحرف اللاتيني والرقم من السطر اللاتيني، و plate_style = "old".',
  'لا تكتب اسم المحافظة. إن لم تتأكد من كل رقم في اللوحة فاجعل plate = null.',
  'العدّاد: الرقم الكلي للكيلومترات فقط (ليس عدّاد الرحلة TRIP)، رقماً بلا فواصل. إن لم تجد عدّاداً أو لم يكن واضحاً فاجعله null.',
  'لا تخمّن أبداً.',
].join('\n');

/** رسائل الطلب: نص التعليمات ثم صورة أو صورتان. */
export function carPhotoMessages(images: string[]): Record<string, unknown>[] {
  return [
    { role: 'system', content: PROMPT },
    {
      role: 'user',
      content: [
        {
          type: 'text',
          text: images.length > 1 ? 'الصورة الأولى للوحة، والثانية للعدّاد.' : 'اقرأ ما يظهر في الصورة.',
        },
        ...images.map((url) => ({ type: 'image_url', image_url: { url } })),
      ],
    },
  ];
}

/** يتحقق من الصور المرسلة: واحدة أو اثنتان، data URL، ضمن الحد. */
export function cleanCarImages(raw: unknown): string[] | string {
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > 2) {
    return 'bad_images';
  }
  const out: string[] = [];
  for (const v of raw) {
    const url = String(v ?? '');
    if (!url.startsWith('data:image/')) return 'bad_image';
    if (url.length > MAX_IMAGE_CHARS) return 'image_too_large';
    out.push(url);
  }
  return out;
}

const PLATE_RE = /^(\d{1,2})\s*([A-Z])\s*(\d{3,6})$/;

/** يطبّع ما أرجعه النموذج. أي شيء غير مؤكد يصير null لا تخميناً. */
export function parseCarPhoto(text: string): CarPhotoRead {
  let o: Record<string, unknown> = {};
  try {
    const m = text.match(/\{[\s\S]*\}/);
    o = m ? JSON.parse(m[0]) : {};
  } catch {
    o = {};
  }
  const style = String(o.plate_style ?? '');
  const plate_style: CarPhotoRead['plate_style'] = style === 'new' || style === 'old' ? style : 'unknown';

  let plate: string | null = null;
  const rawPlate = typeof o.plate === 'string'
    ? o.plate.toUpperCase().replace(/[-_.]/g, ' ').replace(/\s+/g, ' ').trim()
    : '';
  if (rawPlate) {
    const m = rawPlate.match(PLATE_RE);
    if (m) {
      plate = `${m[1]} ${m[2]} ${m[3]}`;
    } else {
      // القديمة: حرف ورقم بلا رقم محافظة.
      const old = rawPlate.match(/^([A-Z])\s*(\d{3,6})$/);
      if (old) plate = `${old[1]} ${old[2]}`;
    }
  }

  let odometer: number | null = null;
  const rawOdo = typeof o.odometer === 'number' ? o.odometer : Number(String(o.odometer ?? '').replace(/[,\s]/g, ''));
  if (
    Number.isFinite(rawOdo) && Number.isInteger(rawOdo) && rawOdo > 0 &&
    rawOdo < 3_000_000
  ) odometer = rawOdo;

  return { plate, plate_style: plate ? plate_style : 'unknown', odometer };
}
