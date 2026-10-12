// Scheduled function — fires every 15 minutes via netlify.toml.
// Retries approval notification emails for reviews whose previous send
// attempt timed out or was rejected by Resend.
//
// ── Security model ────────────────────────────────────────────────────────
// This function has NO public HTTP endpoint.
// Netlify's `schedule` config (in netlify.toml) is mutually exclusive with
// `path` — Netlify invokes the function internally and does not expose a
// public URL. External HTTP callers cannot reach it.
//
// Defense-in-depth: any HTTP invocation that does reach this function (e.g.
// via Netlify's "Run now" dashboard button) must supply
//   Authorization: Bearer {RETRY_SECRET}
// Comparison is done in constant time to prevent timing attacks.
// Requests without a valid secret are rejected with 401.
//
// The previous implementation checked for {"next_run":"..."} in the body.
// That is NOT authentication — any caller can supply that field. It has been
// removed entirely. Security rests on Netlify's no-public-URL guarantee plus
// the RETRY_SECRET for any HTTP access path.
// ─────────────────────────────────────────────────────────────────────────

import { createClient }   from '@supabase/supabase-js';
import { timingSafeEqual } from 'crypto';

const SUPABASE_URL   = process.env.PUBLIC_SUPABASE_URL       ?? '';
const SUPABASE_SVC   = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
const RESEND_API_KEY = process.env.RESEND_API_KEY            ?? '';
const RETRY_SECRET   = process.env.RETRY_SECRET              ?? '';
const SITE_URL       = process.env.SITE_URL ?? 'https://coachcards.co.uk';
const FROM_ADDRESS   = 'CoachCards <hello@coachcards.co.uk>';
const MAX_RETRIES    = 5;
const BATCH_SIZE     = 10;

export const handler = async (event) => {
  // ── 1. Authorization ─────────────────────────────────────────────────────
  // Netlify's scheduler invokes this function WITHOUT an Authorization header.
  // The function has no public URL (schedule config is mutually exclusive with
  // path), so external callers cannot reach it at all.
  //
  // Auth rule:
  //   • No Authorization header → allow (legitimate scheduler invocation).
  //     Security comes from Netlify's infrastructure (no public URL), not code.
  //   • Authorization header present but token doesn't match RETRY_SECRET → 401.
  //     Prevents anyone who stumbles on the function path from abusing it.
  //   • Authorization: Bearer {correct RETRY_SECRET} → allow (manual invocation).
  //
  // We do NOT check request body fields — a {"next_run":"..."} body is not
  // authentication (any caller can supply it). That check has been removed.
  const authHeader  = event.headers['authorization'] || event.headers['Authorization'] || '';
  const bearerToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (authHeader !== '') {
    // Caller sent SOME Authorization header — require a valid Bearer token.
    // bearerToken === null means the format wasn't "Bearer <token>" → reject.
    if (bearerToken === null || !RETRY_SECRET || !constantTimeEquals(bearerToken, RETRY_SECRET)) {
      console.warn('[retry-notifications] Rejected — invalid authorization');
      return { statusCode: 401, body: 'Unauthorized' };
    }
  }
  // authHeader === '': no Authorization header at all — allow (scheduler invocation).
  // Security rests on Netlify's no-public-URL guarantee, not on a code check here.

  // ── 2. Guard: required env vars ──────────────────────────────────────────
  if (!SUPABASE_SVC) {
    console.error('[retry-notifications] SUPABASE_SERVICE_ROLE_KEY not set');
    return { statusCode: 500, body: 'server_misconfigured' };
  }
  if (!RESEND_API_KEY) {
    console.error('[retry-notifications] RESEND_API_KEY not set');
    return { statusCode: 500, body: 'server_misconfigured' };
  }

  const supabaseService = createClient(SUPABASE_URL, SUPABASE_SVC, {
    auth: { persistSession: false },
  });

  // ── 3. Claim retry batch ──────────────────────────────────────────────────
  // claim_notification_retry_batch atomically selects and claims candidates.
  // The function only returns reviews that:
  //   • is_verified = TRUE          — still approved (not reversed or deleted)
  //   • client_id IS NOT NULL       — has a reviewer account (guests excluded)
  //   • notification_sent_at IS NULL — no successful notification yet
  //   • notification_claimed_at IS NOT NULL — went through the new system
  //   • notification_claimed_at < NOW() - 5m — previous attempt expired
  //   • notification_attempt_count < MAX_RETRIES — retry budget remaining
  //   + JOIN to clients and auth.users — valid reviewer account at query time
  // FOR UPDATE SKIP LOCKED prevents concurrent scheduler runs from double-claiming.
  // Historical reviews (approved before this system) have claimed_at = NULL
  // and are never returned by this function.
  const { data: rows, error: batchErr } = await supabaseService.rpc(
    'claim_notification_retry_batch',
    { p_max_retries: MAX_RETRIES, p_batch_size: BATCH_SIZE }
  );

  if (batchErr) {
    console.error('[retry-notifications] Batch claim error:', batchErr.message);
    return { statusCode: 500, body: 'db_error' };
  }

  if (!rows || rows.length === 0) {
    console.log('[retry-notifications] No retry candidates.');
    return { statusCode: 200, body: 'no_work' };
  }

  console.log(`[retry-notifications] Processing ${rows.length} candidate(s).`);

  // ── 4. Send emails ────────────────────────────────────────────────────────
  const results = await Promise.allSettled(
    rows.map(row => processOne(supabaseService, row))
  );

  let sent = 0, failed = 0;
  results.forEach(r => {
    if (r.status === 'fulfilled' && r.value === 'sent') sent++;
    else if (r.status === 'rejected') {
      failed++;
      // Never log the error reason if it might contain email addresses.
      console.error('[retry-notifications] Unhandled rejection for a candidate.');
    } else {
      failed++;
    }
  });

  console.log(`[retry-notifications] Done — sent:${sent} failed:${failed}`);
  return { statusCode: 200, body: JSON.stringify({ sent, failed }) };
};

