import { listVisitEventsSince } from "@/lib/field-db";
import { requireAdminSession } from "@/lib/field-request";

export const dynamic = "force-dynamic";
export const runtime = "nodejs";

export async function GET(req: Request) {
  const auth = await requireAdminSession();
  if (!auth.ok) return auth.response;

  const url = new URL(req.url);
  let lastId = Number(
    req.headers.get("last-event-id") ?? url.searchParams.get("since") ?? "0",
  );
  if (!Number.isFinite(lastId) || lastId < 0) lastId = 0;

  const encoder = new TextEncoder();
  let closed = false;

  const stream = new ReadableStream({
    start(controller) {
      const send = (id: number, data: unknown) => {
        if (closed) return;
        controller.enqueue(
          encoder.encode(`id: ${id}\ndata: ${JSON.stringify(data)}\n\n`),
        );
      };

      // heartbeat
      const ping = setInterval(() => {
        if (closed) return;
        controller.enqueue(encoder.encode(`: ping\n\n`));
      }, 15000);

      const tick = async () => {
        if (closed) return;
        try {
          const events = await listVisitEventsSince(lastId, 100);
          if (events.length > 0) {
            // batch as one SSE message per event, then update lastId
            for (const ev of events) {
              send(ev.id, {
                id: ev.id,
                visit_id: ev.visit_id,
                field_name: ev.field_name,
                actor_kind: ev.actor_kind,
                created_at: ev.created_at,
              });
              lastId = ev.id;
            }
          }
        } catch {
          // keep stream alive
        }
      };

      void tick();
      const interval = setInterval(() => void tick(), 2000);

      const abort = () => {
        closed = true;
        clearInterval(interval);
        clearInterval(ping);
        try {
          controller.close();
        } catch {
          /* ignore */
        }
      };

      req.signal.addEventListener("abort", abort);
    },
    cancel() {
      closed = true;
    },
  });

  return new Response(stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    },
  });
}
