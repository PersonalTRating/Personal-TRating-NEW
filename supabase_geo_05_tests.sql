-- ============================================================
-- COACHCARDS: Geographical Ranking System — Phase 1, File 5 of 5
-- Tests: resolve_postcode_area() validation
--
-- Tests use hardcoded inputs representing what Postcodes.io
-- would return for representative postcodes. They verify the
-- resolution function returns the correct ranking_area_id.
--
-- All tests use DO $$ blocks with ASSERTs and RAISE NOTICE.
-- A PASS message = test passed.
-- A failed ASSERT raises an exception with the test name.
--
-- Run after files 01–04.
-- SAFE TO RE-RUN: read-only (no data modifications).
-- ============================================================


-- ──────────────────────────────────────────────────────────
-- Group A: England — Two-tier Counties (admin_county populated)
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_cc TEXT; v_la TEXT;
BEGIN
  -- A1: Kent — Tunbridge Wells (county council exists)
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Kent', 'Tunbridge Wells', 'England');
  ASSERT v_cc = 'England',  'A1 FAIL: cc_country — got: ' || COALESCE(v_cc,'NULL');
  ASSERT v_la = 'ENG_KENT', 'A1 FAIL: local_area_id — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS A1: Kent two-tier county';

  -- A2: Surrey — Guildford
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Surrey', 'Guildford', 'England');
  ASSERT v_la = 'ENG_SURREY', 'A2 FAIL: Surrey — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS A2: Surrey two-tier county';

  -- A3: Hampshire — Winchester
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Hampshire', 'Winchester', 'England');
  ASSERT v_la = 'ENG_HAMPSHIRE', 'A3 FAIL: Hampshire — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS A3: Hampshire two-tier county';

  -- A4: Oxfordshire — Oxford
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Oxfordshire', 'Oxford', 'England');
  ASSERT v_la = 'ENG_OXFORDSHIRE', 'A4 FAIL: Oxfordshire — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS A4: Oxfordshire two-tier county';

  -- A5: West Sussex — Chichester
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('West Sussex', 'Chichester', 'England');
  ASSERT v_la = 'ENG_WEST_SUSSEX', 'A5 FAIL: West Sussex — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS A5: West Sussex two-tier county';

  -- A6: Norfolk — Norwich
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Norfolk', 'Norwich', 'England');
  ASSERT v_la = 'ENG_NORFOLK', 'A6 FAIL: Norfolk — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS A6: Norfolk two-tier county';

  -- A7: Staffordshire — Lichfield
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Staffordshire', 'Lichfield', 'England');
  ASSERT v_la = 'ENG_STAFFORDSHIRE', 'A7 FAIL: Staffordshire — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS A7: Staffordshire two-tier county';

  RAISE NOTICE '--- Group A complete (7 tests) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group B: England — London Boroughs
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_la TEXT;
BEGIN
  -- B1: Westminster
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Westminster', 'England');
  ASSERT v_la = 'ENG_GREATER_LONDON', 'B1 FAIL: Westminster — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS B1: Westminster → Greater London';

  -- B2: Hackney
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Hackney', 'England');
  ASSERT v_la = 'ENG_GREATER_LONDON', 'B2 FAIL: Hackney — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS B2: Hackney → Greater London';

  -- B3: City of London (distinct from Westminster)
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'City of London', 'England');
  ASSERT v_la = 'ENG_GREATER_LONDON', 'B3 FAIL: City of London — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS B3: City of London → Greater London';

  -- B4: Tower Hamlets
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Tower Hamlets', 'England');
  ASSERT v_la = 'ENG_GREATER_LONDON', 'B4 FAIL: Tower Hamlets — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS B4: Tower Hamlets → Greater London';

  RAISE NOTICE '--- Group B complete (4 tests) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group C: England — Metropolitan Boroughs
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_la TEXT;
BEGIN
  -- C1: Greater Manchester
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Manchester', 'England');
  ASSERT v_la = 'ENG_GREATER_MANCHESTER', 'C1 FAIL: Manchester — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS C1: Manchester → Greater Manchester';

  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Salford', 'England');
  ASSERT v_la = 'ENG_GREATER_MANCHESTER', 'C1b FAIL: Salford — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS C1b: Salford → Greater Manchester';

  -- C2: South Yorkshire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Sheffield', 'England');
  ASSERT v_la = 'ENG_SOUTH_YORKSHIRE', 'C2 FAIL: Sheffield — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS C2: Sheffield → South Yorkshire';

  -- C3: West Yorkshire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Leeds', 'England');
  ASSERT v_la = 'ENG_WEST_YORKSHIRE', 'C3 FAIL: Leeds — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS C3: Leeds → West Yorkshire';

  -- C4: West Midlands county
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Birmingham', 'England');
  ASSERT v_la = 'ENG_WEST_MIDLANDS', 'C4 FAIL: Birmingham — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS C4: Birmingham → West Midlands';

  -- C5: Merseyside
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Liverpool', 'England');
  ASSERT v_la = 'ENG_MERSEYSIDE', 'C5 FAIL: Liverpool — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS C5: Liverpool → Merseyside';

  -- C6: Tyne and Wear
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Newcastle upon Tyne', 'England');
  ASSERT v_la = 'ENG_TYNE_AND_WEAR', 'C6 FAIL: Newcastle — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS C6: Newcastle upon Tyne → Tyne and Wear';

  RAISE NOTICE '--- Group C complete (7 tests) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group D: England — Unitary Authorities (clear cases)
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_la TEXT;
BEGIN
  -- D1: Bristol (own ceremonial county)
  -- NOTE: This test uses 'Bristol, City of' — the expected Postcodes.io string.
  -- If Postcodes.io returns 'Bristol' instead, update the crosswalk and this test.
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Bristol, City of', 'England');
  ASSERT v_la = 'ENG_BRISTOL', 'D1 FAIL: Bristol, City of — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D1: Bristol, City of → Bristol';

  -- D2: Derby → Derbyshire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Derby', 'England');
  ASSERT v_la = 'ENG_DERBYSHIRE', 'D2 FAIL: Derby — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D2: Derby → Derbyshire';

  -- D3: Leicester → Leicestershire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Leicester', 'England');
  ASSERT v_la = 'ENG_LEICESTERSHIRE', 'D3 FAIL: Leicester — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D3: Leicester → Leicestershire';

  -- D4: Rutland → Rutland (its own ceremonial county)
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Rutland', 'England');
  ASSERT v_la = 'ENG_RUTLAND', 'D4 FAIL: Rutland — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D4: Rutland → Rutland';

  -- D5: Peterborough → Cambridgeshire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Peterborough', 'England');
  ASSERT v_la = 'ENG_CAMBRIDGESHIRE', 'D5 FAIL: Peterborough — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D5: Peterborough → Cambridgeshire';

  -- D6: Brighton and Hove → East Sussex
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Brighton and Hove', 'England');
  ASSERT v_la = 'ENG_EAST_SUSSEX', 'D6 FAIL: Brighton and Hove — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D6: Brighton and Hove → East Sussex';

  -- D7: Nottingham → Nottinghamshire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Nottingham', 'England');
  ASSERT v_la = 'ENG_NOTTINGHAMSHIRE', 'D7 FAIL: Nottingham — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D7: Nottingham → Nottinghamshire';

  -- D8: Swindon → Wiltshire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Swindon', 'England');
  ASSERT v_la = 'ENG_WILTSHIRE', 'D8 FAIL: Swindon — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D8: Swindon → Wiltshire';

  -- D9: Bath and North East Somerset → Somerset
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Bath and North East Somerset', 'England');
  ASSERT v_la = 'ENG_SOMERSET', 'D9 FAIL: Bath and NE Somerset — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D9: Bath and North East Somerset → Somerset';

  -- D10: Cheshire East → Cheshire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Cheshire East', 'England');
  ASSERT v_la = 'ENG_CHESHIRE', 'D10 FAIL: Cheshire East — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D10: Cheshire East → Cheshire';

  -- D11: Stoke-on-Trent → Staffordshire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Stoke-on-Trent', 'England');
  ASSERT v_la = 'ENG_STAFFORDSHIRE', 'D11 FAIL: Stoke-on-Trent — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D11: Stoke-on-Trent → Staffordshire';

  -- D12: Medway → Kent
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Medway', 'England');
  ASSERT v_la = 'ENG_KENT', 'D12 FAIL: Medway — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D12: Medway → Kent';

  -- D13: Blackpool → Lancashire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Blackpool', 'England');
  ASSERT v_la = 'ENG_LANCASHIRE', 'D13 FAIL: Blackpool — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D13: Blackpool → Lancashire';

  -- D14: Northumberland → Northumberland
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Northumberland', 'England');
  ASSERT v_la = 'ENG_NORTHUMBERLAND', 'D14 FAIL: Northumberland — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D14: Northumberland → Northumberland';

  -- D15: York → North Yorkshire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'York', 'England');
  ASSERT v_la = 'ENG_NORTH_YORKSHIRE', 'D15 FAIL: York — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS D15: York → North Yorkshire';

  RAISE NOTICE '--- Group D complete (15 tests) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group E: England — Exceptional / Former Cleveland area
