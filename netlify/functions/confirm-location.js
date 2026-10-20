/**
 * Secure trainer location confirmation.
 *
 * Accepts: POST { postcode, source }
 *          Authorization: Bearer <supabase_access_token>
 *
 * Security guarantees:
 *   1. JWT verified via db.auth.getUser() — only the trainer who
 *      owns the session can confirm.
 *   2. Trainer record found via user_id = auth.uid() — client
 *      cannot specify a different trainer.
 *   3. Postcodes.io called server-side — browser never supplies
 *      country, county or district. Fabricated values have no
 *      effect because the browser sends only the postcode.
 *   4. resolve_postcode_area() called server-side — area mapping
 *      is authoritative.
 *   5. cc_confirm_location_atomic() RPC writes to both trainers
 *      and trainer_private in a single PostgreSQL transaction.
 *      If either write fails, both roll back — no partial state.
 *   6. Cooldown enforced inside the transaction via the UPDATE
 *      WHERE clause. PostgreSQL row lock prevents concurrent
 *      requests from both succeeding.
 *   7. The RPC is REVOKE'd from anon and authenticated — only
 *      service_role (this function) can call it.
 *   8. cc_postcode is never stored on the public trainers table
 *      and is not included in RPC responses.
 *
 * Required Netlify environment variables:
 *   SUPABASE_SERVICE_ROLE_KEY  — never exposed to the browser
 *   PUBLIC_SUPABASE_URL        — already in the build environment
 *
 * Do NOT log postcodes, JWTs or email addresses.
 */

import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL     = process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

const MAX_BODY_BYTES    = 4096;
const UK_POSTCODE_RE    = /^[A-Z]{1,2}[0-9][0-9A-Z]? [0-9][A-Z]{2}$/;
const SUPPORTED_NATIONS = new Set(['England', 'Scotland', 'Wales', 'Northern Ireland']);

function jsonResponse(statusCode, body) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

