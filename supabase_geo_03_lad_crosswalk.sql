-- ============================================================
-- COACHCARDS: Geographical Ranking System — Phase 1, File 3 of 5
-- Data: cc_lad_to_county crosswalk (~142 entries)
--
-- Purpose: maps Postcodes.io admin_district values to ranking_areas
-- for all cases where Postcodes.io returns admin_county = NULL.
--
-- WHEN admin_county IS NULL in Postcodes.io:
--   • English Metropolitan Boroughs  (36 LADs across 6 metro counties)
--   • London Boroughs                (32 boroughs + City of London = 33)
--   • English Unitary Authorities    (~62 LADs, post-2023 boundaries)
--   • Northern Ireland Districts     (11 districts, all have null admin_county)
--
-- NOT NEEDED for:
--   • Scotland : admin_county = council area name, matches display_name directly
--   • Wales    : admin_county = principal area name, matches display_name directly
--   • English 2-tier counties (active county council): admin_county is populated
--
-- verified=TRUE : admin_district string confirmed against live Postcodes.io.
-- verified=FALSE: string derived from ONS LAD list; confirm before go-live.
--
-- To verify: GET https://api.postcodes.io/postcodes/<postcode>
-- and check that result.admin_district matches this key exactly.
--
-- Run after file 02.
-- SAFE TO RE-RUN: ON CONFLICT DO NOTHING.
-- ============================================================


-- ──────────────────────────────────────────────────────────
-- 1. Greater Manchester (10 Metropolitan Boroughs)
-- ──────────────────────────────────────────────────────────
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Bolton',     'ENG_GREATER_MANCHESTER', 'E08000001', 'metro_borough', FALSE),
  ('Bury',       'ENG_GREATER_MANCHESTER', 'E08000002', 'metro_borough', FALSE),
  ('Manchester', 'ENG_GREATER_MANCHESTER', 'E08000003', 'metro_borough', FALSE),
  ('Oldham',     'ENG_GREATER_MANCHESTER', 'E08000004', 'metro_borough', FALSE),
  ('Rochdale',   'ENG_GREATER_MANCHESTER', 'E08000005', 'metro_borough', FALSE),
  ('Salford',    'ENG_GREATER_MANCHESTER', 'E08000006', 'metro_borough', FALSE),
  ('Stockport',  'ENG_GREATER_MANCHESTER', 'E08000007', 'metro_borough', FALSE),
  ('Tameside',   'ENG_GREATER_MANCHESTER', 'E08000008', 'metro_borough', FALSE),
  ('Trafford',   'ENG_GREATER_MANCHESTER', 'E08000009', 'metro_borough', FALSE),
  ('Wigan',      'ENG_GREATER_MANCHESTER', 'E08000010', 'metro_borough', FALSE)
ON CONFLICT (admin_district) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- 2. Merseyside (5 Metropolitan Boroughs)
-- NOTE: verify 'St. Helens' — may be 'St Helens' without period
-- ──────────────────────────────────────────────────────────
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Knowsley',    'ENG_MERSEYSIDE', 'E08000011', 'metro_borough', FALSE),
  ('Liverpool',   'ENG_MERSEYSIDE', 'E08000012', 'metro_borough', FALSE),
  ('St. Helens',  'ENG_MERSEYSIDE', 'E08000013', 'metro_borough', FALSE),
  ('Sefton',      'ENG_MERSEYSIDE', 'E08000014', 'metro_borough', FALSE),
  ('Wirral',      'ENG_MERSEYSIDE', 'E08000015', 'metro_borough', FALSE)
ON CONFLICT (admin_district) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- 3. South Yorkshire (4 Metropolitan Boroughs)
-- ──────────────────────────────────────────────────────────
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Barnsley',   'ENG_SOUTH_YORKSHIRE', 'E08000016', 'metro_borough', FALSE),
  ('Doncaster',  'ENG_SOUTH_YORKSHIRE', 'E08000017', 'metro_borough', FALSE),
  ('Rotherham',  'ENG_SOUTH_YORKSHIRE', 'E08000018', 'metro_borough', FALSE),
  ('Sheffield',  'ENG_SOUTH_YORKSHIRE', 'E08000019', 'metro_borough', FALSE)
