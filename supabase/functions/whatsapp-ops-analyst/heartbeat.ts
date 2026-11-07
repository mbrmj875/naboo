/** Dead Man's Switch — ping Healthchecks.io بعد تشغيل ناجح. */

export async function pingHealthchecks(): Promise<{
  ok: boolean;
  detail: string;
}> {
  const url = Deno.env.get('HEALTHCHECKS_PING_URL') ?? '';
  if (!url) {
    return { ok: false, detail: 'HEALTHCHECKS_PING_URL missing' };
  }
  try {
    const res = await fetch(url, {
      method: 'GET',
      redirect: 'follow',
    });
    return {
      ok: res.ok || res.status === 200 || res.status === 204,
      detail: `http_${res.status}`,
    };
  } catch (e) {
    return { ok: false, detail: String(e).slice(0, 200) };
  }
}
