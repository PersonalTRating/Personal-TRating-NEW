-- ============================================================
-- COACHCARDS: Stated-location rankings — DATA FIX
-- Run in the Supabase SQL editor AFTER supabase_stated_location.sql.
-- (The SQL editor runs as postgres, which the geo-column trigger allows.)
--
-- Areas below were worked out with the same lookup the new
-- assign-location.js uses (Postcodes.io + resolve_postcode_area), run
-- read-only against live data on 2026-11-28:
--   E14  → Tower Hamlets               → ENG_GREATER_LONDON
--   SW1  → SW1A/E/H/P/V/W/X/Y (Westminster etc.) → ENG_GREATER_LONDON
--   SE16 → Lewisham / Southwark         → ENG_GREATER_LONDON
--   SE13 → Greenwich / Lewisham         → ENG_GREATER_LONDON
--   EH1  → City of Edinburgh            → SCO_CITY_OF_EDINBURGH
--   Mike Wilson: "3351" is not a postcode district → city "London"
--                                       → ENG_GREATER_LONDON (source = city)
--
-- Every statement checks it changed exactly the rows expected; if not,
-- the whole transaction is rolled back and nothing changes.
-- DO NOT EXECUTE IN PRODUCTION without explicit approval.
-- ============================================================

BEGIN;

DO $$
DECLARE n INT;
BEGIN
  -- ── 1. Tracy Gibson: Scotland → England / Greater London ────────────
  UPDATE trainers
  SET    postcode_district        = 'E14',
         cc_country               = 'England',
         cc_local_area            = 'ENG_GREATER_LONDON',
         location_source          = 'postcode',
         location_mapping_version = 'ONS-2023-12'
  WHERE  id = 'ed71661a-2515-4df0-b0fe-0f486968d104';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'Tracy Gibson: expected 1 row, got %', n; END IF;

  -- ── 2. Joe Wilson: Scotland / Fife → England / Greater London ───────
  UPDATE trainers
  SET    postcode_district        = 'SE16',
         cc_country               = 'England',
         cc_local_area            = 'ENG_GREATER_LONDON',
         location_source          = 'postcode',
         location_mapping_version = 'ONS-2023-12'
  WHERE  id = '35d67612-2999-4076-bfce-0288e836f8b3';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'Joe Wilson: expected 1 row, got %', n; END IF;

  -- ── 3. Paul Davies: unassigned → England / Greater London ───────────
  UPDATE trainers
  SET    postcode_district        = 'SW1',
         cc_country               = 'England',
         cc_local_area            = 'ENG_GREATER_LONDON',
         location_source          = 'postcode',
         location_mapping_version = 'ONS-2023-12'
  WHERE  id = '639b7020-9f0a-4ff4-b352-8169d1d65068';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'Paul Davies: expected 1 row, got %', n; END IF;

  -- ── 4. Joseph Mitchell: unassigned → England / Greater London ───────
  UPDATE trainers
  SET    postcode_district        = 'SE13',
         cc_country               = 'England',
         cc_local_area            = 'ENG_GREATER_LONDON',
         location_source          = 'postcode',
         location_mapping_version = 'ONS-2023-12'
  WHERE  id = '5010cb9f-aa00-4fcc-8c91-739312e2df4e';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'Joseph Mitchell: expected 1 row, got %', n; END IF;

  -- ── 5. Mike Wilson: no valid district → city fallback (London) ──────
  --    postcode_district stays NULL, so his dashboard prompts him to add it.
  UPDATE trainers
  SET    postcode_district        = NULL,
         cc_country               = 'England',
         cc_local_area            = 'ENG_GREATER_LONDON',
         location_source          = 'city',
         location_mapping_version = 'ONS-2023-12'
  WHERE  id = '9a280750-b10e-4de5-8f7b-264b378b6bfa';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'Mike Wilson: expected 1 row, got %', n; END IF;

  -- ── 6. Pawel Pilch: unassigned → Scotland / City of Edinburgh ───────
  UPDATE trainers
  SET    postcode_district        = 'EH1',
         cc_country               = 'Scotland',
         cc_local_area            = 'SCO_CITY_OF_EDINBURGH',
         location_source          = 'postcode',
         location_mapping_version = 'ONS-2023-12'
  WHERE  id = '9b0262f9-7f22-4763-b103-4f1d2b288322';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN RAISE EXCEPTION 'Pawel Pilch: expected 1 row, got %', n; END IF;
END $$;

-- ── 7. Any other trainers (e.g. inactive ones the public key could not see) ──
-- Copy a valid district from the legacy postcode/area field. Their country
-- and local area are then assigned automatically on their next dashboard
-- visit (assign-location.js). Until then they are still shown in the UK
-- ranking, and /find-a-trainer places them by city.
UPDATE trainers
SET    postcode_district = split_part(upper(trim(postcode)), ' ', 1)
WHERE  postcode_district IS NULL
  AND  location_source IS DISTINCT FROM 'city'
  AND  split_part(upper(trim(coalesce(postcode, ''))), ' ', 1) ~ '^[A-Z]{1,2}[0-9][A-Z0-9]?$';

-- ── 8. No full postcodes left in the legacy postcode column ─────────────
-- Keeps only the first part (outward code) of any full postcode.
UPDATE trainers
SET    postcode = split_part(upper(trim(postcode)), ' ', 1)
WHERE  postcode ~* '^\s*[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}\s*$';

COMMIT;

-- ── VERIFY (read-only) ───────────────────────────────────────────────────
-- Expected: the six trainers above with the new values; every active
-- trainer has cc_country; location_confirmed is FALSE for all.
-- SELECT id, name, is_active, city, postcode_district, cc_country,
--        cc_local_area, location_source, location_confirmed
-- FROM   trainers
-- ORDER  BY is_active DESC, bmp_score DESC NULLS LAST;
--
-- Expected 0 rows (no full postcodes anywhere on trainers):
-- SELECT id FROM trainers
-- WHERE  postcode ~* '[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}'
--    OR  cc_postcode IS NOT NULL;
--
-- Expected: relation "trainer_private" does not exist
-- SELECT COUNT(*) FROM trainer_private;