-- These pass if the current assignments in the crosswalk hold.
-- The notes column in cc_lad_to_county documents the reasoning.
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_la TEXT;
BEGIN
  -- E1: Middlesbrough → North Yorkshire (Lord Lieutenancy assignment)
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Middlesbrough', 'England');
  ASSERT v_la = 'ENG_NORTH_YORKSHIRE',
    'E1 FAIL: Middlesbrough — got: ' || COALESCE(v_la,'NULL') ||
    ' (Note: former Cleveland area; assignment may need review)';
  RAISE NOTICE 'PASS E1: Middlesbrough → North Yorkshire (Lord Lieutenancy basis)';

  -- E2: Hartlepool → Durham (north of Tees)
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Hartlepool', 'England');
  ASSERT v_la = 'ENG_DURHAM',
    'E2 FAIL: Hartlepool — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS E2: Hartlepool → Durham (Lord Lieutenancy basis)';

  -- E3: Stockton-on-Tees → Durham
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Stockton-on-Tees', 'England');
  ASSERT v_la = 'ENG_DURHAM',
    'E3 FAIL: Stockton-on-Tees — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS E3: Stockton-on-Tees → Durham (Lord Lieutenancy basis)';

  -- E4: Redcar and Cleveland → North Yorkshire
  SELECT local_area_id INTO v_la
  FROM resolve_postcode_area(NULL, 'Redcar and Cleveland', 'England');
  ASSERT v_la = 'ENG_NORTH_YORKSHIRE',
    'E4 FAIL: Redcar and Cleveland — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS E4: Redcar and Cleveland → North Yorkshire (Lord Lieutenancy basis)';

  RAISE NOTICE '--- Group E complete (4 tests, former Cleveland area) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group F: Scotland
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_cc TEXT; v_la TEXT;
BEGIN
  -- F1: Edinburgh
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('City of Edinburgh', 'City of Edinburgh', 'Scotland');
  ASSERT v_cc = 'Scotland',              'F1 FAIL: cc_country — got: ' || COALESCE(v_cc,'NULL');
  ASSERT v_la = 'SCO_CITY_OF_EDINBURGH', 'F1 FAIL: Edinburgh — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS F1: City of Edinburgh';

  -- F2: Fife
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Fife', 'Fife', 'Scotland');
  ASSERT v_la = 'SCO_FIFE', 'F2 FAIL: Fife — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS F2: Fife';

  -- F3: Glasgow
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Glasgow City', 'Glasgow City', 'Scotland');
  ASSERT v_la = 'SCO_GLASGOW_CITY', 'F3 FAIL: Glasgow — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS F3: Glasgow City';

  -- F4: Aberdeen City
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Aberdeen City', 'Aberdeen City', 'Scotland');
  ASSERT v_la = 'SCO_ABERDEEN_CITY', 'F4 FAIL: Aberdeen City — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS F4: Aberdeen City';

  -- F5: Remote area — Na h-Eileanan Siar (Western Isles)
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Na h-Eileanan Siar', 'Na h-Eileanan Siar', 'Scotland');
  ASSERT v_la = 'SCO_NA_H_EILEANAN_SIAR',
    'F5 FAIL: Na h-Eileanan Siar — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS F5: Na h-Eileanan Siar (Western Isles)';

  -- F6: Highland
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Highland', 'Highland', 'Scotland');
  ASSERT v_la = 'SCO_HIGHLAND', 'F6 FAIL: Highland — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS F6: Highland';

  RAISE NOTICE '--- Group F complete (6 tests) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group G: Wales
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_cc TEXT; v_la TEXT;
BEGIN
  -- G1: Cardiff
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Cardiff', 'Cardiff', 'Wales');
  ASSERT v_cc = 'Wales',       'G1 FAIL: cc_country — got: ' || COALESCE(v_cc,'NULL');
  ASSERT v_la = 'WLS_CARDIFF', 'G1 FAIL: Cardiff — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS G1: Cardiff';

  -- G2: Swansea
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Swansea', 'Swansea', 'Wales');
  ASSERT v_la = 'WLS_SWANSEA', 'G2 FAIL: Swansea — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS G2: Swansea';

  -- G3: Isle of Anglesey (English name used by Postcodes.io, not Ynys Môn)
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Isle of Anglesey', 'Isle of Anglesey', 'Wales');
  ASSERT v_la = 'WLS_ISLE_OF_ANGLESEY',
    'G3 FAIL: Isle of Anglesey — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS G3: Isle of Anglesey';

  -- G4: Rhondda Cynon Taf (single f — verify Postcodes.io spelling)
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Rhondda Cynon Taf', 'Rhondda Cynon Taf', 'Wales');
  ASSERT v_la = 'WLS_RHONDDA_CYNON_TAF',
    'G4 FAIL: Rhondda Cynon Taf — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS G4: Rhondda Cynon Taf';

  -- G5: Powys (largest by area)
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area('Powys', 'Powys', 'Wales');
  ASSERT v_la = 'WLS_POWYS', 'G5 FAIL: Powys — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS G5: Powys';

  RAISE NOTICE '--- Group G complete (5 tests) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group H: Northern Ireland
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_cc TEXT; v_la TEXT;
BEGIN
  -- H1: Belfast
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area(NULL, 'Belfast', 'Northern Ireland');
  ASSERT v_cc = 'Northern Ireland', 'H1 FAIL: cc_country — got: ' || COALESCE(v_cc,'NULL');
  ASSERT v_la = 'NIR_BELFAST',      'H1 FAIL: Belfast — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS H1: Belfast';

  -- H2: Derry City and Strabane
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area(NULL, 'Derry City and Strabane', 'Northern Ireland');
  ASSERT v_la = 'NIR_DERRY_AND_STRABANE',
    'H2 FAIL: Derry City and Strabane — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS H2: Derry City and Strabane';

  -- H3: Antrim and Newtownabbey
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area(NULL, 'Antrim and Newtownabbey', 'Northern Ireland');
  ASSERT v_la = 'NIR_ANTRIM_AND_NEWTOWNABBEY',
    'H3 FAIL: Antrim and Newtownabbey — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS H3: Antrim and Newtownabbey';

  -- H4: Armagh (long compound name)
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area(NULL, 'Armagh City, Banbridge and Craigavon', 'Northern Ireland');
  ASSERT v_la = 'NIR_ARMAGH_BANBRIDGE_CRAIGAVON',
    'H4 FAIL: Armagh — got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS H4: Armagh City, Banbridge and Craigavon';

  RAISE NOTICE '--- Group H complete (4 tests) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Group I: Edge cases
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_cc TEXT; v_la TEXT;
BEGIN
  -- I1: Unknown country → cc_country NULL, local_area_id NULL
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area(NULL, 'Somewhere', 'Channel Islands');
  ASSERT v_cc IS NULL, 'I1 FAIL: unknown country should return NULL cc_country, got: ' || COALESCE(v_cc,'NULL');
  ASSERT v_la IS NULL, 'I1 FAIL: unknown country should return NULL local_area_id, got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS I1: Unknown country returns NULL';

  -- I2: Unknown English admin_district → local_area_id NULL
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area(NULL, 'Atlantis', 'England');
  ASSERT v_cc = 'England', 'I2 FAIL: cc_country should be England, got: ' || COALESCE(v_cc,'NULL');
  ASSERT v_la IS NULL, 'I2 FAIL: unknown district should return NULL local_area_id, got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS I2: Unknown English admin_district returns NULL local_area_id';

  -- I3: NULL admin_district and NULL admin_county for England → NULL local_area_id
  SELECT cc_country, local_area_id INTO v_cc, v_la
  FROM resolve_postcode_area(NULL, NULL, 'England');
  ASSERT v_la IS NULL, 'I3 FAIL: all-NULL should return NULL local_area_id, got: ' || COALESCE(v_la,'NULL');
  RAISE NOTICE 'PASS I3: NULL inputs for England returns NULL local_area_id';

  RAISE NOTICE '--- Group I complete (3 edge cases) ---';
