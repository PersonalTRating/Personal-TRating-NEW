/**
 * UK postcode district (outward code) normalisation — one rule for signup,
 * the trainer dashboard and the assign-location Netlify function.
 *
 *   " sw1 "     → "SW1"     (trimmed, upper-cased)
 *   "SW1A 1AA"  → "SW1A"    (full postcode accepted; only the outward code is kept)
 *   "sw1a1aa"   → "SW1A"
 *   "London", "123", ""  → null  (rejected)
 *
 * Only the returned outward code is ever stored. Plain JS so the Netlify
 * functions can import it as well as the Astro pages.
 */

export const DISTRICT_RE = /^[A-Z]{1,2}[0-9][A-Z0-9]?$/;
const FULL_POSTCODE_RE = /^([A-Z]{1,2}[0-9][A-Z0-9]?) ?([0-9][A-Z]{2})$/;

export const POSTCODE_DISTRICT_ERROR =
  'Please enter your postcode district, e.g. SW1, M4 or EH1 (a full postcode also works — we only keep the first part).';

/** Returns the outward code (e.g. "SW1A"), or null when the input is not a UK postcode district. */
export function toPostcodeDistrict(raw) {
  const s = String(raw ?? '').toUpperCase().replace(/\s+/g, ' ').trim();
  if (!s) return null;
  const full = s.match(FULL_POSTCODE_RE);
  if (full) return full[1];
  const compact = s.replace(/ /g, '');
  return DISTRICT_RE.test(compact) ? compact : null;
}
