import { createClient } from '@supabase/supabase-js';

const SITE_URL     = process.env.SITE_URL ?? 'https://coachcards.co.uk';
const FROM_ADDRESS = 'CoachCards <hello@coachcards.co.uk>';

export const handler = async (event) => {
  const token  = event.queryStringParameters?.token;
  const action = event.queryStringParameters?.action || 'approve';

  if (!token) {
    return { statusCode: 400, headers: { 'Content-Type': 'text/html' }, body: errorPage('Invalid approval link.') };
  }

  console.log('[approve-review] env check — URL:', !!process.env.PUBLIC_SUPABASE_URL, 'KEY:', !!process.env.PUBLIC_SUPABASE_ANON_KEY);

  // Anon client for the approval RPC (approve_review_by_token is public).
  const supabase = createClient(
    process.env.PUBLIC_SUPABASE_URL,
    process.env.PUBLIC_SUPABASE_ANON_KEY
  );

  if (action === 'reject') {
    let data, error;
    try {
      ({ data, error } = await supabase.rpc('reject_review_by_token', { p_token: token }));
    } catch (e) {
      console.log('[approve-review] reject rpc threw:', e.message);
      return { statusCode: 500, headers: { 'Content-Type': 'text/html' }, body: errorPage('A server error occurred. Please try again or contact support.') };
    }

    if (error || !data || data === 'not_found') {
      return {
        statusCode: 400,
        headers: { 'Content-Type': 'text/html' },
        body: errorPage('This review has already been actioned or the link is invalid.'),
      };
    }

    return {
      statusCode: 200,
      headers: { 'Content-Type': 'text/html' },
      body: rejectedPage(data),
    };
  }

  // Default: approve
  let data, error;
  try {
    ({ data, error } = await supabase.rpc('approve_review_by_token', { p_token: token }));
  } catch (e) {
    console.log('[approve-review] approve rpc threw:', e.message);
    return { statusCode: 500, headers: { 'Content-Type': 'text/html' }, body: errorPage('A server error occurred. Please try again or contact support.') };
  }

  console.log('[approve-review] rpc result:', JSON.stringify({ data, error }));

  if (error) {
    return {
      statusCode: 500,
      headers: { 'Content-Type': 'text/html' },
      body: errorPage('A server error occurred. Please try again or contact support.'),
    };
  }

  if (data === 'not_found') {
    return {
      statusCode: 400,
      headers: { 'Content-Type': 'text/html' },
      body: errorPage('This approval link is invalid or has expired.'),
    };
  }

  if (data === 'already_approved') {
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'text/html' },
      body: alreadyApprovedPage(),
    };
  }

  // ── Send reviewer notification — awaited ──────────────────────────────
  // MUST be awaited. Netlify kills the execution context the moment the
  // handler returns — any un-awaited fetch inside sendNotification is
  // silently terminated, leaving notification_claimed_at unset and the
  // retry scheduler unable to recover the review (it skips NULL claimed_at).
  try {
    await sendNotification(token);
  } catch (err) {
    console.error('[approve-review] notification: unhandled error —', err.message);
  }

  return {
    statusCode: 200,
    headers: { 'Content-Type': 'text/html' },
    body: successPage(data),
  };
};

