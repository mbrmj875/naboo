// Public hop: Google/Supabase → this URL → http://127.0.0.1:47821 (Windows app).
Deno.serve((req: Request) => {
  const incoming = new URL(req.url);
  const dest = new URL('http://127.0.0.1:47821/login-callback');
  incoming.searchParams.forEach((value, key) => {
    dest.searchParams.set(key, value);
  });
  return Response.redirect(dest.toString(), 302);
});
