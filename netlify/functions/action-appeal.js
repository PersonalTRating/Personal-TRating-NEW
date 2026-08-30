import { createClient } from '@supabase/supabase-js';

export const handler = async (event) => {
  const qs     = event.queryStringParameters ?? {};
  const token  = qs.token;
  const action = qs.action || 'uphold';

  if (!token) {
    return { statusCode: 400, headers: { 'Content-Type': 'text/html' }, body: errorPage('Invalid appeal link.') };
  }

  // ── GET: show confirmation page with notes field ──────────────────────
  if (event.httpMethod !== 'POST') {
    return {
      statusCode: 200,
      headers: { 'Content-Type': 'text/html' },
      body: confirmPage(token, action),
    };
  }

  // ── POST: execute the action ──────────────────────────────────────────
  const params = new URLSearchParams(event.body ?? '');
  const notes  = params.get('notes')?.trim() ?? '';
  const pToken = params.get('token') ?? token;
  const pAction = params.get('action') ?? action;

  const supabase = createClient(
    process.env.PUBLIC_SUPABASE_URL,
    process.env.PUBLIC_SUPABASE_ANON_KEY
  );

  if (pAction === 'remove') {
    let data, error;
    try {
      ({ data, error } = await supabase.rpc('remove_appealed_review', { p_token: pToken, p_notes: notes }));
    } catch (e) {
      console.log('[action-appeal] remove threw:', e.message);
      return { statusCode: 500, headers: { 'Content-Type': 'text/html' }, body: errorPage('A server error occurred.') };
    }
    if (error || !data || data === 'not_found') {
      return { statusCode: 400, headers: { 'Content-Type': 'text/html' }, body: errorPage('This appeal has already been actioned or the link is invalid.') };
    }
    return { statusCode: 200, headers: { 'Content-Type': 'text/html' }, body: removedPage(data) };
  }

  // uphold
  let data, error;
  try {
    ({ data, error } = await supabase.rpc('uphold_appealed_review', { p_token: pToken, p_notes: notes }));
  } catch (e) {
    console.log('[action-appeal] uphold threw:', e.message);
    return { statusCode: 500, headers: { 'Content-Type': 'text/html' }, body: errorPage('A server error occurred.') };
  }
  if (error || !data || data === 'not_found') {
    return { statusCode: 400, headers: { 'Content-Type': 'text/html' }, body: errorPage('This appeal has already been actioned or the link is invalid.') };
  }
  return { statusCode: 200, headers: { 'Content-Type': 'text/html' }, body: upheldPage(data) };
};

// ── Pages ─────────────────────────────────────────────────────────────────

function confirmPage(token, action) {
  const isRemove  = action === 'remove';
  const accentClr = isRemove ? '#dc2626' : '#3ab54a';
  const icon      = isRemove ? '🗑️' : '✅';
  const heading   = isRemove ? 'Remove This Review?' : 'Uphold This Review?';
  const desc      = isRemove
    ? 'The review will be permanently deleted and the trainer\'s BMP score will be recalculated.'
    : 'The review will remain live on the trainer\'s profile. The appeal will be marked as rejected.';
  const btnLabel  = isRemove ? 'Confirm — Remove Review' : 'Confirm — Uphold Review';
  const notesLabel = isRemove
    ? 'Reason for removal (shared with trainer)'
    : 'Reason for upholding (shared with trainer)';

  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${heading} — CoachCards</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;padding:1rem;box-sizing:border-box;">
  <div style="background:white;border-radius:20px;max-width:480px;width:100%;overflow:hidden;box-shadow:0 8px 40px rgba(0,0,0,0.1);">
    <div style="background:linear-gradient(135deg,#0d1a0e,#1a3d1e);padding:28px 36px;">
      <div style="font-size:0.65rem;font-weight:700;letter-spacing:3px;text-transform:uppercase;color:#7de88a;margin-bottom:6px;">Review Appeal</div>
      <h1 style="margin:0;font-size:1.4rem;font-weight:900;color:white;">${icon} ${heading}</h1>
    </div>
    <div style="padding:28px 36px;">
      <p style="font-size:0.9rem;color:#3a4a3b;line-height:1.7;margin:0 0 1.5rem;">${desc}</p>
      <form method="POST">
        <input type="hidden" name="token"  value="${token}">
        <input type="hidden" name="action" value="${action}">
        <label style="display:block;font-size:0.78rem;font-weight:700;color:#111311;margin-bottom:0.4rem;">${notesLabel}</label>
        <textarea name="notes" rows="4" placeholder="Optional — will appear in the trainer's notification…"
          style="width:100%;box-sizing:border-box;border:1px solid #d0d8d1;border-radius:8px;padding:0.75rem;font-size:0.85rem;font-family:inherit;line-height:1.6;resize:vertical;color:#0d1a0e;"></textarea>
        <button type="submit"
          style="margin-top:1rem;width:100%;padding:14px;background:${accentClr};color:white;border:none;border-radius:10px;font-weight:700;font-size:0.9rem;cursor:pointer;font-family:inherit;">
          ${btnLabel}
        </button>
      </form>
      <a href="https://coachcards.com" style="display:block;text-align:center;margin-top:1rem;font-size:0.78rem;color:#7a8f7c;text-decoration:none;">← Back to CoachCards</a>
    </div>
  </div>
</body>
</html>`;
}

function removedPage(reviewerName) {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Review Removed — CoachCards</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:white;border-radius:20px;padding:48px 40px;max-width:420px;width:90%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="font-size:56px;margin-bottom:16px;">🗑️</div>
    <div style="font-size:22px;font-weight:800;color:#0d1a0e;margin-bottom:10px;">Review Removed</div>
    <div style="font-size:14px;color:#7a8f7c;line-height:1.7;margin-bottom:28px;">
      ${reviewerName}'s review has been permanently removed. The trainer's BMP score has been recalculated and they've been notified.
    </div>
    <a href="https://coachcards.com" style="display:inline-block;background:#3ab54a;color:white;text-decoration:none;padding:12px 28px;border-radius:10px;font-weight:700;font-size:14px;">Back to CoachCards →</a>
  </div>
</body>
</html>`;
}

function upheldPage(reviewerName) {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Review Upheld — CoachCards</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:white;border-radius:20px;padding:48px 40px;max-width:420px;width:90%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="font-size:56px;margin-bottom:16px;">✅</div>
    <div style="font-size:22px;font-weight:800;color:#0d1a0e;margin-bottom:10px;">Review Upheld</div>
    <div style="font-size:14px;color:#7a8f7c;line-height:1.7;margin-bottom:28px;">
      ${reviewerName}'s review will remain live. The trainer has been notified of the outcome.
    </div>
    <a href="https://coachcards.com" style="display:inline-block;background:#3ab54a;color:white;text-decoration:none;padding:12px 28px;border-radius:10px;font-weight:700;font-size:14px;">Back to CoachCards →</a>
  </div>
</body>
</html>`;
}

function errorPage(message) {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Appeal Error — CoachCards</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:white;border-radius:20px;padding:48px 40px;max-width:420px;width:90%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="font-size:56px;margin-bottom:16px;">⚠️</div>
    <div style="font-size:22px;font-weight:800;color:#0d1a0e;margin-bottom:10px;">Unable to Action</div>
    <div style="font-size:14px;color:#7a8f7c;line-height:1.7;">${message}</div>
  </div>
</body>
</html>`;
}
