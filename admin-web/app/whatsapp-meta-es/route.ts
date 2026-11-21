import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

/**
 * صفحة عامة لـ WhatsApp Embedded Signup.
 * نحوّل للملف الثابت في public مع الإبقاء على كل query params —
 * قراءة الملفات من نظام الملفات داخل route غير مضمونة على Vercel.
 */
export function GET(request: Request) {
  const url = new URL(request.url);
  const target = new URL("/whatsapp-meta-es.html", url.origin);
  target.search = url.search;
  return NextResponse.redirect(target, 307);
}
