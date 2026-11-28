// دالة القياس المؤقتة انتهى دورها؛ معطّلة نهائياً (2026-11-27).
Deno.serve(() => new Response(JSON.stringify({ error: 'gone' }), {
  status: 410,
  headers: { 'Content-Type': 'application/json' },
}));