END $$;


-- ──────────────────────────────────────────────────────────
-- Summary query: verify ranking_areas row counts
-- ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_national INT; v_country INT;
  v_eng INT; v_sco INT; v_wls INT; v_nir INT;
  v_total INT;
BEGIN
  SELECT COUNT(*) INTO v_national FROM ranking_areas WHERE area_type = 'national';
  SELECT COUNT(*) INTO v_country  FROM ranking_areas WHERE area_type = 'country';
  SELECT COUNT(*) INTO v_eng FROM ranking_areas WHERE country = 'England'          AND area_type = 'local';
  SELECT COUNT(*) INTO v_sco FROM ranking_areas WHERE country = 'Scotland'         AND area_type = 'local';
  SELECT COUNT(*) INTO v_wls FROM ranking_areas WHERE country = 'Wales'            AND area_type = 'local';
  SELECT COUNT(*) INTO v_nir FROM ranking_areas WHERE country = 'Northern Ireland' AND area_type = 'local';
  SELECT COUNT(*) INTO v_total FROM ranking_areas;

  ASSERT v_national = 1,  'COUNT FAIL: national rows should be 1, got ' || v_national;
  ASSERT v_country  = 4,  'COUNT FAIL: country rows should be 4, got '  || v_country;
  ASSERT v_eng = 48,      'COUNT FAIL: England local should be 48, got ' || v_eng;
  ASSERT v_sco = 32,      'COUNT FAIL: Scotland local should be 32, got ' || v_sco;
  ASSERT v_wls = 22,      'COUNT FAIL: Wales local should be 22, got '   || v_wls;
  ASSERT v_nir = 11,      'COUNT FAIL: NI local should be 11, got '      || v_nir;
  ASSERT v_total = 118,   'COUNT FAIL: total should be 118, got '        || v_total;

  RAISE NOTICE 'PASS — ranking_areas counts: 1 national + 4 countries + 48 ENG + 32 SCO + 22 WLS + 11 NIR = 118 rows';
END $$;

-- Crosswalk count check
DO $$
DECLARE v_total INT;
BEGIN
  SELECT COUNT(*) INTO v_total FROM cc_lad_to_county;
  -- Expected: ~36 metro + 33 London + ~62 English UAs + 11 NI = ~142
  ASSERT v_total >= 140, 'COUNT FAIL: crosswalk rows should be >= 140, got ' || v_total;
  RAISE NOTICE 'PASS — cc_lad_to_county has % rows (expected >= 140)', v_total;
END $$;