async function sendNotification(token) {
  const svcKey = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
  if (!svcKey) {
    console.warn('[approve-review] notification: SUPABASE_SERVICE_ROLE_KEY not set — skipping');
    return;
  }

  const resendKey = process.env.RESEND_API_KEY ?? '';
  if (!resendKey) {
    console.warn('[approve-review] notification: RESEND_API_KEY not set — skipping');
    return;
  }

  const supabaseService = createClient(
    process.env.PUBLIC_SUPABASE_URL,
    svcKey,
    { auth: { persistSession: false } }
  );

  console.log('[approve-review] notification: claiming slot');

  const { data: rows, error: rpcErr } = await supabaseService.rpc(
    'claim_approval_notification_by_token',
    { p_token: token }
  );

  if (rpcErr) {
    console.error('[approve-review] notification: claim RPC failed —', rpcErr.message);
    return;
  }

  if (!rows || rows.length === 0) {
    console.log('[approve-review] notification: skipped — already sent, guest, claim active, or not found');
    return;
  }

  const { reviewer_email, reviewer_name, trainer_name, trainer_id, review_id } = rows[0];

  console.log('[approve-review] notification: claim succeeded | review_id:', review_id);

  if (!reviewer_email) {
    console.warn('[approve-review] notification: no email address | review_id:', review_id);
    return;
  }

  const profileUrl = `${SITE_URL}/trainers/${trainer_id}`;
  const firstName  = reviewer_name ? reviewer_name.trim().split(/\s+/)[0] : 'there';
  const html       = buildApprovalEmail(firstName, trainer_name, profileUrl);

  console.log('[approve-review] notification: sending via Resend | review_id:', review_id);

  const res = await fetch('https://api.resend.com/emails', {
    method:  'POST',
    headers: {
      'Content-Type':    'application/json',
      'Authorization':   `Bearer ${resendKey}`,
      'Idempotency-Key': `coachcards-approval-${review_id}`,
    },
    body: JSON.stringify({
      from:    FROM_ADDRESS,
      to:      [reviewer_email],
      subject: 'Your CoachCards review is now live',
      html,
    }),
  });

  const resBody = await res.text();

  if (!res.ok) {
    console.error(`[approve-review] notification: Resend rejected | review_id: ${review_id} status: ${res.status} body: ${resBody}`);
    return;
  }

  console.log(`[approve-review] notification: Resend accepted | review_id: ${review_id} status: ${res.status}`);

  const { error: confirmErr } = await supabaseService.rpc(
    'confirm_approval_notification',
    { p_review_id: review_id }
  );

  if (confirmErr) {
    console.error(`[approve-review] notification: confirm failed (email was sent) | review_id: ${review_id} —`, confirmErr.message);
  } else {
    console.log(`[approve-review] notification: confirmed in Supabase | review_id: ${review_id}`);
  }
}

// ── Email template ─────────────────────────────────────────────────────────
function buildApprovalEmail(firstName, trainerName, profileUrl) {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Your CoachCards review is now live</title>
</head>
<body style="margin:0;padding:0;background:#f4f6f4;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f4;padding:40px 16px;">
  <tr><td align="center">
    <table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">

      <!-- ── Header ── -->
      <tr><td style="background:linear-gradient(160deg,#0d1a0e 0%,#1a3d1e 60%,#2a5a30 100%);border-radius:16px 16px 0 0;padding:40px 40px 36px;text-align:center;">
        <div style="display:inline-block;background:white;border:2px solid #3ab54a;border-radius:10px;padding:8px 16px;margin-bottom:24px;">
          <span style="font-family:Georgia,serif;font-size:22px;font-weight:900;color:#0d1a0e;letter-spacing:-0.5px;"><span style="color:#3ab54a;">Coach</span>Cards</span>
        </div>
        <div style="display:inline-block;background:rgba(58,181,74,0.15);border:1px solid rgba(58,181,74,0.35);border-radius:50px;padding:8px 20px;margin-bottom:20px;">
          <span style="font-size:11px;font-weight:800;letter-spacing:2.5px;text-transform:uppercase;color:#7de88a;">Review Approved ✓</span>
        </div>
        <h1 style="margin:0 0 8px;font-family:Georgia,serif;font-size:28px;font-weight:900;color:white;line-height:1.2;">Your review is now live</h1>
        <p style="margin:0;font-size:15px;color:rgba(255,255,255,0.65);line-height:1.6;">Your feedback is helping others find the right trainer.</p>
      </td></tr>

      <!-- ── Body ── -->
      <tr><td style="background:white;padding:40px;">

        <p style="margin:0 0 24px;font-size:15px;color:#3a4a3b;line-height:1.7;">
          Hi ${firstName}, your review of <strong style="color:#0d1a0e;">${trainerName}</strong> has been approved and is now live on CoachCards.
        </p>

        <!-- Confirmed box -->
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:28px;">
          <tr><td style="background:#eaf7ec;border:1px solid #c0e8c6;border-left:4px solid #3ab54a;border-radius:12px;padding:20px 24px;">
            <table cellpadding="0" cellspacing="0">
              <tr>
                <td width="40" valign="middle" style="padding-right:14px;">
                  <div style="width:34px;height:34px;background:#3ab54a;border-radius:50%;text-align:center;line-height:34px;font-size:16px;color:white;font-weight:900;">✓</div>
                </td>
                <td valign="middle">
                  <div style="font-weight:700;font-size:14px;color:#0d1a0e;margin-bottom:3px;">Review published</div>
                  <div style="font-size:13px;color:#5a7a5c;line-height:1.5;">Your review of <strong>${trainerName}</strong> is now visible on their CoachCards profile.</div>
                </td>
              </tr>
            </table>
          </td></tr>
        </table>

        <p style="margin:0 0 28px;font-size:14px;color:#7a8f7c;line-height:1.75;">
          Thank you for sharing your experience and helping others find the right personal trainer. Every verified review makes CoachCards more useful for the fitness community.
        </p>

        <!-- CTA -->
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:36px;">
          <tr><td align="center">
            <a href="${profileUrl}" style="display:inline-block;background:#3ab54a;color:white;font-weight:700;font-size:15px;text-decoration:none;padding:14px 36px;border-radius:10px;">
              View ${trainerName}&rsquo;s profile &rarr;
            </a>
          </td></tr>
        </table>

        <hr style="border:none;border-top:1px solid #e8ede9;margin:0 0 28px;">
        <p style="margin:0;font-size:13px;color:#7a8f7c;line-height:1.7;">
          If you have any questions, just reply to this email.<br>
          <strong style="color:#0d1a0e;">The CoachCards team</strong>
        </p>

      </td></tr>

      <!-- ── Footer ── -->
      <tr><td style="background:#f4f6f4;border-radius:0 0 16px 16px;padding:24px 40px;text-align:center;">
        <p style="margin:0 0 6px;font-size:12px;color:#aab8ac;">CoachCards &mdash; The UK&rsquo;s verified PT ranking platform</p>
        <p style="margin:0;font-size:11px;color:#c0cac1;">
          <a href="https://coachcards.co.uk/privacy" style="color:#aab8ac;text-decoration:none;">Privacy Policy</a>
          &nbsp;&middot;&nbsp;
          <a href="https://coachcards.co.uk/terms" style="color:#aab8ac;text-decoration:none;">Terms</a>
        </p>
      </td></tr>

    </table>
  </td></tr>
</table>
</body>
</html>`;
}

function successPage(reviewerName) {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Review Approved — CoachCards</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:white;border-radius:20px;padding:48px 40px;max-width:420px;width:90%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="font-size:56px;margin-bottom:16px;">✅</div>
    <div style="font-size:22px;font-weight:800;color:#0d1a0e;margin-bottom:10px;">Review Approved</div>
    <div style="font-size:14px;color:#7a8f7c;line-height:1.7;margin-bottom:28px;">
      ${reviewerName}'s review is now live on their trainer's profile and will count towards the BMP score.
    </div>
    <a href="https://coachcards.co.uk" style="display:inline-block;background:#3ab54a;color:white;text-decoration:none;padding:12px 28px;border-radius:10px;font-weight:700;font-size:14px;">
      Back to CoachCards →
    </a>
  </div>
</body>
</html>`;
}

