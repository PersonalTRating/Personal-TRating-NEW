-- ============================================================
-- COACHCARDS: Geographical Ranking System — Phase 1, File 5 of 5
-- Tests: resolve_postcode_area() validation
--
-- Uses RECORD variables throughout to avoid PostgreSQL's
-- multi-column SELECT INTO ambiguity (42P01 parsing issue).
--
-- Tests use hardcoded inputs representing what Postcodes.io
-- returns for representative postcodes across all UK countries.
--
-- Run after files 01–04.
-- SAFE TO RE-RUN: read-only (no data modifications).
-- A PASS notice = test passed. A failed ASSERT raises an exception.
-- ============================================================


-- ──────────────────────────────────────────────────────────
-- Group A: England — Two-tier Counties (admin_county populated)
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  -- A1: Kent — Tunbridge Wells (county council exists)
  SELECT * INTO r FROM resolve_postcode_area('Kent', 'Tunbridge Wells', 'England');
  ASSERT r.cc_country = 'England',  'A1 FAIL: cc_country — got: ' || COALESCE(r.cc_country,'NULL');
  ASSERT r.local_area_id = 'ENG_KENT', 'A1 FAIL: local_area_id — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS A1: Kent two-tier county';

  -- A2: Surrey — Guildford
  SELECT * INTO r FROM resolve_postcode_area('Surrey', 'Guildford', 'England');
  ASSERT r.local_area_id = 'ENG_SURREY', 'A2 FAIL: Surrey — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS A2: Surrey two-tier county';

  -- A3: Hampshire — Winchester
  SELECT * INTO r FROM resolve_postcode_area('Hampshire', 'Winchester', 'England');
  ASSERT r.local_area_id = 'ENG_HAMPSHIRE', 'A3 FAIL: Hampshire — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS A3: Hampshire two-tier county';

  -- A4: Oxfordshire — Oxford
  SELECT * INTO r FROM resolve_postcode_area('Oxfordshire', 'Oxford', 'England');
  ASSERT r.local_area_id = 'ENG_OXFORDSHIRE', 'A4 FAIL: Oxfordshire — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS A4: Oxfordshire two-tier county';

  -- A5: West Sussex — Chichester
  SELECT * INTO r FROM resolve_postcode_area('West Sussex', 'Chichester', 'England');
  ASSERT r.local_area_id = 'ENG_WEST_SUSSEX', 'A5 FAIL: West Sussex — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS A5: West Sussex two-tier county';

  -- A6: Norfolk — Norwich
  SELECT * INTO r FROM resolve_postcode_area('Norfolk', 'Norwich', 'England');
  ASSERT r.local_area_id = 'ENG_NORFOLK', 'A6 FAIL: Norfolk — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS A6: Norfolk two-tier county';

  -- A7: Staffordshire — Lichfield
  SELECT * INTO r FROM resolve_postcode_area('Staffordshire', 'Lichfield', 'England');
  ASSERT r.local_area_id = 'ENG_STAFFORDSHIRE', 'A7 FAIL: Staffordshire — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS A7: Staffordshire two-tier county';

  RAISE NOTICE '--- Group A complete (7/7) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group B: England — London Boroughs
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Westminster', 'England');
  ASSERT r.local_area_id = 'ENG_GREATER_LONDON', 'B1 FAIL: Westminster — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS B1: Westminster → Greater London';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Hackney', 'England');
  ASSERT r.local_area_id = 'ENG_GREATER_LONDON', 'B2 FAIL: Hackney — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS B2: Hackney → Greater London';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'City of London', 'England');
  ASSERT r.local_area_id = 'ENG_GREATER_LONDON', 'B3 FAIL: City of London — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS B3: City of London → Greater London';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Tower Hamlets', 'England');
  ASSERT r.local_area_id = 'ENG_GREATER_LONDON', 'B4 FAIL: Tower Hamlets — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS B4: Tower Hamlets → Greater London';

  RAISE NOTICE '--- Group B complete (4/4) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group C: England — Metropolitan Boroughs
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Manchester', 'England');
  ASSERT r.local_area_id = 'ENG_GREATER_MANCHESTER', 'C1 FAIL: Manchester — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS C1: Manchester → Greater Manchester';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Salford', 'England');
  ASSERT r.local_area_id = 'ENG_GREATER_MANCHESTER', 'C2 FAIL: Salford — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS C2: Salford → Greater Manchester';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Sheffield', 'England');
  ASSERT r.local_area_id = 'ENG_SOUTH_YORKSHIRE', 'C3 FAIL: Sheffield — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS C3: Sheffield → South Yorkshire';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Leeds', 'England');
  ASSERT r.local_area_id = 'ENG_WEST_YORKSHIRE', 'C4 FAIL: Leeds — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS C4: Leeds → West Yorkshire';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Birmingham', 'England');
  ASSERT r.local_area_id = 'ENG_WEST_MIDLANDS', 'C5 FAIL: Birmingham — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS C5: Birmingham → West Midlands';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Liverpool', 'England');
  ASSERT r.local_area_id = 'ENG_MERSEYSIDE', 'C6 FAIL: Liverpool — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS C6: Liverpool → Merseyside';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Newcastle upon Tyne', 'England');
  ASSERT r.local_area_id = 'ENG_TYNE_AND_WEAR', 'C7 FAIL: Newcastle — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS C7: Newcastle upon Tyne → Tyne and Wear';

  RAISE NOTICE '--- Group C complete (7/7) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group D: England — Unitary Authorities (clear cases)
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  -- D1: Bristol — NOTE: if this fails, Postcodes.io returns 'Bristol' not 'Bristol, City of'
  -- Update the crosswalk admin_district key and re-run if so.
  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Bristol, City of', 'England');
  ASSERT r.local_area_id = 'ENG_BRISTOL', 'D1 FAIL: Bristol, City of — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D1: Bristol, City of → Bristol';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Derby', 'England');
  ASSERT r.local_area_id = 'ENG_DERBYSHIRE', 'D2 FAIL: Derby — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D2: Derby → Derbyshire';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Leicester', 'England');
  ASSERT r.local_area_id = 'ENG_LEICESTERSHIRE', 'D3 FAIL: Leicester — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D3: Leicester → Leicestershire';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Rutland', 'England');
  ASSERT r.local_area_id = 'ENG_RUTLAND', 'D4 FAIL: Rutland — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D4: Rutland → Rutland (own ceremonial county)';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Peterborough', 'England');
  ASSERT r.local_area_id = 'ENG_CAMBRIDGESHIRE', 'D5 FAIL: Peterborough — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D5: Peterborough → Cambridgeshire';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Brighton and Hove', 'England');
  ASSERT r.local_area_id = 'ENG_EAST_SUSSEX', 'D6 FAIL: Brighton and Hove — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D6: Brighton and Hove → East Sussex';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Nottingham', 'England');
  ASSERT r.local_area_id = 'ENG_NOTTINGHAMSHIRE', 'D7 FAIL: Nottingham — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D7: Nottingham → Nottinghamshire';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Swindon', 'England');
  ASSERT r.local_area_id = 'ENG_WILTSHIRE', 'D8 FAIL: Swindon — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D8: Swindon → Wiltshire';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Bath and North East Somerset', 'England');
  ASSERT r.local_area_id = 'ENG_SOMERSET', 'D9 FAIL: Bath and NE Somerset — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D9: Bath and North East Somerset → Somerset';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Cheshire East', 'England');
  ASSERT r.local_area_id = 'ENG_CHESHIRE', 'D10 FAIL: Cheshire East — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D10: Cheshire East → Cheshire';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Stoke-on-Trent', 'England');
  ASSERT r.local_area_id = 'ENG_STAFFORDSHIRE', 'D11 FAIL: Stoke-on-Trent — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D11: Stoke-on-Trent → Staffordshire';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Medway', 'England');
  ASSERT r.local_area_id = 'ENG_KENT', 'D12 FAIL: Medway — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D12: Medway → Kent';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Blackpool', 'England');
  ASSERT r.local_area_id = 'ENG_LANCASHIRE', 'D13 FAIL: Blackpool — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D13: Blackpool → Lancashire';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Northumberland', 'England');
  ASSERT r.local_area_id = 'ENG_NORTHUMBERLAND', 'D14 FAIL: Northumberland — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D14: Northumberland → Northumberland';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'York', 'England');
  ASSERT r.local_area_id = 'ENG_NORTH_YORKSHIRE', 'D15 FAIL: York — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS D15: York → North Yorkshire';

  RAISE NOTICE '--- Group D complete (15/15) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group E: England — Former Cleveland area (exceptional cases)
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Middlesbrough', 'England');
  ASSERT r.local_area_id = 'ENG_NORTH_YORKSHIRE',
    'E1 FAIL: Middlesbrough — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS E1: Middlesbrough → North Yorkshire (Lord Lieutenancy basis)';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Hartlepool', 'England');
  ASSERT r.local_area_id = 'ENG_DURHAM',
    'E2 FAIL: Hartlepool — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS E2: Hartlepool → Durham';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Stockton-on-Tees', 'England');
  ASSERT r.local_area_id = 'ENG_DURHAM',
    'E3 FAIL: Stockton-on-Tees — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS E3: Stockton-on-Tees → Durham';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Redcar and Cleveland', 'England');
  ASSERT r.local_area_id = 'ENG_NORTH_YORKSHIRE',
    'E4 FAIL: Redcar and Cleveland — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS E4: Redcar and Cleveland → North Yorkshire';

  RAISE NOTICE '--- Group E complete (4/4, former Cleveland area) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group F: Scotland
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  SELECT * INTO r FROM resolve_postcode_area('City of Edinburgh', 'City of Edinburgh', 'Scotland');
  ASSERT r.cc_country = 'Scotland',              'F1 FAIL: cc_country — got: ' || COALESCE(r.cc_country,'NULL');
  ASSERT r.local_area_id = 'SCO_CITY_OF_EDINBURGH', 'F1 FAIL: Edinburgh — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS F1: City of Edinburgh';

  SELECT * INTO r FROM resolve_postcode_area('Fife', 'Fife', 'Scotland');
  ASSERT r.local_area_id = 'SCO_FIFE', 'F2 FAIL: Fife — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS F2: Fife';

  SELECT * INTO r FROM resolve_postcode_area('Glasgow City', 'Glasgow City', 'Scotland');
  ASSERT r.local_area_id = 'SCO_GLASGOW_CITY', 'F3 FAIL: Glasgow — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS F3: Glasgow City';

  SELECT * INTO r FROM resolve_postcode_area('Aberdeen City', 'Aberdeen City', 'Scotland');
  ASSERT r.local_area_id = 'SCO_ABERDEEN_CITY', 'F4 FAIL: Aberdeen — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS F4: Aberdeen City';

  SELECT * INTO r FROM resolve_postcode_area('Na h-Eileanan Siar', 'Na h-Eileanan Siar', 'Scotland');
  ASSERT r.local_area_id = 'SCO_NA_H_EILEANAN_SIAR',
    'F5 FAIL: Na h-Eileanan Siar — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS F5: Na h-Eileanan Siar (Western Isles)';

  SELECT * INTO r FROM resolve_postcode_area('Highland', 'Highland', 'Scotland');
  ASSERT r.local_area_id = 'SCO_HIGHLAND', 'F6 FAIL: Highland — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS F6: Highland';

  RAISE NOTICE '--- Group F complete (6/6) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group G: Wales
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  SELECT * INTO r FROM resolve_postcode_area('Cardiff', 'Cardiff', 'Wales');
  ASSERT r.cc_country = 'Wales',       'G1 FAIL: cc_country — got: ' || COALESCE(r.cc_country,'NULL');
  ASSERT r.local_area_id = 'WLS_CARDIFF', 'G1 FAIL: Cardiff — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS G1: Cardiff';

  SELECT * INTO r FROM resolve_postcode_area('Swansea', 'Swansea', 'Wales');
  ASSERT r.local_area_id = 'WLS_SWANSEA', 'G2 FAIL: Swansea — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS G2: Swansea';

  SELECT * INTO r FROM resolve_postcode_area('Isle of Anglesey', 'Isle of Anglesey', 'Wales');
  ASSERT r.local_area_id = 'WLS_ISLE_OF_ANGLESEY',
    'G3 FAIL: Isle of Anglesey — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS G3: Isle of Anglesey';

  SELECT * INTO r FROM resolve_postcode_area('Rhondda Cynon Taf', 'Rhondda Cynon Taf', 'Wales');
  ASSERT r.local_area_id = 'WLS_RHONDDA_CYNON_TAF',
    'G4 FAIL: Rhondda Cynon Taf — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS G4: Rhondda Cynon Taf';

  SELECT * INTO r FROM resolve_postcode_area('Powys', 'Powys', 'Wales');
  ASSERT r.local_area_id = 'WLS_POWYS', 'G5 FAIL: Powys — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS G5: Powys';

  RAISE NOTICE '--- Group G complete (5/5) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group H: Northern Ireland
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Belfast', 'Northern Ireland');
  ASSERT r.cc_country = 'Northern Ireland', 'H1 FAIL: cc_country — got: ' || COALESCE(r.cc_country,'NULL');
  ASSERT r.local_area_id = 'NIR_BELFAST', 'H1 FAIL: Belfast — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS H1: Belfast';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Derry City and Strabane', 'Northern Ireland');
  ASSERT r.local_area_id = 'NIR_DERRY_AND_STRABANE',
    'H2 FAIL: Derry — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS H2: Derry City and Strabane';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Antrim and Newtownabbey', 'Northern Ireland');
  ASSERT r.local_area_id = 'NIR_ANTRIM_AND_NEWTOWNABBEY',
    'H3 FAIL: Antrim and Newtownabbey — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS H3: Antrim and Newtownabbey';

  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Armagh City, Banbridge and Craigavon', 'Northern Ireland');
  ASSERT r.local_area_id = 'NIR_ARMAGH_BANBRIDGE_CRAIGAVON',
    'H4 FAIL: Armagh — got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS H4: Armagh City, Banbridge and Craigavon';

  RAISE NOTICE '--- Group H complete (4/4) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group I: Edge cases
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
BEGIN
  -- I1: Unknown country → cc_country NULL, local_area_id NULL
  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Somewhere', 'Channel Islands');
  ASSERT r.cc_country IS NULL,    'I1 FAIL: unknown country should return NULL cc_country, got: ' || COALESCE(r.cc_country,'NULL');
  ASSERT r.local_area_id IS NULL, 'I1 FAIL: unknown country should return NULL local_area_id, got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS I1: Unknown country returns NULL';

  -- I2: Known country, unknown admin_district → local_area_id NULL
  SELECT * INTO r FROM resolve_postcode_area(NULL, 'Atlantis', 'England');
  ASSERT r.cc_country = 'England', 'I2 FAIL: cc_country should be England, got: ' || COALESCE(r.cc_country,'NULL');
  ASSERT r.local_area_id IS NULL,  'I2 FAIL: unknown district should return NULL local_area_id, got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS I2: Unknown English admin_district returns NULL local_area_id';

  -- I3: All-NULL inputs for England → NULL local_area_id
  SELECT * INTO r FROM resolve_postcode_area(NULL, NULL, 'England');
  ASSERT r.local_area_id IS NULL, 'I3 FAIL: all-NULL should return NULL local_area_id, got: ' || COALESCE(r.local_area_id,'NULL');
  RAISE NOTICE 'PASS I3: NULL inputs for England returns NULL local_area_id';

  RAISE NOTICE '--- Group I complete (3/3 edge cases) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Row count checks
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_national INT; v_country INT;
  v_eng INT; v_sco INT; v_wls INT; v_nir INT;
  v_total INT; v_xwalk INT;
