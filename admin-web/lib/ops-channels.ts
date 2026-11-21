/** قنوات تواصل عمل نابو — واتساب فعّال؛ الباقي مهيأ لنفس نموذج الهوية. */

export type OpsChannel =
  | "whatsapp"
  | "facebook"
  | "instagram"
  | "telegram"
  | "email"
  | "tiktok"
  | "system";

export type OpsChannelMeta = {
  id: OpsChannel;
  labelAr: string;
  /** جاهز للاستقبال/الإرسال في الكود الحالي */
  enabled: boolean;
  /** ترتيب التفعيل حسب خطة المنتج */
  rolloutOrder: number;
};

export const OPS_CHANNELS: OpsChannelMeta[] = [
  { id: "whatsapp", labelAr: "واتساب", enabled: true, rolloutOrder: 1 },
  { id: "facebook", labelAr: "فيسبوك", enabled: false, rolloutOrder: 2 },
  { id: "instagram", labelAr: "إنستغرام", enabled: false, rolloutOrder: 3 },
  { id: "telegram", labelAr: "تيليجرام", enabled: false, rolloutOrder: 4 },
  { id: "email", labelAr: "البريد", enabled: false, rolloutOrder: 5 },
  { id: "tiktok", labelAr: "تيك توك", enabled: false, rolloutOrder: 6 },
  { id: "system", labelAr: "النظام", enabled: true, rolloutOrder: 99 },
];

export function opsChannelLabelAr(channel: string): string {
  return OPS_CHANNELS.find((c) => c.id === channel)?.labelAr ?? channel;
}

export function isOpsChannelEnabled(channel: string): boolean {
  return OPS_CHANNELS.find((c) => c.id === channel)?.enabled === true;
}