ON CONFLICT (admin_district) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- 4. Tyne and Wear (5 Metropolitan Boroughs)
-- NOTE: verify exact strings, especially 'Newcastle upon Tyne'
-- ──────────────────────────────────────────────────────────
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Gateshead',          'ENG_TYNE_AND_WEAR', NULL, 'metro_borough', FALSE),
  ('Newcastle upon Tyne','ENG_TYNE_AND_WEAR', NULL, 'metro_borough', FALSE),
  ('North Tyneside',     'ENG_TYNE_AND_WEAR', NULL, 'metro_borough', FALSE),
  ('South Tyneside',     'ENG_TYNE_AND_WEAR', NULL, 'metro_borough', FALSE),
  ('Sunderland',         'ENG_TYNE_AND_WEAR', NULL, 'metro_borough', FALSE)
ON CONFLICT (admin_district) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- 5. West Midlands (7 Metropolitan Boroughs)
-- ──────────────────────────────────────────────────────────
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Birmingham',  'ENG_WEST_MIDLANDS', 'E08000025', 'metro_borough', FALSE),
  ('Coventry',    'ENG_WEST_MIDLANDS', 'E08000026', 'metro_borough', FALSE),
  ('Dudley',      'ENG_WEST_MIDLANDS', 'E08000027', 'metro_borough', FALSE),
  ('Sandwell',    'ENG_WEST_MIDLANDS', 'E08000028', 'metro_borough', FALSE),
  ('Solihull',    'ENG_WEST_MIDLANDS', 'E08000029', 'metro_borough', FALSE),
  ('Walsall',     'ENG_WEST_MIDLANDS', 'E08000030', 'metro_borough', FALSE),
  ('Wolverhampton','ENG_WEST_MIDLANDS','E08000031', 'metro_borough', FALSE)
ON CONFLICT (admin_district) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- 6. West Yorkshire (5 Metropolitan Boroughs)
-- ──────────────────────────────────────────────────────────
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Bradford',   'ENG_WEST_YORKSHIRE', NULL, 'metro_borough', FALSE),
  ('Calderdale', 'ENG_WEST_YORKSHIRE', NULL, 'metro_borough', FALSE),
  ('Kirklees',   'ENG_WEST_YORKSHIRE', NULL, 'metro_borough', FALSE),
  ('Leeds',      'ENG_WEST_YORKSHIRE', NULL, 'metro_borough', FALSE),
  ('Wakefield',  'ENG_WEST_YORKSHIRE', NULL, 'metro_borough', FALSE)