BEGIN
  SELECT COUNT(*) INTO v_national FROM ranking_areas WHERE area_type = 'national';
  SELECT COUNT(*) INTO v_country  FROM ranking_areas WHERE area_type = 'country';
  SELECT COUNT(*) INTO v_eng  FROM ranking_areas WHERE country = 'England'          AND area_type = 'local';
  SELECT COUNT(*) INTO v_sco  FROM ranking_areas WHERE country = 'Scotland'         AND area_type = 'local';
  SELECT COUNT(*) INTO v_wls  FROM ranking_areas WHERE country = 'Wales'            AND area_type = 'local';
  SELECT COUNT(*) INTO v_nir  FROM ranking_areas WHERE country = 'Northern Ireland' AND area_type = 'local';
  SELECT COUNT(*) INTO v_total  FROM ranking_areas;
  SELECT COUNT(*) INTO v_xwalk  FROM cc_lad_to_county;

  ASSERT v_national = 1,  'COUNT FAIL: national rows = 1, got ' || v_national;
  ASSERT v_country  = 4,  'COUNT FAIL: country rows = 4, got '  || v_country;
  ASSERT v_eng = 48,      'COUNT FAIL: England local = 48, got ' || v_eng;
  ASSERT v_sco = 32,      'COUNT FAIL: Scotland local = 32, got ' || v_sco;
  ASSERT v_wls = 22,      'COUNT FAIL: Wales local = 22, got '   || v_wls;
  ASSERT v_nir = 11,      'COUNT FAIL: NI local = 11, got '      || v_nir;
  ASSERT v_total = 118,   'COUNT FAIL: total = 118, got '        || v_total;
  ASSERT v_xwalk >= 140,  'COUNT FAIL: crosswalk >= 140 rows, got ' || v_xwalk;

  RAISE NOTICE 'PASS — ranking_areas: 1 national + 4 countries + 48 ENG + 32 SCO + 22 WLS + 11 NIR = % total', v_total;
  RAISE NOTICE 'PASS — cc_lad_to_county: % rows', v_xwalk;
END $$;