function alreadyApprovedPage() {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Already Approved — CoachCards</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:white;border-radius:20px;padding:48px 40px;max-width:420px;width:90%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="font-size:56px;margin-bottom:16px;">✅</div>
    <div style="font-size:22px;font-weight:800;color:#0d1a0e;margin-bottom:10px;">Already Approved</div>
    <div style="font-size:14px;color:#7a8f7c;line-height:1.7;margin-bottom:28px;">
      This review has already been approved and is live on the trainer's profile.
    </div>
    <a href="https://coachcards.co.uk" style="display:inline-block;background:#3ab54a;color:white;text-decoration:none;padding:12px 28px;border-radius:10px;font-weight:700;font-size:14px;">
      Back to CoachCards →
    </a>
  </div>
</body>
</html>`;
}

function rejectedPage(reviewerName) {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Review Rejected — CoachCards</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:white;border-radius:20px;padding:48px 40px;max-width:420px;width:90%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="font-size:56px;margin-bottom:16px;">🗑️</div>
    <div style="font-size:22px;font-weight:800;color:#0d1a0e;margin-bottom:10px;">Review Deleted</div>
    <div style="font-size:14px;color:#7a8f7c;line-height:1.7;margin-bottom:28px;">
      ${reviewerName}'s review has been permanently removed and will not appear on any profile.
    </div>
    <a href="https://coachcards.co.uk" style="display:inline-block;background:#3ab54a;color:white;text-decoration:none;padding:12px 28px;border-radius:10px;font-weight:700;font-size:14px;">
      Back to CoachCards →
    </a>
  </div>
</body>
</html>`;
}

function errorPage(message) {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Approval Error — CoachCards</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:white;border-radius:20px;padding:48px 40px;max-width:420px;width:90%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="font-size:56px;margin-bottom:16px;">⚠️</div>
    <div style="font-size:22px;font-weight:800;color:#0d1a0e;margin-bottom:10px;">Unable to Action</div>
    <div style="font-size:14px;color:#7a8f7c;line-height:1.7;">${message}</div>
  </div>
</body>
</html>`;
}
