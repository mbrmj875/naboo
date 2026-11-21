import { NextResponse } from "next/server";
import { fieldCookieName } from "@/lib/field-session";

export async function POST() {
  const res = NextResponse.json({ ok: true });
  res.cookies.set(fieldCookieName(), "", {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/",
    maxAge: 0,
  });
  return res;
}