ON CONFLICT (admin_district) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- 7. London Boroughs (32 boroughs + City of London = 33)
-- ONS codes E09000001–E09000033
-- ──────────────────────────────────────────────────────────
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('City of London',          'ENG_GREATER_LONDON', 'E09000001', 'london_borough', FALSE),
  ('Barking and Dagenham',    'ENG_GREATER_LONDON', 'E09000002', 'london_borough', FALSE),
  ('Barnet',                  'ENG_GREATER_LONDON', 'E09000003', 'london_borough', FALSE),
  ('Bexley',                  'ENG_GREATER_LONDON', 'E09000004', 'london_borough', FALSE),
  ('Brent',                   'ENG_GREATER_LONDON', 'E09000005', 'london_borough', FALSE),
  ('Bromley',                 'ENG_GREATER_LONDON', 'E09000006', 'london_borough', FALSE),
  ('Camden',                  'ENG_GREATER_LONDON', 'E09000007', 'london_borough', FALSE),
  ('Croydon',                 'ENG_GREATER_LONDON', 'E09000008', 'london_borough', FALSE),
  ('Ealing',                  'ENG_GREATER_LONDON', 'E09000009', 'london_borough', FALSE),
  ('Enfield',                 'ENG_GREATER_LONDON', 'E09000010', 'london_borough', FALSE),
  ('Greenwich',               'ENG_GREATER_LONDON', 'E09000011', 'london_borough', FALSE),
  ('Hackney',                 'ENG_GREATER_LONDON', 'E09000012', 'london_borough', FALSE),
  ('Hammersmith and Fulham',  'ENG_GREATER_LONDON', 'E09000013', 'london_borough', FALSE),
  ('Haringey',                'ENG_GREATER_LONDON', 'E09000014', 'london_borough', FALSE),
  ('Harrow',                  'ENG_GREATER_LONDON', 'E09000015', 'london_borough', FALSE),
  ('Havering',                'ENG_GREATER_LONDON', 'E09000016', 'london_borough', FALSE),
  ('Hillingdon',              'ENG_GREATER_LONDON', 'E09000017', 'london_borough', FALSE),
  ('Hounslow',                'ENG_GREATER_LONDON', 'E09000018', 'london_borough', FALSE),
  ('Islington',               'ENG_GREATER_LONDON', 'E09000019', 'london_borough', FALSE),
  ('Kensington and Chelsea',  'ENG_GREATER_LONDON', 'E09000020', 'london_borough', FALSE),
  ('Kingston upon Thames',    'ENG_GREATER_LONDON', 'E09000021', 'london_borough', FALSE),
  ('Lambeth',                 'ENG_GREATER_LONDON', 'E09000022', 'london_borough', FALSE),
  ('Lewisham',                'ENG_GREATER_LONDON', 'E09000023', 'london_borough', FALSE),
  ('Merton',                  'ENG_GREATER_LONDON', 'E09000024', 'london_borough', FALSE),
  ('Newham',                  'ENG_GREATER_LONDON', 'E09000025', 'london_borough', FALSE),
  ('Redbridge',               'ENG_GREATER_LONDON', 'E09000026', 'london_borough', FALSE),
  ('Richmond upon Thames',    'ENG_GREATER_LONDON', 'E09000027', 'london_borough', FALSE),
  ('Southwark',               'ENG_GREATER_LONDON', 'E09000028', 'london_borough', FALSE),
  ('Sutton',                  'ENG_GREATER_LONDON', 'E09000029', 'london_borough', FALSE),
  ('Tower Hamlets',           'ENG_GREATER_LONDON', 'E09000030', 'london_borough', FALSE),
  ('Waltham Forest',          'ENG_GREATER_LONDON', 'E09000031', 'london_borough', FALSE),
  ('Wandsworth',              'ENG_GREATER_LONDON', 'E09000032', 'london_borough', FALSE),
  ('Westminster',             'ENG_GREATER_LONDON', 'E09000033', 'london_borough', FALSE)
ON CONFLICT (admin_district) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- 8. English Unitary Authorities
--    Grouped by ceremonial county.
--    Former Cleveland area (Hartlepool, Middlesbrough,
--    Redcar and Cleveland, Stockton-on-Tees) assigned on
--    Lord Lieutenancy basis; see notes. Verify if needed.
-- ──────────────────────────────────────────────────────────

