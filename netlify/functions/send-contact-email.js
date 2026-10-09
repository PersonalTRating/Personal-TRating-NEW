// Simple in-memory rate limiter (resets on cold start; adequate for basic spam protection)
const rateStore = new Map();
const RATE_MAX    = 3;
const RATE_WINDOW = 15 * 60 * 1000; // 15 minutes

function esc(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
    .replace(/\n/g, '<br>');
}

export const handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method not allowed' };
  }

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return { statusCode: 400, body: JSON.stringify({ error: 'Invalid request' }) }; }

  // Honeypot: silently accept bot submissions
  if (body.website || body.bot_check) {
    return { statusCode: 200, body: JSON.stringify({ ok: true }) };
  }

  // Rate limiting by IP
  const ip  = (event.headers['x-forwarded-for'] || '').split(',')[0].trim() || 'unknown';
  const now = Date.now();
  const rec = rateStore.get(ip) || { count: 0, first: now };
  if (now - rec.first > RATE_WINDOW) { rec.count = 0; rec.first = now; }
  rec.count++;
  rateStore.set(ip, rec);
  if (rec.count > RATE_MAX) {
    return { statusCode: 429, body: JSON.stringify({ error: 'Too many requests. Please wait a few minutes and try again.' }) };
  }

  // Sanitise and validate
  const name    = (body.name    || '').toString().trim().slice(0, 200);
  const email   = (body.email   || '').toString().trim().slice(0, 320);
  const message = (body.message || '').toString().trim().slice(0, 3000);

  if (!name || !email || !message) {
    return { statusCode: 400, body: JSON.stringify({ error: 'All fields are required.' }) };
  }
  // Basic email format check (prevents header injection via email field)
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email) || /[\r\n]/.test(email)) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Please enter a valid email address.' }) };
  }
  // Prevent header injection in name
  if (/[\r\n]/.test(name)) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Invalid input.' }) };
  }

  const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;">
  <div style="max-width:560px;margin:0 auto;padding:32px 16px;">

    <div style="background:linear-gradient(135deg,#0d1a0e,#1a3d1e);border-radius:16px 16px 0 0;padding:28px 32px;">
      <div style="color:#3ab54a;font-size:11px;font-weight:800;letter-spacing:3px;text-transform:uppercase;margin-bottom:8px;">CoachCards</div>
      <div style="color:white;font-size:20px;font-weight:800;">New Contact Message</div>
    </div>

    <div style="background:white;padding:32px;border:1px solid #e0e8e1;border-top:none;">

      <table style="width:100%;border-collapse:collapse;">
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #f0f4f0;font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#7a8f7c;width:100px;">Name</td>
          <td style="padding:10px 0;border-bottom:1px solid #f0f4f0;font-size:15px;font-weight:700;color:#0d1a0e;">${esc(name)}</td>
        </tr>
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #f0f4f0;font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#7a8f7c;">Email</td>
          <td style="padding:10px 0;border-bottom:1px solid #f0f4f0;font-size:15px;color:#0d1a0e;">${esc(email)}</td>
        </tr>
        <tr>
          <td style="padding:10px 0;border-bottom:1px solid #f0f4f0;font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#7a8f7c;">Source</td>
          <td style="padding:10px 0;border-bottom:1px solid #f0f4f0;font-size:13px;color:#7a8f7c;">CoachCards Contact Form</td>
        </tr>
      </table>

      <div style="margin-top:24px;background:#f7f9f7;border:1px solid #e0e8e1;border-left:3px solid #3ab54a;border-radius:0 12px 12px 0;padding:20px 24px;">
        <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#7a8f7c;margin-bottom:10px;">Message</div>
        <div style="font-size:14px;color:#0d1a0e;line-height:1.75;">${esc(message)}</div>
      </div>

      <p style="margin-top:24px;font-size:12px;color:#aab8ac;text-align:center;">
        Reply directly to this email to respond to ${esc(name)}.
      </p>
    </div>

    <div style="background:#f0f4f0;border-radius:0 0 16px 16px;padding:14px 32px;border:1px solid #e0e8e1;border-top:none;text-align:center;">
      <span style="font-size:12px;color:#7a8f7c;">CoachCards · <a href="https://coachcards.co.uk" style="color:#3ab54a;text-decoration:none;">coachcards.co.uk</a></span>
    </div>

  </div>
</body>
</html>`;

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.RESEND_API_KEY}`,
      'Content-Type':  'application/json',
    },
    body: JSON.stringify({
      from:     'CoachCards <onboarding@resend.dev>',
      to:       ['hello@coachcards.co.uk'],
      reply_to: email,
      subject:  `New CoachCards Contact Message — ${name}`,
      html,
    }),
  });

  console.log('[send-contact-email] Resend status:', res.status);

  if (!res.ok) {
    return { statusCode: 500, body: JSON.stringify({ error: 'Email delivery failed. Please try again.' }) };
  }

  return { statusCode: 200, body: JSON.stringify({ ok: true }) };
};
