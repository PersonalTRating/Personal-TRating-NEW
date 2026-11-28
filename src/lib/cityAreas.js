/**
 * City / town name → local ranking area.
 *
 * One source of truth shared by:
 *   - /find-a-trainer local search (so "London" finds Greater London,
 *     "Birmingham" finds West Midlands, etc.) and legacy ?area=city:<name> links
 *   - netlify/lib/ukArea.js city fallback (so a trainer with no postcode
 *     district who says "London" is assigned the same area search shows)
 *
 * Every value MUST be a ranking_areas.id. Each entry was checked against the
 * area a sample postcode district in that city is assigned to
 * (resolve_postcode_area), so search and ranking assignment always agree.
 *
 * Plain JS (not TS) so the Netlify functions can import it too.
 */

export const CITY_AREA_ALIASES = {
  // ── England: Greater London ──────────────────────────────────────────────
  'london': 'ENG_GREATER_LONDON',
  'central london': 'ENG_GREATER_LONDON',
  'city of london': 'ENG_GREATER_LONDON',   // the Square Mile is part of Greater London
  'the city': 'ENG_GREATER_LONDON',
  'east london': 'ENG_GREATER_LONDON',
  'west london': 'ENG_GREATER_LONDON',
  'north london': 'ENG_GREATER_LONDON',
  'south london': 'ENG_GREATER_LONDON',
  'westminster': 'ENG_GREATER_LONDON',
  'camden': 'ENG_GREATER_LONDON',
  'islington': 'ENG_GREATER_LONDON',
  'hackney': 'ENG_GREATER_LONDON',
  'shoreditch': 'ENG_GREATER_LONDON',
  'canary wharf': 'ENG_GREATER_LONDON',
  'stratford': 'ENG_GREATER_LONDON',
  'greenwich': 'ENG_GREATER_LONDON',
  'lewisham': 'ENG_GREATER_LONDON',
  'southwark': 'ENG_GREATER_LONDON',
  'lambeth': 'ENG_GREATER_LONDON',
  'brixton': 'ENG_GREATER_LONDON',
  'clapham': 'ENG_GREATER_LONDON',
  'wandsworth': 'ENG_GREATER_LONDON',
  'chelsea': 'ENG_GREATER_LONDON',
  'kensington': 'ENG_GREATER_LONDON',
  'fulham': 'ENG_GREATER_LONDON',
  'hammersmith': 'ENG_GREATER_LONDON',
  'ealing': 'ENG_GREATER_LONDON',
  'croydon': 'ENG_GREATER_LONDON',
  'wimbledon': 'ENG_GREATER_LONDON',
  'bromley': 'ENG_GREATER_LONDON',
  'romford': 'ENG_GREATER_LONDON',

  // ── England: metropolitan counties ───────────────────────────────────────
  'manchester': 'ENG_GREATER_MANCHESTER',
  'salford': 'ENG_GREATER_MANCHESTER',
  'stockport': 'ENG_GREATER_MANCHESTER',
  'bolton': 'ENG_GREATER_MANCHESTER',
  'wigan': 'ENG_GREATER_MANCHESTER',
  'oldham': 'ENG_GREATER_MANCHESTER',
  'rochdale': 'ENG_GREATER_MANCHESTER',
  'birmingham': 'ENG_WEST_MIDLANDS',
  'coventry': 'ENG_WEST_MIDLANDS',
  'wolverhampton': 'ENG_WEST_MIDLANDS',
  'walsall': 'ENG_WEST_MIDLANDS',
  'solihull': 'ENG_WEST_MIDLANDS',
  'dudley': 'ENG_WEST_MIDLANDS',
  'west bromwich': 'ENG_WEST_MIDLANDS',
  'liverpool': 'ENG_MERSEYSIDE',
  'birkenhead': 'ENG_MERSEYSIDE',
  'st helens': 'ENG_MERSEYSIDE',
  'southport': 'ENG_MERSEYSIDE',
  'leeds': 'ENG_WEST_YORKSHIRE',
  'bradford': 'ENG_WEST_YORKSHIRE',
  'wakefield': 'ENG_WEST_YORKSHIRE',
  'huddersfield': 'ENG_WEST_YORKSHIRE',
  'halifax': 'ENG_WEST_YORKSHIRE',
  'sheffield': 'ENG_SOUTH_YORKSHIRE',
  'doncaster': 'ENG_SOUTH_YORKSHIRE',
  'rotherham': 'ENG_SOUTH_YORKSHIRE',
  'barnsley': 'ENG_SOUTH_YORKSHIRE',
  'newcastle': 'ENG_TYNE_AND_WEAR',
  'newcastle upon tyne': 'ENG_TYNE_AND_WEAR',
  'sunderland': 'ENG_TYNE_AND_WEAR',
  'gateshead': 'ENG_TYNE_AND_WEAR',
  'south shields': 'ENG_TYNE_AND_WEAR',

  // ── England: cities inside a county / unitary area ───────────────────────
  'nottingham': 'ENG_NOTTINGHAMSHIRE',
  'leicester': 'ENG_LEICESTERSHIRE',
  'derby': 'ENG_DERBYSHIRE',
  'stoke': 'ENG_STAFFORDSHIRE',
  'stoke-on-trent': 'ENG_STAFFORDSHIRE',
  'bristol': 'ENG_BRISTOL',
  'bath': 'ENG_SOMERSET',
  'hull': 'ENG_EAST_RIDING',
  'kingston upon hull': 'ENG_EAST_RIDING',
  'york': 'ENG_NORTH_YORKSHIRE',
  'middlesbrough': 'ENG_NORTH_YORKSHIRE',
  'brighton': 'ENG_EAST_SUSSEX',
  'hove': 'ENG_EAST_SUSSEX',
  'southampton': 'ENG_HAMPSHIRE',
  'portsmouth': 'ENG_HAMPSHIRE',
  'reading': 'ENG_BERKSHIRE',
  'oxford': 'ENG_OXFORDSHIRE',
  'cambridge': 'ENG_CAMBRIDGESHIRE',
  'peterborough': 'ENG_CAMBRIDGESHIRE',
  // 'milton keynes' intentionally absent: MK postcodes currently resolve to no local
  // area (missing from cc_lad_to_county). Add it here once that row exists.
  'luton': 'ENG_BEDFORDSHIRE',
  'plymouth': 'ENG_DEVON',
  'exeter': 'ENG_DEVON',
  'bournemouth': 'ENG_DORSET',
  'poole': 'ENG_DORSET',
  'norwich': 'ENG_NORFOLK',
  'ipswich': 'ENG_SUFFOLK',
  'chelmsford': 'ENG_ESSEX',
  'colchester': 'ENG_ESSEX',
  'southend': 'ENG_ESSEX',
  'southend-on-sea': 'ENG_ESSEX',
  'swindon': 'ENG_WILTSHIRE',
  'gloucester': 'ENG_GLOUCESTERSHIRE',
  'cheltenham': 'ENG_GLOUCESTERSHIRE',
  'northampton': 'ENG_NORTHAMPTONSHIRE',
  'lincoln': 'ENG_LINCOLNSHIRE',
  'preston': 'ENG_LANCASHIRE',
  'blackpool': 'ENG_LANCASHIRE',
  'blackburn': 'ENG_LANCASHIRE',
  'chester': 'ENG_CHESHIRE',
  'warrington': 'ENG_CHESHIRE',
  'carlisle': 'ENG_CUMBRIA',
  'durham': 'ENG_DURHAM',
  'darlington': 'ENG_DURHAM',

  // ── Scotland ─────────────────────────────────────────────────────────────
  'glasgow': 'SCO_GLASGOW_CITY',
  'edinburgh': 'SCO_CITY_OF_EDINBURGH',
  'aberdeen': 'SCO_ABERDEEN_CITY',
  'dundee': 'SCO_DUNDEE_CITY',
  'inverness': 'SCO_HIGHLAND',
  'perth': 'SCO_PERTH_AND_KINROSS',
  'paisley': 'SCO_RENFREWSHIRE',
  'kirkcaldy': 'SCO_FIFE',
  'dunfermline': 'SCO_FIFE',

  // ── Wales ────────────────────────────────────────────────────────────────
  'cardiff': 'WLS_CARDIFF',
  'swansea': 'WLS_SWANSEA',
  'newport': 'WLS_NEWPORT',
  'wrexham': 'WLS_WREXHAM',
  'barry': 'WLS_VALE_OF_GLAMORGAN',

  // ── Northern Ireland ─────────────────────────────────────────────────────
  'belfast': 'NIR_BELFAST',
  'derry': 'NIR_DERRY_AND_STRABANE',
  'londonderry': 'NIR_DERRY_AND_STRABANE',
  'lisburn': 'NIR_LISBURN_AND_CASTLEREAGH',
  'newry': 'NIR_NEWRY_MOURNE_AND_DOWN',
};

/**
 * "  London, UK " → "london"; "Central London" stays "central london".
 * Lower-cases, collapses spaces, drops punctuation and a trailing
 * country/UK suffix so common variants hit the alias table.
 */
export function normaliseCityName(raw) {
  let s = String(raw ?? '').toLowerCase()
    .replace(/[.,()]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  s = s.replace(/\s+(uk|u k|united kingdom|great britain|gb|england|scotland|wales|northern ireland)$/, '').trim();
  return s;
}

/** Ranking area id for a stated city / search term, or null when unknown. */
export function cityToAreaId(raw) {
  return CITY_AREA_ALIASES[normaliseCityName(raw)] ?? null;
}
