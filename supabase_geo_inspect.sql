-- ============================================================
-- COACHCARDS — GEO INVESTIGATION: READ-ONLY INSPECTION QUERIES
-- Run these in Supabase SQL Editor to diagnose the current state.
-- These queries make NO changes to any data.
-- ============================================================


-- ── 1. Check whether geo migration files have been run ──────
-- Expected after running geo_01: columns exist on trainers.
-- Expected after running geo_02: ranking_areas has 118 rows.
-- Expected after running geo_03: cc_lad_to_county has ~142 rows.

SELECT
  (SELECT COUNT(*) FROM ranking_areas)                             AS ranking_areas_rows,   -- expect 118 after geo_02
  (SELECT COUNT(*) FROM cc_lad_to_county)                         AS lad_crosswalk_rows,   -- expect ~142 after geo_03
  (SELECT COUNT(*) FROM ranking_areas WHERE area_type = 'local')  AS local_areas,          -- expect 113
  (SELECT COUNT(*) FROM ranking_areas WHERE area_type = 'country') AS country_areas;       -- expect 4


-- ── 2. Check trainer location fields ────────────────────────
-- Shows whether geo columns exist and how many trainers have them.

SELECT
  COUNT(*)                                                           AS total_active_trainers,
  COUNT(city)                                                        AS with_city,
  COUNT(location)                                                    AS with_location,
  COUNT(cc_country)                                                  AS with_cc_country,         -- expect 0 if Phase 2 not built
  COUNT(cc_local_area)                                               AS with_cc_local_area,       -- expect 0 if Phase 2 not built
  COUNT(*) FILTER (WHERE location_confirmed = TRUE)                  AS location_confirmed_count, -- expect 0 if Phase 2 not built
  COUNT(*) FILTER (WHERE cc_country IS NOT NULL AND location_confirmed = FALSE) AS unconfirmed_with_country
FROM trainers
WHERE is_active = TRUE;


-- ── 3. Sample trainer location data ─────────────────────────
-- See what city/location data current trainers have.

SELECT
  name,
  city,
  location,
  cc_country,
  cc_local_area,
  location_confirmed,
  location_source
FROM trainers
WHERE is_active = TRUE
ORDER BY bmp_score DESC NULLS LAST
LIMIT 20;


-- ── 4. Check RLS status on ranking_areas ────────────────────
-- If relrowsecurity = true AND no SELECT policy exists for anon,
-- the Astro page (which uses the anon key) will get 0 rows even
-- after geo_02 is run. In that case, add the policy in geo_rls.sql.

SELECT
  relname        AS table_name,
  relrowsecurity AS rls_enabled,
  relforcerowsecurity AS rls_forced
FROM pg_class
WHERE relname IN ('ranking_areas', 'cc_lad_to_county')
  AND relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');


-- ── 5. Check existing RLS policies on ranking_areas ─────────

SELECT
  schemaname, tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename IN ('ranking_areas', 'cc_lad_to_county');


-- ── 6. Check trainer columns exist (post geo_01) ────────────

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'trainers'
  AND column_name IN (
    'cc_postcode', 'cc_country', 'cc_local_area',
    'location_confirmed', 'location_confirmed_at',
    'location_source', 'location_cooldown_until', 'location_mapping_version'
  )
ORDER BY column_name;
