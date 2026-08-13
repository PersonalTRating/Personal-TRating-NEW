import { createClient } from '@supabase/supabase-js';

export const handler = async (event) => {
  const token  = event.queryStringParameters?.token;
  const action = event.queryStringParameters?.action || 'approve';

  if (!token) {
    return { statusCode: 400, headers: { 'Content-Type': 'text/html' }, body: errorPage('Invalid approval link.') };
  }

  const supabase = createClient(
    process.env.PUBLIC_SUPABASE_URL,
    process.env.PUBLIC_SUPABASE_ANON_KEY
  );

  if (action === 'reject') {
    const { data, error } = await supabase.rpc('reject_review_by_token', { p_token: token });

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
  const { data, error } = await supabase.rpc('approve_review_by_token', { p_token: token });

  if (error || !data || data === 'not_found') {
    return {
      statusCode: 400,
      headers: { 'Content-Type': 'text/html' },
      body: errorPage('This review has already been approved or the link is invalid.'),
    };
  }

  return {
    statusCode: 200,
    headers: { 'Content-Type': 'text/html' },
    body: successPage(data),
  };
};

function successPage(reviewerName) {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Review Approved — Personal TRating</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:white;border-radius:20px;padding:48px 40px;max-width:420px;width:90%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="font-size:56px;margin-bottom:16px;">✅</div>
    <div style="font-size:22px;font-weight:800;color:#0d1a0e;margin-bottom:10px;">Review Approved</div>
    <div style="font-size:14px;color:#7a8f7c;line-height:1.7;margin-bottom:28px;">
      ${reviewerName}'s review is now live on their trainer's profile and will count towards the BMP score.
    </div>
    <a href="https://personaltrating.com" style="display:inline-block;background:#3ab54a;color:white;text-decoration:none;padding:12px 28px;border-radius:10px;font-weight:700;font-size:14px;">
      Back to Personal TRating →
    </a>
  </div>
</body>
</html>`;
}

function rejectedPage(reviewerName) {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Review Rejected — Personal TRating</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:white;border-radius:20px;padding:48px 40px;max-width:420px;width:90%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="font-size:56px;margin-bottom:16px;">🗑️</div>
    <div style="font-size:22px;font-weight:800;color:#0d1a0e;margin-bottom:10px;">Review Deleted</div>
    <div style="font-size:14px;color:#7a8f7c;line-height:1.7;margin-bottom:28px;">
      ${reviewerName}'s review has been permanently removed and will not appear on any profile.
    </div>
    <a href="https://personaltrating.com" style="display:inline-block;background:#3ab54a;color:white;text-decoration:none;padding:12px 28px;border-radius:10px;font-weight:700;font-size:14px;">
      Back to Personal TRating →
    </a>
  </div>
</body>
</html>`;
}

function errorPage(message) {
  return `<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Approval Error — Personal TRating</title></head>
<body style="margin:0;padding:0;background:#f7f9f7;font-family:'Helvetica Neue',Arial,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;">
  <div style="background:white;border-radius:20px;padding:48px 40px;max-width:420px;width:90%;text-align:center;box-shadow:0 8px 40px rgba(0,0,0,0.08);">
    <div style="font-size:56px;margin-bottom:16px;">⚠️</div>
    <div style="font-size:22px;font-weight:800;color:#0d1a0e;margin-bottom:10px;">Unable to Action</div>
    <div style="font-size:14px;color:#7a8f7c;line-height:1.7;">${message}</div>
  </div>
</body>
</html>`;
}
