const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? '';
const FROM_ADDRESS   = 'CoachCards <hello@coachcards.co.uk>';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const payload = await req.json();
    const record  = payload.record;

    if (!record?.email || !record?.name) {
      return new Response('Missing email or name', { status: 400, headers: corsHeaders });
    }

    const firstName = record.name.split(' ')[0] || record.name;
    const html = buildEmail(firstName, record.name);

    const res = await fetch('https://api.resend.com/emails', {
      method:  'POST',
      headers: {
        'Authorization': `Bearer ${RESEND_API_KEY}`,
        'Content-Type':  'application/json',
      },
      body: JSON.stringify({
        from:    FROM_ADDRESS,
        to:      [record.email],
        subject: `Welcome to CoachCards, ${firstName}!`,
        html,
      }),
    });

    if (!res.ok) {
      const err = await res.text();
      console.error('Resend error:', err);
      return new Response(err, { status: 500, headers: corsHeaders });
    }

    return new Response(JSON.stringify({ sent: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  } catch (e) {
    console.error(e);
    return new Response(String(e), { status: 500, headers: corsHeaders });
  }
});

function buildEmail(firstName: string, fullName: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>Welcome to CoachCards</title>
</head>
<body style="margin:0;padding:0;background:#f4f6f4;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">
<table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f6f4;padding:40px 16px;">
  <tr><td align="center">
    <table width="600" cellpadding="0" cellspacing="0" style="max-width:600px;width:100%;">
      <tr><td style="background:linear-gradient(160deg,#0d1a0e 0%,#1a3d1e 60%,#2a5a30 100%);border-radius:16px 16px 0 0;padding:40px 40px 36px;text-align:center;">
        <div style="display:inline-block;background:white;border:2px solid #3ab54a;border-radius:10px;padding:8px 16px;margin-bottom:24px;">
          <span style="font-family:Georgia,serif;font-size:22px;font-weight:900;color:#0d1a0e;letter-spacing:-0.5px;"><span style="color:#3ab54a;">Coach</span>Cards</span>
        </div>
        <h1 style="margin:0 0 8px;font-family:Georgia,serif;font-size:32px;font-weight:900;color:white;line-height:1.15;">Welcome, ${firstName}!</h1>
        <p style="margin:0;font-size:15px;color:rgba(255,255,255,0.6);line-height:1.6;">Your CoachCards profile is live. Here's how to get your first verified review.</p>
      </td></tr>
      <tr><td style="background:white;padding:40px;">
        <p style="margin:0 0 28px;font-size:15px;color:#3a4a3b;line-height:1.7;">Hi ${firstName}, you're now part of the UK's first verified personal trainer ranking platform.</p>
        <p style="margin:0 0 16px;font-size:11px;font-weight:700;letter-spacing:2px;text-transform:uppercase;color:#3ab54a;">Your next steps</p>
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:12px;">
          <tr><td width="44" valign="top"><div style="width:36px;height:36px;border-radius:50%;background:#eaf7ec;text-align:center;line-height:36px;font-size:18px;">👤</div></td>
          <td style="padding-left:14px;vertical-align:top;"><div style="font-weight:700;font-size:14px;color:#0d1a0e;margin-bottom:3px;">Complete your profile</div><div style="font-size:13px;color:#7a8f7c;line-height:1.5;">Add a photo, bio and your specialisms.</div></td></tr>
        </table>
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:12px;">
          <tr><td width="44" valign="top"><div style="width:36px;height:36px;border-radius:50%;background:#eaf7ec;text-align:center;line-height:36px;font-size:18px;">🔗</div></td>
          <td style="padding-left:14px;vertical-align:top;"><div style="font-weight:700;font-size:14px;color:#0d1a0e;margin-bottom:3px;">Generate your review link</div><div style="font-size:13px;color:#7a8f7c;line-height:1.5;">Send it to a client after your next session.</div></td></tr>
        </table>
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:32px;">
          <tr><td width="44" valign="top"><div style="width:36px;height:36px;border-radius:50%;background:#eaf7ec;text-align:center;line-height:36px;font-size:18px;">🏆</div></td>
          <td style="padding-left:14px;vertical-align:top;"><div style="font-weight:700;font-size:14px;color:#0d1a0e;margin-bottom:3px;">Start climbing the rankings</div><div style="font-size:13px;color:#7a8f7c;line-height:1.5;">Every verified review improves your BMP score.</div></td></tr>
        </table>
        <table width="100%" cellpadding="0" cellspacing="0" style="margin-bottom:36px;">
          <tr><td align="center"><a href="https://coachcards.co.uk/dashboard" style="display:inline-block;background:#3ab54a;color:white;font-weight:700;font-size:15px;text-decoration:none;padding:14px 36px;border-radius:10px;">Go to my dashboard &rarr;</a></td></tr>
        </table>
        <hr style="border:none;border-top:1px solid #e8ede9;margin:0 0 28px;">
        <p style="margin:0;font-size:13px;color:#7a8f7c;line-height:1.7;">If you have any questions, just reply to this email.<br><strong style="color:#0d1a0e;">The CoachCards team</strong></p>
      </td></tr>
      <tr><td style="background:#f4f6f4;border-radius:0 0 16px 16px;padding:24px 40px;text-align:center;">
        <p style="margin:0 0 6px;font-size:12px;color:#aab8ac;">CoachCards &mdash; The UK's verified PT ranking platform</p>
        <p style="margin:0;font-size:11px;color:#c0cac1;"><a href="https://coachcards.co.uk/privacy" style="color:#aab8ac;text-decoration:none;">Privacy Policy</a> &nbsp;&middot;&nbsp; <a href="https://coachcards.co.uk/terms" style="color:#aab8ac;text-decoration:none;">Terms</a></p>
      </td></tr>
    </table>
  </td></tr>
</table>
</body>
</html>`;
}
