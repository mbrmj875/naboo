/** بطاقة بريد نابو — نفس هيكل رسائل رمز الدخول، بلا رمز وبلا رابط. */

function esc(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

export function renderNabooEmail(args: {
  title: string;
  badge: string;
  paragraphs: string[];
  ltrLines?: string[];
}): { text: string; html: string } {
  const paragraphs = args.paragraphs.map((p) => p.trim()).filter(Boolean);
  const ltr = (args.ltrLines ?? []).map((p) => p.trim()).filter(Boolean);
  const text = [
    args.title,
    args.badge,
    '',
    ...paragraphs,
    ...ltr,
    '',
    'Naboo · support@naboo.fun',
  ].join('\n');

  const body = paragraphs
    .map(
      (p) =>
        `<p style="margin:0 0 10px;font-size:15px;color:#334155;line-height:1.7;">${esc(p)}</p>`,
    )
    .join('');
  const ltrHtml = ltr.length === 0
    ? ''
    : `<p dir="ltr" style="margin:12px 0 0;font-size:13px;color:#64748b;line-height:1.6;font-family:ui-monospace,Consolas,monospace;text-align:left;">${
      ltr.map(esc).join('<br>')
    }</p>`;

  const html = `<div dir="rtl" style="margin:0;padding:0;background:#e8eef8;font-family:Georgia,'Times New Roman',Tahoma,'Segoe UI',serif;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#e8eef8;padding:40px 16px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:480px;background:#ffffff;border-radius:20px;overflow:hidden;">
        <tr><td style="background:#0b1f4a;padding:32px 28px 28px;text-align:center;border-bottom:3px solid #c9a227;">
          <p style="margin:0 0 6px;font-size:34px;font-weight:700;color:#ffffff;letter-spacing:0.12em;font-family:Georgia,'Palatino Linotype',Palatino,'Times New Roman',serif;">Naboo</p>
          <p style="margin:0;font-size:13px;color:#f0e6c8;letter-spacing:0.06em;font-family:Tahoma,'Segoe UI',Arial,sans-serif;">نظام إدارة الأعمال</p>
        </td></tr>
        <tr><td style="padding:28px 28px 8px;text-align:center;font-family:Tahoma,'Segoe UI',Arial,sans-serif;">
          <p style="margin:0 0 14px;font-size:20px;font-weight:700;color:#0b1f4a;">${esc(args.title)}</p>
          <table role="presentation" cellspacing="0" cellpadding="0" style="margin:0 auto 16px;background:#0b1f4a;border-radius:16px;border:2px solid #c9a227;">
            <tr><td align="center" style="padding:16px 28px;">
              <p style="margin:0;font-size:18px;font-weight:700;color:#ffffff;font-family:Tahoma,'Segoe UI',Arial,sans-serif;">${esc(args.badge)}</p>
            </td></tr>
          </table>
          ${body}
          ${ltrHtml}
        </td></tr>
        <tr><td style="padding:14px 28px;background:#0b1f4a;border-top:3px solid #c9a227;text-align:center;">
          <p style="margin:0;font-size:11px;color:#f0e6c8;font-family:Tahoma,'Segoe UI',Arial,sans-serif;">Naboo · support@naboo.fun</p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</div>`;

  return { text, html };
}
