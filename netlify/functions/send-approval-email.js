import { createClient } from '@supabase/supabase-js';

const RESEND_API_KEY = process.env.RESEND_API_KEY             ?? '';
const SUPABASE_URL   = process.env.PUBLIC_SUPABASE_URL        ?? '';
const SUPABASE_SVC   = process.env.SUPABASE_SERVICE_ROLE_KEY  ?? '';
const SITE_URL       = process.env.SITE_URL ?? 'https://coachcards.co.uk';
const ADMIN_EMAIL    = 'modernisetraders@hotmail.com';
const FROM_ADDRESS   = 'CoachCards <hello@coachcards.co.uk>';

// Service-role client — never exposed to the browser.
// All DB calls (JWT verification + claim functions) go through this.
const supabaseService = SUPABASE_SVC
  ? createClient(SUPABASE_URL, SUPABASE_SVC, { auth: { persistSession: false } })
  : null;

export const handler = async (event) => {
  if (event.httpMethod !== 'POST') {
    return { statusCode: 405, body: 'Method not allowed' };
  }

  // ── Guard: service role key must be configured ────────────────────────────
  if (!supabaseService) {
    console.error('[send-approval-email] SUPABASE_SERVICE_ROLE_KEY not set');
    return { statusCode: 500, body: 'server_misconfigured' };
  }

  // ── 1. Verify the caller is the admin ────────────────────────────────────
  // The admin dashboard sends its Supabase session token in Authorization.
  // supabase.auth.getUser() verifies the JWT cryptographically using the
  // service role key — this cannot be forged without the project JWT secret.
  const authHeader = event.headers['authorization'] || event.headers['Authorization'] || '';
  const jwt = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (!jwt) {
    return { statusCode: 401, body: 'Unauthorized' };
  }

  const { data: { user }, error: authErr } = await supabaseService.auth.getUser(jwt);
  if (authErr || !user) {
    console.warn('[send-approval-email] JWT verification failed:', authErr?.message);
    return { statusCode: 401, body: 'Invalid token' };
  }
  if (user.email !== ADMIN_EMAIL) {
    console.warn('[send-approval-email] Forbidden — caller:', user.email);
    return { statusCode: 403, body: 'Forbidden' };
  }

  // ── 2. Parse body ─────────────────────────────────────────────────────────
  let body;
  try { body = JSON.parse(event.body || '{}'); }
  catch { return { statusCode: 400, body: 'Bad JSON' }; }

  const { reviewId } = body;
  console.log('[send-approval-email] invoked by admin | reviewId:', reviewId);

  if (!reviewId) {
    return { statusCode: 400, body: 'Missing reviewId' };
  }

  // ── 3. Atomically claim the notification slot ─────────────────────────────
  // claim_approval_notification is SECURITY DEFINER with no GRANT to anon/
  // authenticated — only reachable via service_role key (this function).
  // Returns empty set when: already sent, claim lock not yet expired,
  // not yet approved, review not found, or guest reviewer.
  const { data: rows, error: rpcErr } = await supabaseService.rpc(
    'claim_approval_notification',
    { p_review_id: reviewId }
  );

  if (rpcErr) {
    console.error('[send-approval-email] RPC error:', rpcErr.message);
    return { statusCode: 500, body: 'db_error' };
  }

  if (!rows || rows.length === 0) {
    console.log('[send-approval-email] Skipped — already sent, guest, claim active, or not approved.');
    return { statusCode: 200, body: 'skipped' };
  }

  const { reviewer_email, reviewer_name, trainer_name, trainer_id } = rows[0];

  if (!reviewer_email) {
    return { statusCode: 200, body: 'no_email' };
  }

  // ── 4. Send via Resend ────────────────────────────────────────────────────
  // Idempotency key: if this exact request is retried (claim expired, network
  // hiccup), Resend will not deliver a second email within its 24h window.
  const profileUrl = `${SITE_URL}/trainers/${trainer_id}`;
  const firstName  = reviewer_name ? reviewer_name.trim().split(/\s+/)[0] : 'there';
  const html       = buildApprovalEmail(firstName, trainer_name, profileUrl);

  let emailOk = false;
  try {
    const res = await fetch('https://api.resend.com/emails', {
      method:  'POST',
      headers: {
        'Content-Type':   'application/json',
        'Authorization':  `Bearer ${RESEND_API_KEY}`,
        'Idempotency-Key': `coachcards-approval-${reviewId}`,
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
      // notification_claimed_at will expire in 5 min, making this retryable.
      console.error(`[send-approval-email] Resend rejected | reviewId: ${reviewId} status: ${res.status} body: ${resBody}`);
      return { statusCode: 500, body: 'email_send_failed' };
    }

    console.log(`[send-approval-email] Resend accepted | reviewId: ${reviewId} status: ${res.status}`);
    emailOk = true;
  } catch (err) {
    console.error('[send-approval-email] fetch threw:', err.message);
    return { statusCode: 500, body: 'network_error' };
  }

  // ── 5. Confirm — set notification_sent_at only after Resend confirms ──────
  if (emailOk) {
    const { error: confirmErr } = await supabaseService.rpc(
      'confirm_approval_notification',
      { p_review_id: reviewId }
    );
    if (confirmErr) {
      // Email was sent. Log but don't fail — the slot stays claimed so a
      // subsequent retry with the same idempotency key won't double-send.
      console.error('[send-approval-email] confirm error (email was sent):', confirmErr.message);
    } else {
      console.log(`[send-approval-email] confirmed in Supabase | reviewId: ${reviewId}`);
    }
  }

  console.log(`[send-approval-email] notification complete | reviewId: ${reviewId}`);
  return { statusCode: 200, body: 'sent' };
};

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
        <img src="https://coachcards.co.uk/images/cc-logo.png" alt="CoachCards" width="64" height="64" style="display:block;margin:0 auto 24px;" />
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
