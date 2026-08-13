export const handler = async (event) => {
  console.log('[send-review-email] invoked', event.httpMethod);
  if (event.httpMethod !== 'POST') return { statusCode: 405, body: 'Method not allowed' };

  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return { statusCode: 400, body: 'Bad JSON' }; }

  const { trainerName, trainerId, reviewerName, isClient, rating, reviewText, approvalToken } = body;
  console.log('[send-review-email] approvalToken present:', !!approvalToken, '| RESEND_API_KEY present:', !!process.env.RESEND_API_KEY);
  if (!approvalToken) return { statusCode: 400, body: 'Missing token' };

  const bmp      = Math.round((rating || 0) * 20);
  const stars    = Math.round((rating || 0) * 5);
  const dumbbells = '🏋️'.repeat(stars) + '⬜'.repeat(Math.max(0, 5 - stars));
  const siteUrl    = 'https://personaltrating.com';
  const approveUrl = `${siteUrl}/.netlify/functions/approve-review?token=${approvalToken}&action=approve`;
  const rejectUrl  = `${siteUrl}/.netlify/functions/approve-review?token=${approvalToken}&action=reject`;
  const profileUrl = `${siteUrl}/trainers/${trainerId}`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;">
  <div style="max-width:560px;margin:0 auto;padding:32px 16px;">

    <div style="background:linear-gradient(135deg,#0d1a0e,#1a3d1e);border-radius:16px 16px 0 0;padding:28px 32px;text-align:center;">
      <div style="color:#3ab54a;font-size:11px;font-weight:800;letter-spacing:3px;text-transform:uppercase;margin-bottom:8px;">Personal TRating</div>
      <div style="color:white;font-size:20px;font-weight:800;">New Review Pending Approval</div>
    </div>

    <div style="background:white;padding:32px;border:1px solid #e0e8e1;border-top:none;">

      <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#7a8f7c;margin-bottom:4px;">Trainer</div>
      <div style="font-size:18px;font-weight:800;color:#0d1a0e;margin-bottom:24px;">${trainerName}</div>

      <div style="background:#f7f9f7;border:1px solid #e0e8e1;border-radius:12px;padding:16px 20px;margin-bottom:16px;">
        <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#7a8f7c;margin-bottom:8px;">Reviewer</div>
        <div style="font-size:15px;font-weight:700;color:#0d1a0e;">${reviewerName}</div>
        <div style="font-size:13px;color:#7a8f7c;margin-top:4px;">${isClient ? '✅ Registered client · Email verified' : '👤 Guest · No account'}</div>
      </div>

      <div style="background:#f7f9f7;border:1px solid #e0e8e1;border-radius:12px;padding:16px 20px;margin-bottom:16px;">
        <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#7a8f7c;margin-bottom:8px;">BMP Score Given</div>
        <div style="font-size:36px;font-weight:900;color:#0d1a0e;line-height:1;">${bmp}<span style="font-size:16px;color:#7a8f7c;">%</span></div>
        <div style="font-size:18px;margin-top:6px;">${dumbbells}</div>
      </div>

      <div style="background:#f7f9f7;border:1px solid #e0e8e1;border-left:3px solid #3ab54a;border-radius:12px;padding:16px 20px;margin-bottom:28px;">
        <div style="font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#7a8f7c;margin-bottom:8px;">Review</div>
        <div style="font-size:14px;color:#0d1a0e;line-height:1.7;font-style:italic;">"${reviewText}"</div>
      </div>

      <a href="${approveUrl}"
        style="display:block;background:#3ab54a;color:white;text-decoration:none;text-align:center;padding:18px;border-radius:12px;font-weight:800;font-size:16px;margin-bottom:12px;">
        ✓ Approve This Review
      </a>
      <a href="${rejectUrl}"
        style="display:block;background:#f7f9f7;color:#c0392b;text-decoration:none;text-align:center;padding:14px;border-radius:12px;font-weight:700;font-size:14px;border:2px solid #f0d0ce;margin-bottom:12px;">
        ✕ Reject &amp; Delete This Review
      </a>
      <p style="font-size:12px;color:#aab8ac;text-align:center;margin:0;">Approving makes it live immediately. Rejecting permanently deletes it.</p>
    </div>

    <div style="background:#f0f4f0;border-radius:0 0 16px 16px;padding:16px 32px;border:1px solid #e0e8e1;border-top:none;text-align:center;">
      <a href="${profileUrl}" style="font-size:12px;color:#3ab54a;text-decoration:none;">View trainer profile →</a>
    </div>

  </div>
</body>
</html>`;

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${process.env.RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from: 'Personal TRating <onboarding@resend.dev>',
      to: ['modernisetraders@hotmail.com'],
      subject: `⏳ New Review Pending — ${trainerName}`,
      html,
    }),
  });

  const resBody = await res.text();
  console.log('[send-review-email] Resend status:', res.status, '| body:', resBody);

  if (!res.ok) {
    return { statusCode: 500, body: 'Email send failed' };
  }

  return { statusCode: 200, body: 'ok' };
};
