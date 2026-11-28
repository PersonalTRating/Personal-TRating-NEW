/**
 * Assign a trainer's ranking area from their STATED location.
 *
 * POST { postcode_district? }   Authorization: Bearer <supabase_access_token>
 *
 *   postcode_district given  → validated (outward code), looked up, saved.
 *   postcode_district absent → uses the district already on the trainer row;
 *                              if there is none, falls back to the stated city.
 *
 * Country and local area are derived server-side and written through
 * cc_assign_stated_location() (service_role only). Device location plays no
 * part here. Full postcodes are never accepted or stored.
 *
 * Do NOT log postcodes, JWTs or email addresses.
 */

import { createClient } from '@supabase/supabase-js';
import { normaliseDistrict, resolveDistrict, resolveCity } from '../lib/ukArea.js';
import { POSTCODE_DISTRICT_ERROR } from '../../src/lib/postcodeDistrict.js';

const SUPABASE_URL     = process.env.PUBLIC_SUPABASE_URL;
const SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const MAX_BODY_BYTES   = 1024;

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

  let district = null;
  if (body.postcode_district !== undefined) {
    district = normaliseDistrict(body.postcode_district);
    if (!district) {
      return json(400, { error: POSTCODE_DISTRICT_ERROR });
    }
  }

  if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
    console.error('[assign-location] Missing SUPABASE_URL or SERVICE_ROLE_KEY env vars');
    return json(500, { error: 'Server configuration error' });
  }
  const db = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, { auth: { persistSession: false } });

  const { data: { user }, error: authErr } = await db.auth.getUser(jwt);
  if (authErr || !user) return json(401, { error: 'Invalid or expired session — please refresh the page' });

  const { data: trainer, error: trainerErr } = await db
    .from('trainers')
    .select('id, city, postcode_district')
    .eq('user_id', user.id)
    .maybeSingle();
  if (trainerErr || !trainer) return json(404, { error: 'Trainer record not found' });

  if (body.postcode_district === undefined) district = normaliseDistrict(trainer.postcode_district);

  let area;
  let source;
  try {
    if (district) {
      const r = await resolveDistrict(db, district, trainer.city);
      if (!r.found) {
        return json(422, { error: `We couldn't find postcode district ${district}. Please check it and try again.` });
      }
      area = r;
      source = 'postcode';
    } else {
      area = await resolveCity(db, trainer.city);
      source = 'city';
      if (!area) return json(422, { error: 'Add your postcode district so we can place you in country and local rankings.' });
    }
  } catch (err) {
    console.error('[assign-location] lookup failed:', err.message);
    return json(503, { error: 'Location lookup failed — please try again in a moment.' });
  }

  const { data: rpc, error: rpcErr } = await db.rpc('cc_assign_stated_location', {
    p_trainer_id:        trainer.id,
    p_postcode_district: district,
    p_cc_country:        area.cc_country,
    p_cc_local_area:     area.local_area_id,
    p_source:            source,
  });
  if (rpcErr || !rpc?.success) {
    console.error('[assign-location] cc_assign_stated_location failed:', rpcErr?.message);
    return json(500, { error: 'Failed to save location. Please try again.' });
  }

  let localName = null;
  if (area.local_area_id) {
    const { data: ad } = await db.rpc('get_ranking_area_display', { p_area_id: area.local_area_id });
    localName = (Array.isArray(ad) ? ad[0] : ad)?.display_name ?? null;
  }

  return json(200, {
    success:           true,
    postcode_district: district,
    cc_country:        area.cc_country,
    local_area_id:     area.local_area_id,
    local_name:        localName,
    source,
  });
};