-- Bedfordshire (county council abolished 2009; 3 UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Bedford',              'ENG_BEDFORDSHIRE', 'E06000055', 'unitary_authority', FALSE),
  ('Central Bedfordshire', 'ENG_BEDFORDSHIRE', 'E06000056', 'unitary_authority', FALSE),
  ('Luton',                'ENG_BEDFORDSHIRE', 'E06000032', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Berkshire (county council abolished 1998; 6 UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Bracknell Forest',        'ENG_BERKSHIRE', 'E06000036', 'unitary_authority', FALSE),
  ('Reading',                 'ENG_BERKSHIRE', 'E06000038', 'unitary_authority', FALSE),
  ('Slough',                  'ENG_BERKSHIRE', 'E06000039', 'unitary_authority', FALSE),
  ('West Berkshire',          'ENG_BERKSHIRE', 'E06000037', 'unitary_authority', FALSE),
  ('Windsor and Maidenhead',  'ENG_BERKSHIRE', 'E06000040', 'unitary_authority', FALSE),
  ('Wokingham',               'ENG_BERKSHIRE', 'E06000041', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Bristol (its own ceremonial county; 1 UA)
-- NOTE: Postcodes.io may return 'Bristol, City of' — verify
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, notes, verified)
VALUES
  ('Bristol, City of', 'ENG_BRISTOL', 'E06000023', 'unitary_authority',
   'Verify: Postcodes.io may return ''Bristol, City of'' or ''Bristol''', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Buckinghamshire (county council abolished 2020; 1 UA)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Buckinghamshire', 'ENG_BUCKINGHAMSHIRE', 'E06000060', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Cambridgeshire (county council remains; Peterborough is UA)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Peterborough', 'ENG_CAMBRIDGESHIRE', 'E06000031', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Cheshire (county council abolished 2009; 4 UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Cheshire East',              'ENG_CHESHIRE', 'E06000049', 'unitary_authority', FALSE),
  ('Cheshire West and Chester',  'ENG_CHESHIRE', 'E06000050', 'unitary_authority', FALSE),
  ('Halton',                     'ENG_CHESHIRE', 'E06000006', 'unitary_authority', FALSE),
  ('Warrington',                 'ENG_CHESHIRE', 'E06000007', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Cornwall (county council abolished 2009; 1 UA + Isles of Scilly)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Cornwall',        'ENG_CORNWALL',        'E06000052', 'unitary_authority', FALSE),
  ('Isles of Scilly', 'ENG_ISLES_OF_SCILLY', 'E06000053', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Cumbria (county council abolished April 2023; 2 UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Cumberland',              'ENG_CUMBRIA', 'E06000063', 'unitary_authority', FALSE),
  ('Westmorland and Furness', 'ENG_CUMBRIA', 'E06000064', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Durham ceremonial county (county council → UA 2009; also Darlington UA)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('County Durham', 'ENG_DURHAM', 'E06000047', 'unitary_authority', FALSE),
  ('Darlington',    'ENG_DURHAM', 'E06000005', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Former Cleveland area — assigned to Durham or North Yorkshire
-- on Lord Lieutenancy basis (County Durham covers north of Tees;
-- North Yorkshire covers south). VERIFY if precise ceremonial
-- boundary matters for your use case.
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, notes, verified)
VALUES
  ('Hartlepool',         'ENG_DURHAM',          'E06000001', 'unitary_authority',
   'Former Cleveland; assigned to Durham (north of Tees, Lord Lieutenancy boundary)', FALSE),
  ('Stockton-on-Tees',   'ENG_DURHAM',          'E06000004', 'unitary_authority',
   'Former Cleveland; assigned to Durham (most of Stockton is north of Tees)', FALSE),
  ('Middlesbrough',      'ENG_NORTH_YORKSHIRE',  'E06000002', 'unitary_authority',
   'Former Cleveland; assigned to North Yorkshire (south of Tees, Lord Lieutenancy)', FALSE),
  ('Redcar and Cleveland','ENG_NORTH_YORKSHIRE', 'E06000003', 'unitary_authority',
   'Former Cleveland; assigned to North Yorkshire (south of Tees, Lord Lieutenancy)', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Derbyshire (county council remains; Derby is UA)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Derby', 'ENG_DERBYSHIRE', 'E06000015', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Devon (county council remains; Plymouth and Torbay are UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Plymouth', 'ENG_DEVON', 'E06000026', 'unitary_authority', FALSE),
  ('Torbay',   'ENG_DEVON', 'E06000027', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Dorset (county council abolished April 2019; 2 UAs)
-- NOTE: verify exact string for the merged council
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, notes, verified)
VALUES
  ('Bournemouth, Christchurch and Poole', 'ENG_DORSET', 'E06000058', 'unitary_authority',
   'Formed April 2019 from Bournemouth, Christchurch and Poole councils', FALSE),
  ('Dorset', 'ENG_DORSET', 'E06000059', 'unitary_authority', NULL, FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- East Riding of Yorkshire (UA since 1996; also Hull)
-- NOTE: verify Kingston upon Hull string — may include 'City of'
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, notes, verified)
VALUES
  ('East Riding of Yorkshire', 'ENG_EAST_RIDING', 'E06000011', 'unitary_authority', NULL, FALSE),
  ('Kingston upon Hull, City of', 'ENG_EAST_RIDING', 'E06000010', 'unitary_authority',
   'Verify: Postcodes.io may return ''Kingston upon Hull, City of'' or ''Kingston upon Hull''', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- East Sussex (county council remains; Brighton and Hove is UA)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Brighton and Hove', 'ENG_EAST_SUSSEX', 'E06000043', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Essex (county council remains; Southend-on-Sea and Thurrock are UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Southend-on-Sea', 'ENG_ESSEX', 'E06000033', 'unitary_authority', FALSE),
  ('Thurrock',        'ENG_ESSEX', 'E06000034', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Gloucestershire (county council remains; South Gloucestershire is UA)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('South Gloucestershire', 'ENG_GLOUCESTERSHIRE', 'E06000025', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Hampshire (county council remains; Portsmouth and Southampton are UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Portsmouth',  'ENG_HAMPSHIRE', 'E06000044', 'unitary_authority', FALSE),
  ('Southampton', 'ENG_HAMPSHIRE', 'E06000045', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Herefordshire (UA since 1998; whole county is one UA)
-- NOTE: Postcodes.io may return 'Herefordshire, County of' — verify
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, notes, verified)
VALUES
  ('Herefordshire, County of', 'ENG_HEREFORDSHIRE', 'E06000019', 'unitary_authority',
   'Verify: Postcodes.io may return ''Herefordshire, County of'' or ''Herefordshire''', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Isle of Wight (UA since 1995)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Isle of Wight', 'ENG_ISLE_OF_WIGHT', 'E06000046', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Kent (county council remains; Medway is UA)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Medway', 'ENG_KENT', 'E06000035', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Lancashire (county council remains; Blackburn and Blackpool are UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Blackburn with Darwen', 'ENG_LANCASHIRE', 'E06000008', 'unitary_authority', FALSE),
  ('Blackpool',             'ENG_LANCASHIRE', 'E06000009', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Leicestershire (county council remains; Leicester and Rutland are UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Leicester', 'ENG_LEICESTERSHIRE', 'E06000016', 'unitary_authority', FALSE),
  ('Rutland',   'ENG_RUTLAND',        'E06000017', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Lincolnshire (county council remains; NE and N Lincolnshire are UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('North East Lincolnshire', 'ENG_LINCOLNSHIRE', 'E06000012', 'unitary_authority', FALSE),
  ('North Lincolnshire',      'ENG_LINCOLNSHIRE', 'E06000013', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- North Yorkshire (county council became UA April 2023; York is separate UA)
-- When admin_county IS NULL and admin_district = 'North Yorkshire',
-- this covers post-April 2023 postcodes (new UA).
-- Pre-2023 postcodes use admin_county = 'North Yorkshire' directly.
-- NOTE: 'York' (admin_district) is actually 'City of York' in some sources — verify
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, notes, verified)
VALUES
  ('North Yorkshire', 'ENG_NORTH_YORKSHIRE', 'E06000065', 'unitary_authority',
   'Post-April 2023 UA replacing North Yorkshire County Council', FALSE),
  ('York', 'ENG_NORTH_YORKSHIRE', 'E06000014', 'unitary_authority',
   'Verify: Postcodes.io may return ''York'' or ''City of York''', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Northamptonshire (county council abolished April 2021; 2 UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('North Northamptonshire', 'ENG_NORTHAMPTONSHIRE', 'E06000061', 'unitary_authority', FALSE),
  ('West Northamptonshire',  'ENG_NORTHAMPTONSHIRE', 'E06000062', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Northumberland (UA since 2009)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Northumberland', 'ENG_NORTHUMBERLAND', 'E06000057', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Nottinghamshire (county council remains; Nottingham is UA)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Nottingham', 'ENG_NOTTINGHAMSHIRE', 'E06000018', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Shropshire (county council abolished 2009; 2 UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Shropshire',        'ENG_SHROPSHIRE', 'E06000051', 'unitary_authority', FALSE),
  ('Telford and Wrekin','ENG_SHROPSHIRE', 'E06000020', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Somerset (county council abolished April 2023; Bath/NE Somerset and
-- North Somerset were UAs since 1996; Somerset became UA April 2023)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, notes, verified)
VALUES
  ('Bath and North East Somerset', 'ENG_SOMERSET', 'E06000022', 'unitary_authority', NULL, FALSE),
  ('North Somerset',               'ENG_SOMERSET', 'E06000024', 'unitary_authority', NULL, FALSE),
  ('Somerset',                     'ENG_SOMERSET', 'E06000066', 'unitary_authority',
   'Post-April 2023 UA replacing Somerset County Council', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Staffordshire (county council remains; Stoke-on-Trent is UA)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Stoke-on-Trent', 'ENG_STAFFORDSHIRE', 'E06000021', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;

-- Wiltshire (county council abolished 2009; 2 UAs)
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Swindon',    'ENG_WILTSHIRE', 'E06000030', 'unitary_authority', FALSE),
  ('Wiltshire',  'ENG_WILTSHIRE', 'E06000054', 'unitary_authority', FALSE)
ON CONFLICT (admin_district) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- 9. Northern Ireland Districts (11)
--    All NI postcodes return admin_county = NULL.
--    admin_district = the 2015-reform district name.
--    Verify strings against: https://api.postcodes.io/postcodes/BT11AA
-- ──────────────────────────────────────────────────────────
INSERT INTO cc_lad_to_county (admin_district, ranking_area_id, ons_lad_code, area_category, verified)
VALUES
  ('Antrim and Newtownabbey',               'NIR_ANTRIM_AND_NEWTOWNABBEY',    'N09000001', 'ni_district', FALSE),
  ('Ards and North Down',                   'NIR_ARDS_AND_NORTH_DOWN',        'N09000011', 'ni_district', FALSE),
  ('Armagh City, Banbridge and Craigavon',  'NIR_ARMAGH_BANBRIDGE_CRAIGAVON', 'N09000002', 'ni_district', FALSE),
  ('Belfast',                               'NIR_BELFAST',                    'N09000003', 'ni_district', FALSE),
  ('Causeway Coast and Glens',              'NIR_CAUSEWAY_COAST_AND_GLENS',   'N09000004', 'ni_district', FALSE),
  ('Derry City and Strabane',               'NIR_DERRY_AND_STRABANE',         'N09000005', 'ni_district', FALSE),
  ('Fermanagh and Omagh',                   'NIR_FERMANAGH_AND_OMAGH',        'N09000006', 'ni_district', FALSE),
  ('Lisburn and Castlereagh',               'NIR_LISBURN_AND_CASTLEREAGH',    'N09000007', 'ni_district', FALSE),
  ('Mid and East Antrim',                   'NIR_MID_AND_EAST_ANTRIM',        'N09000008', 'ni_district', FALSE),
  ('Mid Ulster',                            'NIR_MID_ULSTER',                 'N09000009', 'ni_district', FALSE),
  ('Newry, Mourne and Down',                'NIR_NEWRY_MOURNE_AND_DOWN',      'N09000010', 'ni_district', FALSE)
ON CONFLICT (admin_district) DO NOTHING;
