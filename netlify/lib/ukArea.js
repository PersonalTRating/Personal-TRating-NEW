/**
 * Shared UK area resolution for the location Netlify functions.
 *
 * Turns a stated postcode district (outward code, e.g. SW1, M4, EH1) or a
 * stated city into { cc_country, local_area_id } using Postcodes.io for the
 * ONS fields and the resolve_postcode_area() RPC for the ranking-area mapping.
 *
 * Never handles or stores full postcodes. Never logs inputs.
 */

export const DISTRICT_RE = /^[A-Z]{1,2}[0-9][A-Z0-9]?$/;
const SUPPORTED_NATIONS = new Set(['England', 'Scotland', 'Wales', 'Northern Ireland']);
const PCIO = 'https://api.postcodes.io';

/** "sw1 " → "SW1". Returns null when the value is not an outward code. */
export function normaliseDistrict(raw) {
  const v = String(raw ?? '').trim().toUpperCase().replace(/\s+/g, '');
  return DISTRICT_RE.test(v) ? v : null;
}

async function getJson(url) {
  const resp = await fetch(url);
  return resp.json();
}

function uniq(arr) {
  return [...new Set((arr || []).filter(Boolean))];
}

/**
 * Postcodes.io outcode lookup. Some London districts (SW1, W1, WC1, WC2,
 * EC1–EC4) exist only as sub-districts (SW1A, W1D …); when the plain
 * district is unknown and has a single trailing digit, the sub-districts
 * are merged instead.
 * Returns { countries, counties, districts } or null when not found.
 */
async function lookupOutcode(district) {
  const direct = await getJson(`${PCIO}/outcodes/${encodeURIComponent(district)}`);
  let results = direct.status === 200 && direct.result ? [direct.result] : [];

  if (!results.length && /^[A-Z]{1,2}[0-9]$/.test(district)) {
    const letters = 'ABCDEFGHJKLMNPRSTUVWXY'.split('');
    const subs = await Promise.all(
      letters.map(l => getJson(`${PCIO}/outcodes/${district}${l}`).catch(() => null))
    );
    results = subs.filter(s => s && s.status === 200 && s.result).map(s => s.result);
  }
  if (!results.length) return null;

  return {
    countries: uniq(results.flatMap(r => r.country)).filter(c => SUPPORTED_NATIONS.has(c)),
    counties:  uniq(results.flatMap(r => r.admin_county)),
    districts: uniq(results.flatMap(r => r.admin_district)),
  };
}

async function resolveArea(db, adminCounty, adminDistrict, country) {
  const { data, error } = await db.rpc('resolve_postcode_area', {
    p_admin_county:   adminCounty ?? null,
    p_admin_district: adminDistrict ?? null,
    p_country:        country,
  });
  if (error) throw new Error('resolve_postcode_area failed');
  const row = Array.isArray(data) ? data[0] : data;
  return { cc_country: row?.cc_country ?? null, local_area_id: row?.local_area_id ?? null };
}

/** Candidate areas for one ONS field set (county/district names per country). */
async function candidatesFor(db, countries, counties, districts) {
  const out = [];
  for (const country of countries) {
    const tries = country === 'England'
      ? [...counties.map(c => [c, null]), ...districts.map(d => [null, d])]
      : districts.map(d => [null, d]);
    for (const [cty, dist] of tries) {
      const r = await resolveArea(db, cty, dist, country);
      if (r.cc_country && r.local_area_id) out.push(r);
    }
    if (!out.some(r => r.cc_country === country)) out.push({ cc_country: country, local_area_id: null });
  }
  return out;
}

/** Stated city → area, via Postcodes.io place names. Null when unknown. */
export async function resolveCity(db, city) {
  const name = String(city ?? '').trim();
  if (!name) return null;
  const json = await getJson(`${PCIO}/places?q=${encodeURIComponent(name)}&limit=10`);
  const places = (json.result || []).filter(p => SUPPORTED_NATIONS.has(p.country));
  if (!places.length) return null;
  const exact = places.filter(p => String(p.name_1 || '').toLowerCase() === name.toLowerCase());
  const settlements = ['City', 'Town', 'Village', 'Suburban Area', 'Other Settlement', 'Hamlet'];
  const pick = [...exact, ...places]
    .sort((a, b) => settlements.indexOf(a.local_type) - settlements.indexOf(b.local_type))
    .find(p => settlements.includes(p.local_type)) || exact[0] || places[0];

  const county   = pick.county_unitary   || null;
  const district = pick.district_borough || null;
  const country  = pick.country;
  const tries = country === 'England'
    ? [[county, district], [null, county], [null, district]]
    : [[null, county], [null, district]];
  for (const [c, d] of tries) {
    if (!c && !d) continue;
    const r = await resolveArea(db, c, d, country);
    if (r.local_area_id) return r;
  }
  return { cc_country: country, local_area_id: null };
}

/**
 * Stated postcode district (+ stated city as tie-breaker) → area.
 * Returns { found: false } when Postcodes.io does not know the district.
 */
export async function resolveDistrict(db, district, city) {
  const oc = await lookupOutcode(district);
  if (!oc || !oc.countries.length) return { found: false };

  const cands = await candidatesFor(db, oc.countries, oc.counties, oc.districts);
  let chosen = cands.find(c => c.local_area_id) || cands[0];

  // A district can straddle a border or two areas (e.g. TD15, SE16).
  // When it does, prefer the area that matches the stated city.
  const distinct = uniq(cands.map(c => `${c.cc_country}|${c.local_area_id ?? ''}`));
  if (distinct.length > 1 && city) {
    const cityArea = await resolveCity(db, city).catch(() => null);
    if (cityArea) {
      chosen = cands.find(c => c.local_area_id && c.local_area_id === cityArea.local_area_id)
            || cands.find(c => c.cc_country === cityArea.cc_country && c.local_area_id)
            || cands.find(c => c.cc_country === cityArea.cc_country)
            || chosen;
    }
  }
  return { found: true, ...chosen };
}

/** Device coordinates → area. Coordinates are used for this lookup only. */
export async function resolveCoordinates(db, lat, lon) {
  const json = await getJson(`${PCIO}/postcodes?lon=${lon}&lat=${lat}&limit=1&radius=2000`);
  const pc = json.result?.[0];
  if (!pc || !SUPPORTED_NATIONS.has(pc.country)) return null;
  return resolveArea(db, pc.admin_county, pc.admin_district, pc.country);
}
