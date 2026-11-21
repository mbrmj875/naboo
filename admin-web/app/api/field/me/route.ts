import { NextResponse } from "next/server";
import { findRepById } from "@/lib/field-db";
import { requireFieldSession } from "@/lib/field-request";

export async function GET() {
  const auth = await requireFieldSession();
  if (!auth.ok) return auth.response;
  const rep = await findRepById(auth.session.repId);
  return NextResponse.json({
    ok: true,
    rep: rep
      ? {
          id: rep.id,
          username: rep.username,
          display_name: rep.display_name,
        }
      : { id: auth.session.repId },
  });
}
