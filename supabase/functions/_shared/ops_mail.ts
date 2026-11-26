// بريد تنبيه فريق نابو: نفس مرحّل البريد الذي تستعمله مراقبة واتساب، ثم Resend
// احتياطاً. لا يرمي خطأ: الفشل يُرجع نصاً قصيراً للسجل.

export async function sendOpsMail(to: string, subject: string, text: string): Promise<{ ok: boolean; detail: string }> {
  if (!to.includes('@')) return { ok: false, detail: 'no_address' };
  const relayUrl = (Deno.env.get('OPS_MAIL_RELAY_URL') ?? '').replace(/\/$/, '');
  const relaySecret = Deno.env.get('OPS_MAIL_RELAY_SECRET') ?? '';
  if (relayUrl && relaySecret) {
    try {
      const res = await fetch(`${relayUrl}/send`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Ops-Mail-Secret': relaySecret },
        body: JSON.stringify({ to, subject, text }),
        signal: AbortSignal.timeout(8_000),
      });
      await res.body?.cancel();
      if (res.ok) return { ok: true, detail: 'relay' };
    } catch { /* نجرب Resend */ }
  }
  const key = Deno.env.get('RESEND_API_KEY') ?? '';
  if (!key) return { ok: false, detail: 'no_mailer' };
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: Deno.env.get('OPS_ALERT_FROM_EMAIL') ?? 'NaBoo Ops <onboarding@resend.dev>',
        to: [to],
        subject,
        text,
      }),
      signal: AbortSignal.timeout(8_000),
    });
    await res.body?.cancel();
    return { ok: res.ok, detail: res.ok ? 'resend' : `resend_${res.status}` };
  } catch (e) {
    return { ok: false, detail: String(e).slice(0, 80) };
  }
}