export const handler = async (event) => {

  // ── Method guard ─────────────────────────────────────────────────────────
  if (event.httpMethod !== 'POST') {
    return jsonResponse(405, { error: 'Method not allowed' });
  }

  // ── 1. Request body size check ───────────────────────────────────────────
  if (event.body && event.body.length > MAX_BODY_BYTES) {
    return jsonResponse(413, { error: 'Request body too large' });
  }

  // ── 2. Extract Bearer token ──────────────────────────────────────────────
  const authHeader = event.headers?.authorization ?? event.headers?.Authorization ?? '';
  const jwt = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : null;
  if (!jwt) {
    return jsonResponse(401, { error: 'Authorization header required' });
  }

  // ── 3. Parse and validate input ──────────────────────────────────────────
  let body;
  try {
    body = JSON.parse(event.body ?? '{}');
  } catch {
    return jsonResponse(400, { error: 'Invalid JSON body' });
  }

  const rawPostcode = String(body.postcode ?? '').trim().toUpperCase().replace(/\s+/g, ' ');
  const source      = body.source === 'geolocation' ? 'geolocation' : 'postcode';

  if (!rawPostcode) {
    return jsonResponse(400, { error: 'postcode is required' });
  }
  if (!UK_POSTCODE_RE.test(rawPostcode)) {
    return jsonResponse(400, { error: 'Invalid UK postcode format' });
  }

  // ── 4. Initialise service-role client ────────────────────────────────────
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    console.error('[confirm-location] Missing SUPABASE_URL or SERVICE_ROLE_KEY env vars');
    return jsonResponse(500, { error: 'Server configuration error' });
  }
  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  // ── 5. Verify trainer identity via JWT ───────────────────────────────────
  // auth.getUser(jwt) validates the token with Supabase Auth and returns the
  // verified user. We never trust a trainer_id from the request body.
  const { data: { user }, error: authErr } = await db.auth.getUser(jwt);
  if (authErr || !user) {
    return jsonResponse(401, { error: 'Invalid or expired session — please refresh the page' });
  }

  // ── 6. Load trainer record ───────────────────────────────────────────────
  // trainer.id is derived server-side from user.id (JWT-verified).
  // This is the value passed to cc_confirm_location_atomic — the client
  // cannot supply or influence which trainer is confirmed.
  const { data: trainer, error: trainerErr } = await db
    .from('trainers')
    .select('id, location_confirmed, location_cooldown_until')
    .eq('user_id', user.id)
    .eq('is_active', true)
    .maybeSingle();

  if (trainerErr || !trainer) {
    return jsonResponse(404, { error: 'Trainer record not found' });
  }

  // ── 7. Early cooldown check (UX fast-fail; non-authoritative) ────────────
  // Avoids an unnecessary Postcodes.io round-trip for trainers already in
  // cooldown. The authoritative cooldown guard is inside the RPC (step 11).
  if (trainer.location_confirmed && trainer.location_cooldown_until) {
    if (new Date(trainer.location_cooldown_until) > new Date()) {
      const endDate = new Date(trainer.location_cooldown_until).toLocaleDateString('en-GB', {
        day: 'numeric', month: 'long', year: 'numeric',
      });
      return jsonResponse(409, {
        error:          `Your location is locked until ${endDate}. Contact support if you need to change it sooner.`,
        cooldown_until: trainer.location_cooldown_until,
      });
    }
  }

  // ── 8. Authoritative postcode validation via Postcodes.io ────────────────
  // The SERVER calls Postcodes.io. The browser never supplies country, county
  // or district — those are determined here from the trusted API response.
  let pcResult;
  try {
    const resp = await fetch(
      `https://api.postcodes.io/postcodes/${encodeURIComponent(rawPostcode)}`
    );
    const json = await resp.json();
    if (json.status !== 200 || !json.result) {
      return jsonResponse(422, { error: 'Postcode not found. Please check and try again.' });
    }
    pcResult = json.result;
  } catch (err) {
    console.error('[confirm-location] Postcodes.io fetch failed:', err.message);
    return jsonResponse(503, { error: 'Postcode lookup failed — please try again in a moment.' });
  }

  const adminCounty   = pcResult.admin_county   ?? null;
  const adminDistrict = pcResult.admin_district ?? null;
  const country       = pcResult.country        ?? null;

  if (!country || !SUPPORTED_NATIONS.has(country)) {
    return jsonResponse(422, {
      error: `Postcode '${rawPostcode}' is not in England, Scotland, Wales or Northern Ireland.`,
    });
  }

  // ── 9. Server-side geographical area resolution ──────────────────────────
  // resolve_postcode_area() maps the trusted Postcodes.io fields to a
  // ranking_areas.id. The client has no input into this resolution.
  const { data: resolveData, error: resolveErr } = await db.rpc('resolve_postcode_area', {
    p_admin_county:   adminCounty,
    p_admin_district: adminDistrict,
    p_country:        country,
  });

  if (resolveErr) {
    console.error('[confirm-location] resolve_postcode_area failed:', resolveErr.message);
    return jsonResponse(503, { error: 'Area resolution failed — please try again.' });
  }

  const resolved    = Array.isArray(resolveData) ? resolveData[0] : resolveData;
  const ccCountry   = resolved?.cc_country    ?? null;
  const localAreaId = resolved?.local_area_id ?? null;

  // cc_country is NULL only for unsupported postcodes (Channel Islands etc.).
  // We already checked the raw country above, but resolve_postcode_area() is
  // the authoritative mapping. Reject if it cannot confirm a UK country.
  if (!ccCountry) {
    return jsonResponse(422, {
      error: 'Could not resolve a geographical country for this postcode. Please contact support.',
    });
  }
  // localAreaId may be null (valid: trainer gets country ranking only).

  // ── 10. Prepare timestamps ───────────────────────────────────────────────
  const now           = new Date().toISOString();
  const cooldownUntil = new Date(Date.now() + 90 * 24 * 60 * 60 * 1000).toISOString();

  // ── 11. Atomic confirmation — single PostgreSQL transaction ──────────────
  // cc_confirm_location_atomic() writes to both trainers (geo columns) and
  // trainer_private (cc_postcode) in one transaction. If either write fails,
  // both roll back — the trainer cannot end up confirmed without a stored
  // postcode, or vice versa.
  //
  // The cooldown WHERE clause is evaluated inside the transaction with a
  // row lock, so two concurrent requests cannot both succeed.
  //
  // Only service_role may execute this RPC (REVOKE from PUBLIC in the DB).
  // p_trainer_id was derived server-side from the verified JWT (steps 5–6),
  // not supplied by the client.
  const { data: rpcResult, error: rpcErr } = await db.rpc(
    'cc_confirm_location_atomic',
    {
      p_trainer_id:     trainer.id,
      p_postcode:       rawPostcode,
      p_cc_country:     ccCountry,
      p_cc_local_area:  localAreaId,
      p_source:         source,
      p_confirmed_at:   now,
      p_cooldown_until: cooldownUntil,
    }
  );

  if (rpcErr) {
    console.error('[confirm-location] cc_confirm_location_atomic failed:', rpcErr.message);
    return jsonResponse(500, { error: 'Failed to save location. Please try again.' });
  }

  if (!rpcResult?.success) {
    // Cooldown became active between step 7 (early check) and this write —
    // a concurrent request won the race. Return the active cooldown_until.
    const coolEnd = rpcResult?.cooldown_until ?? null;
    const endDate = coolEnd
      ? new Date(coolEnd).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })
      : 'an unknown date';
    return jsonResponse(409, {
      error:          `Your location is locked until ${endDate}. Contact support if you need to change it sooner.`,
      cooldown_until: coolEnd,
    });
  }

  // ── 12. Fetch local area display name for immediate UI update ────────────
  let localName = null;
  if (localAreaId) {
    const { data: areaData } = await db.rpc('get_ranking_area_display', {
      p_area_id: localAreaId,
    });
    const areaRow = Array.isArray(areaData) ? areaData[0] : areaData;
    localName = areaRow?.display_name ?? null;
  }

  console.log('[confirm-location] confirmed trainer:', trainer.id,
              'country:', ccCountry, 'area:', localAreaId ?? 'none');

  return jsonResponse(200, {
    success:        true,
    postcode:       rawPostcode,
    cc_country:     ccCountry,
    local_area_id:  localAreaId,
    local_name:     localName,
    cooldown_until: cooldownUntil,
  });
};
