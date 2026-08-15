import { createClient } from '@supabase/supabase-js';
import { Resend } from 'resend';

const siteUrl = 'https://personaltrating.com';

export const handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method not allowed' };
  }

  let body;
  try { body = JSON.parse(event.body); } catch {
    return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON' }) };
  }

  const { review_id, reason, access_token } = body;
  if (!review_id || !access_token) {
    return { statusCode: 400, body: JSON.stringify({ error: 'Missing fields' }) };
  }

  const supabase = createClient(
    process.env.PUBLIC_SUPABASE_URL,
    process.env.PUBLIC_SUPABASE_ANON_KEY
  );

  // Verify the JWT and get the user
  const { data: { user }, error: userError } = await supabase.auth.getUser(access_token);
  if (userError || !user) {
    console.log('[submit-appeal] auth error:', userError?.message);
    return { statusCode: 401, body: JSON.stringify({ error: 'unauthorized' }) };
  }

  // Look up their trainer profile
  const { data: trainer, error: trainerError } = await supabase
    .from('trainers')
    .select('id, name')
    .eq('user_id', user.id)
    .maybeSingle();

  if (trainerError || !trainer) {
    console.log('[submit-appeal] trainer lookup error:', trainerError?.message);
    return { statusCode: 403, body: JSON.stringify({ error: 'unauthorized' }) };
  }

  // Call RPC — passes trainer_id so no auth.uid() needed in SQL
  const { data, error } = await supabase.rpc('submit_review_appeal', {
    p_review_id:  review_id,
    p_trainer_id: trainer.id,
    p_reason:     reason ?? '',
  });

  if (error) {
    console.log('[submit-appeal] rpc error:', error.message);
    return { statusCode: 500, body: JSON.stringify({ error: error.message }) };
  }

  if (data?.error) {
    const status = data.error === 'already_appealed' ? 409 : 400;
    return { statusCode: status, body: JSON.stringify({ error: data.error }) };
  }

  // Send appeal email to admin
  const resend = new Resend(process.env.RESEND_API_KEY);
  const removeUrl = `${siteUrl}/.netlify/functions/action-appeal?token=${data.token}&action=remove`;
  const upholdUrl = `${siteUrl}/.netlify/functions/action-appeal?token=${data.token}&action=uphold`;

  const stars = '★'.repeat(Math.round(data.rating)) + '☆'.repeat(5 - Math.round(data.rating));
  const reasonHtml = reason
    ? `<div style="background:#fff8e1;border-left:3px solid #f59e0b;padding:1rem 1.25rem;border-radius:0 8px 8px 0;margin:1.25rem 0;">
        <div style="font-size:0.7rem;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:#b45309;margin-bottom:0.4rem;">Trainer's Reason</div>
        <div style="font-size:0.9rem;color:#1c1c1e;line-height:1.7;">${reason}</div>
       </div>`
    : `<p style="font-size:0.85rem;color:#7a8f7c;font-style:italic;margin:1.25rem 0;">No reason provided.</p>`;

  await resend.emails.send({
    from: 'Personal TRating <noreply@personaltrating.com>',
    to:   'modernisetraders@hotmail.com',
    subject: `Review Appeal — ${trainer.name} disputes ${data.reviewer_name}'s review`,
    html: `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;">
  <div style="max-width:560px;margin:40px auto;background:white;border-radius:20px;overflow:hidden;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="background:linear-gradient(135deg,#0d1a0e,#1a3d1e);padding:32px 40px;">
      <div style="font-size:0.65rem;font-weight:700;letter-spacing:3px;text-transform:uppercase;color:#7de88a;margin-bottom:8px;">Action Required</div>
      <h1 style="margin:0;font-size:1.5rem;font-weight:900;color:white;">Review Appeal</h1>
    </div>
    <div style="padding:32px 40px;">
      <p style="font-size:0.9rem;color:#3a4a3b;line-height:1.7;margin:0 0 1.5rem;">
        <strong>${trainer.name}</strong> has appealed a verified review left by <strong>${data.reviewer_name}</strong>.
      </p>

      <div style="background:#f4f6f4;border-radius:12px;padding:1.25rem 1.5rem;margin-bottom:0.5rem;">
        <div style="font-size:0.7rem;font-weight:700;letter-spacing:1.5px;text-transform:uppercase;color:#3ab54a;margin-bottom:0.5rem;">The Review</div>
        <div style="font-size:1rem;color:#f59e0b;letter-spacing:2px;margin-bottom:0.5rem;">${stars}</div>
        <div style="font-size:0.9rem;color:#1c1c1e;line-height:1.7;font-style:italic;">"${data.review_text}"</div>
        <div style="font-size:0.75rem;color:#7a8f7c;margin-top:0.5rem;">— ${data.reviewer_name}</div>
      </div>

      ${reasonHtml}

      <div style="display:flex;gap:12px;margin-top:1.75rem;">
        <a href="${removeUrl}" style="flex:1;display:inline-block;background:#dc2626;color:white;text-decoration:none;padding:14px 0;border-radius:10px;font-weight:700;font-size:0.88rem;text-align:center;">
          Remove Review
        </a>
        <a href="${upholdUrl}" style="flex:1;display:inline-block;background:#3ab54a;color:white;text-decoration:none;padding:14px 0;border-radius:10px;font-weight:700;font-size:0.88rem;text-align:center;">
          Uphold Review
        </a>
      </div>
      <p style="font-size:0.72rem;color:#aaa;margin-top:1rem;text-align:center;">
        Remove = delete the review &amp; recalculate BMP. Uphold = keep the review live.
      </p>
    </div>
  </div>
</body>
</html>`,
  });

  return { statusCode: 200, body: JSON.stringify({ ok: true }) };
};
