/**
 * Optional device-location check (trainer opts in from the dashboard).
 *
 * POST { lat, lon }   Authorization: Bearer <supabase_access_token>
 *
 * Compares the device's area with the trainer's STATED area:
 *   - trainer has a local area → device local area must equal it
 *   - otherwise                → device country must equal cc_country
 *
 * Match    → trainers.location_confirmed = TRUE (public "Location confirmed").
 * No match → trainers.location_confirmed = FALSE and the admin-only
 *            trainer_location_checks.location_mismatch = TRUE.
 *
 * The stated location (postcode_district / cc_country / cc_local_area) is
 * NEVER changed here. Coordinates are used for one Postcodes.io lookup and
 * then discarded: they are not stored, returned or logged.
 */

import { createClient } from '@supabase/supabase-js';
import { resolveCoordinates } from '../lib/ukArea.js';

const SUPABASE_URL     = process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const MAX_BODY_BYTES   = 512;

const json = (statusCode, body) => ({
  statusCode,
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(body),
});

export const handler = async (event) => {
  if (event.httpMethod !== 'POST') return json(405, { error: 'Method not allowed' });
  if (event.body && event.body.length > MAX_BODY_BYTES) return json(413, { error: 'Request body too large' });

  const authHeader = event.headers?.authorization ?? event.headers?.Authorization ?? '';
  const jwt = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : null;
  if (!jwt) return json(401, { error: 'Authorization header required' });

  let body;
  try { body = JSON.parse(event.body || '{}'); } catch { return json(400, { error: 'Invalid JSON body' }); }
  const lat = Number(body.lat);
  const lon = Number(body.lon);
  if (!Number.isFinite(lat) || !Number.isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) {
    return json(400, { error: 'Invalid coordinates' });
  }

  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    console.error('[check-device-location] Missing SUPABASE_URL or SERVICE_ROLE_KEY env vars');
    return json(500, { error: 'Server configuration error' });
  }
  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

  const { data: { user }, error: authErr } = await db.auth.getUser(jwt);
  if (authErr || !user) return json(401, { error: 'Invalid or expired session — please refresh the page' });

  const { data: trainer, error: trainerErr } = await db
    .from('trainers')
    .select('id, cc_country, cc_local_area')
    .eq('user_id', user.id)
    .maybeSingle();
  if (trainerErr || !trainer) return json(404, { error: 'Trainer record not found' });
  if (!trainer.cc_country) {
    return json(409, { error: 'Add your postcode district first, then check your device location.' });
  }

  let device;
  try {
    device = await resolveCoordinates(db, lat, lon); // null = no UK postcode nearby
  } catch {
    return json(503, { error: 'Location lookup failed — please try again in a moment.' });
  }

  const matched = !!device && (
    trainer.cc_local_area
      ? device.local_area_id === trainer.cc_local_area
      : device.cc_country === trainer.cc_country
  );

  const { error: rpcErr } = await db.rpc('cc_record_device_check', {
    p_trainer_id: trainer.id,
    p_matched:    matched,
  });
  if (rpcErr) {
    console.error('[check-device-location] cc_record_device_check failed:', rpcErr.message);
    return json(500, { error: 'Failed to save the check. Please try again.' });
  }

  return json(200, { success: true, matched });
};
