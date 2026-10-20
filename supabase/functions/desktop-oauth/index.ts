// Windows Google sign-in hop.
// Supabase may return the session in the URL hash. A server redirect cannot
// see that hash, so this page runs in the browser and forwards both the query
// and the hash to the app listening on 127.0.0.1.
const html = `<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>نبو</title>
  <style>
    body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#071A36;color:#f5f3ee;font-family:system-ui,sans-serif;padding:24px;text-align:center}
  </style>
</head>
<body>
  <p id="m">جاري إكمال تسجيل الدخول في نبو…</p>
  <script>
    (function () {
      var q = location.search ? location.search.substring(1) : '';
      var h = location.hash ? location.hash.substring(1) : '';
      var params = q;
      if (h) params = params ? (params + '&' + h) : h;
      var dest = 'http://127.0.0.1:47821/login-callback' + (params ? ('?' + params) : '');
      var msg = document.getElementById('m');
      try { location.replace(dest); } catch (e) {}
      setTimeout(function () {
        if (msg) msg.textContent = 'إذا بقيت هذه الصفحة، أبقِ تطبيق نبو مفتوحاً ثم أعد تسجيل الدخول من التطبيق.';
      }, 4000);
    })();
  </script>
</body>
</html>`;

Deno.serve((_req: Request) => {
  return new Response(html, {
    status: 200,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'content-security-policy':
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'",
    },
  });
});
