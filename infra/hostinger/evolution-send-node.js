const prev = $input.first().json;
if (prev._abort) {
  return [{ json: prev }];
}

const instance = (prev.instanceName || '').toString().trim();
const evolutionBase = ($env.EVOLUTION_BASE_URL || 'http://72.61.191.237:8080').replace(/\/$/, '');
const apiKey = ($env.EVOLUTION_API_KEY || '').toString().trim();

function fail(reason, detail) {
  return [{
    json: {
      ok: false,
      reason,
      detail: detail || '',
      mode: '',
      pdf_bytes_est: 0,
      tenant_id: prev.tenant_id || '',
      order_id: prev.order_id ?? null,
      source: prev.source || '',
      sent_to: prev.phone || '',
      secret_used: prev.secret_used || '',
    },
  }];
}

if (!apiKey) return fail('missing_field', 'EVOLUTION_API_KEY_env');
if (!instance) return fail('missing_field', 'instance_name');

const pdf = (prev.pdf_base64 || '').toString().trim();
const fileName = (prev.pdf_filename || 'oil_change_service.pdf').toString().trim();
const mime = (prev.pdf_mimetype || 'application/pdf').toString().trim();
const fullText = (prev.message_text || '').toString();

const rawB64 = pdf.replace(/^data:[^;]+;base64,/, '').trim();
const dataUri = rawB64 ? `data:${mime};base64,${rawB64}` : '';

let pdf_bytes_est = 0;
if (rawB64) {
  const padding = rawB64.endsWith('==') ? 2 : rawB64.endsWith('=') ? 1 : 0;
  pdf_bytes_est = Math.floor((rawB64.length * 3) / 4) - padding;
}

const pdfUsable = rawB64.length > 80 && pdf_bytes_est >= 500;

let ok = false;
let reason = '';
let mode = 'text';
let detail = '';

async function sendText(text) {
  await this.helpers.httpRequest({
    method: 'POST',
    url: `${evolutionBase}/message/sendText/${instance}`,
    headers: { apikey: apiKey, 'Content-Type': 'application/json' },
    body: { number: prev.phone, text },
    json: true,
    timeout: 30000,
  });
}

async function sendPdf(mediaPayload) {
  await this.helpers.httpRequest({
    method: 'POST',
    url: `${evolutionBase}/message/sendMedia/${instance}`,
    headers: { apikey: apiKey, 'Content-Type': 'application/json' },
    body: {
      number: prev.phone,
      options: { delay: 1200, presence: 'composing' },
      mediatype: 'document',
      mimetype: 'application/pdf',
      caption: 'مرفق: تفاصيل زيارة غيار الزيت (PDF)',
      media: mediaPayload,
      fileName,
      filename: fileName,
    },
    json: true,
    timeout: 90000,
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

try {
  if (!pdfUsable) {
    await sendText.call(this, fullText);
    mode = rawB64 ? 'text_pdf_too_small' : 'text_no_pdf_in_request';
    ok = true;
  } else {
    let pdfSent = false;
    let pdfErr = '';
    try {
      await sendPdf.call(this, rawB64);
      pdfSent = true;
      mode = 'pdf_raw';
    } catch (e1) {
      pdfErr = (e1.message || String(e1)).slice(0, 300);
      try {
        await sendPdf.call(this, dataUri);
        pdfSent = true;
        mode = 'pdf_data_uri';
        pdfErr = '';
      } catch (e2) {
        pdfErr = (e2.message || String(e2)).slice(0, 300);
      }
    }

    if (pdfSent) {
      await sleep(1500);
    }

    await sendText.call(this, fullText);
    mode = pdfSent ? `${mode}+text` : 'text_after_pdf_fail';
    detail = pdfErr;
    ok = true;
  }
} catch (e) {
  detail = (e.message || String(e)).slice(0, 400);
  const msg = detail.toLowerCase();
  if (msg.includes('disconnect') || msg.includes('not connected') || msg.includes('closed')) {
    reason = 'whatsapp_disconnected';
  } else if (msg.includes('timeout') || msg.includes('timed out')) {
    reason = 'timeout';
  } else if (msg.includes('401') || msg.includes('403')) {
    reason = 'unauthorized';
  } else if (msg.includes('404')) {
    reason = 'instance_not_found';
  } else if (msg.includes('rate') || msg.includes('429')) {
    reason = 'rate_limited';
  } else {
    reason = 'evolution_error';
  }
}

return [{
  json: {
    ok,
    reason,
    mode,
    detail,
    pdf_bytes_est,
    tenant_id: prev.tenant_id,
    order_id: prev.order_id,
    source: prev.source,
    sent_to: prev.phone,
    instanceName: instance,
    secret_used: prev.secret_used || '',
  },
}];