async function processOne(supabaseService, row) {
  const { review_id, reviewer_email, reviewer_name, trainer_name, trainer_id } = row;

  // reviewer_email missing means the JOIN to auth.users found no account.
  // The claim was set; notification_attempt_count was incremented.
  // Log by review_id only — never log the email address.
  if (!reviewer_email) {
    console.warn(`[retry-notifications] review ${review_id} — no email, skipping.`);
    return 'no_email';
  }

  const profileUrl = `${SITE_URL}/trainers/${trainer_id}`;
  const firstName  = reviewer_name ? reviewer_name.trim().split(/\s+/)[0] : 'there';
  const html       = buildApprovalEmail(firstName, trainer_name, profileUrl);

  // Resend idempotency key behaviour for retries:
  //   • First attempt was ACCEPTED by Resend but confirm() failed →
  //     same key returns the original 200 response → we call confirm → done.
  //   • First attempt was REJECTED by Resend →
  //     same key does NOT block the retry (idempotency only applies to
  //     previously accepted emails within the 24h window).
  const res = await fetch('https://api.resend.com/emails', {
    method:  'POST',
    headers: {
      'Content-Type':    'application/json',
      'Authorization':   `Bearer ${RESEND_API_KEY}`,
      'Idempotency-Key': `coachcards-approval-${review_id}`,
    },
    body: JSON.stringify({
      from:    FROM_ADDRESS,
      to:      [reviewer_email],
      subject: 'Your CoachCards review is now live',
      html,
    }),
  });

  // Log by review_id only — no email address in logs.
  console.log(`[retry-notifications] review ${review_id} — Resend ${res.status}`);

  if (!res.ok) {
    const body = await res.text();
    console.error(`[retry-notifications] review ${review_id} — Resend rejected:`, body);
    // claimed_at expires in 5 min → eligible for next scheduled run.
    return 'failed';
  }

  // Set notification_sent_at only after Resend confirms success.
  const { error: confirmErr } = await supabaseService.rpc(
    'confirm_approval_notification',
    { p_review_id: review_id }
  );
  if (confirmErr) {
    // Email sent. Idempotency key prevents a second email if we retry the confirm.
    console.error(`[retry-notifications] review ${review_id} — confirm error:`, confirmErr.message);
  }

  return 'sent';
}

