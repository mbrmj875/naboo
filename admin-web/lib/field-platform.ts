/** كشف منصة الجهاز لتطويع واجهة المندوب */

export type FieldPlatform = "ios" | "android" | "other";

export function detectFieldPlatform(
  ua = typeof navigator !== "undefined" ? navigator.userAgent : "",
): FieldPlatform {
  if (/iPhone|iPad|iPod/i.test(ua)) return "ios";
  // iPadOS 13+ قد يظهر كـ Macintosh مع لمس
  if (
    typeof navigator !== "undefined" &&
    /Macintosh/i.test(ua) &&
    Number(navigator.maxTouchPoints || 0) > 1
  ) {
    return "ios";
  }
  if (/Android/i.test(ua)) return "android";
  return "other";
}

export function fieldPlatformClass(platform: FieldPlatform): string {
  if (platform === "ios") return "platform-ios";
  if (platform === "android") return "platform-android";
  return "platform-other";
}