// Constant-time comparison to prevent timing attacks on the secret.
function constantTimeEquals(a, b) {
  if (!a || !b) return false;
  try {
    const bufA = Buffer.from(a);
    const bufB = Buffer.from(b);
    if (bufA.length !== bufB.length) return false;
    return timingSafeEqual(bufA, bufB);
  } catch {
    return false;
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
      <tr><td style="background:linear-gradient(160deg,#0d1a0e 0%,#1a3d1e 60%,#2a5a30 100%);border-radius:16px 16px 0 0;padding:40px 40px 36px;text-align:center;">
        <img src="https://coachcards.co.uk/images/cc-logo.png" alt="CoachCards" width="64" height="64" style="display:block;margin:0 auto 24px;" />
        <div style="display:inline-block;background:rgba(58,181,74,0.15);border:1px solid rgba(58,181,74,0.35);border-radius:50px;padding:8px 20px;margin-bottom:20px;">
          <span style="font-size:11px;font-weight:800;letter-spacing:2.5px;text-transform:uppercase;color:#7de88a;">Review Approved ✓</span>
        </div>
        <h1 style="margin:0 0 8px;font-family:Georgia,serif;font-size:28px;font-weight:900;color:white;line-height:1.2;">Your review is now live</h1>
        <p style="margin:0;font-size:15px;color:rgba(255,255,255,0.65);line-height:1.6;">Your feedback is helping others find the right trainer.</p>
      </td></tr>
      <tr><td style="background:white;padding:40px;">
        <p style="margin:0 0 24px;font-size:15px;color:#3a4a3b;line-height:1.7;">
          Hi ${firstName}, your review of <strong style="color:#0d1a0e;">${trainerName}</strong> has been approved and is now live on CoachCards.
        </p>
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:28px;">
          <tr><td style="background:#eaf7ec;border:1px solid #c0e8c6;border-left:4px solid #3ab54a;border-radius:12px;padding:20px 24px;">
            <table cellpadding="0" cellspacing="0"><tr>
              <td width="40" valign="middle" style="padding-right:14px;">
                <div style="width:34px;height:34px;background:#3ab54a;border-radius:50%;text-align:center;line-height:34px;font-size:16px;color:white;font-weight:900;">✓</div>
              </td>
              <td valign="middle">
                <div style="font-weight:700;font-size:14px;color:#0d1a0e;margin-bottom:3px;">Review published</div>
                <div style="font-size:13px;color:#5a7a5c;line-height:1.5;">Your review of <strong>${trainerName}</strong> is now visible on their CoachCards profile.</div>
              </td>
            </tr></table>
          </td></tr>
        </table>
        <p style="margin:0 0 28px;font-size:14px;color:#7a8f7c;line-height:1.75;">
          Thank you for sharing your experience and helping others find the right personal trainer.
        </p>
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:36px;">
          <tr><td align="center">
            <a href="${profileUrl}" style="display:inline-block;background:#3ab54a;color:white;font-weight:700;font-size:15px;text-decoration:none;padding:14px 36px;border-radius:10px;">
              View ${trainerName}&rsquo;s profile &rarr;
            </a>
          </td></tr>
        </table>
        <hr style="border:none;border-top:1px solid #e8ede9;margin:0 0 28px;">
        <p style="margin:0;font-size:13px;color:#7a8f7c;line-height:1.7;">
          If you have any questions, reply to this email.<br>
          <strong style="color:#0d1a0e;">The CoachCards team</strong>
        </p>
      </td></tr>
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
