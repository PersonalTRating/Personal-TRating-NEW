-- ============================================================
-- COACHCARDS — OPTIONAL: TRAINER LOCATION BACKFILL
-- DO NOT RUN without explicit approval.
--
-- Purpose: Set cc_country = 'England' and cc_local_area =
-- 'ENG_GREATER_LONDON' for trainers whose city is 'london',
-- and mark them location_confirmed = TRUE.
--
-- Effect: These trainers will appear in England country rankings
-- and Greater London local rankings with proper rank numbers
-- (computed at next Netlify deploy).
--
-- Scope: Only affects trainers where city = 'london' (case-
-- insensitive) AND cc_country IS NULL (not already confirmed).
-- Does NOT affect trainers with existing cc_country data.
-- Does NOT affect BMP scores, review counts or UK rankings.
--
-- REVIEW the SELECT below before approving the UPDATE.
-- The ranking_areas row 'ENG_GREATER_LONDON' must exist
-- (run supabase_geo_fix.sql first).
-- ============================================================


-- ── Step A: Preview which rows will be affected ──────────────
-- Run this first. Review before proceeding to Step B.

SELECT
  id,
  name,
  city,
  location,
  cc_country,
  cc_local_area,
  location_confirmed
FROM trainers
WHERE LOWER(city) = 'london'
  AND cc_country IS NULL
  AND is_active = TRUE
ORDER BY bmp_score DESC NULLS LAST;


-- ── Step B: Apply the backfill ───────────────────────────────
-- Only run after reviewing Step A output and getting approval.
-- Wrapped in a transaction so it can be rolled back if needed.

BEGIN;

UPDATE trainers
SET
  cc_country              = 'England',
  cc_local_area           = 'ENG_GREATER_LONDON',
  location_confirmed      = TRUE,
  location_confirmed_at   = NOW(),
  location_source         = 'admin',
  location_mapping_version = 'ONS-2023-12'
WHERE
  LOWER(city) = 'london'
  AND cc_country IS NULL
  AND is_active = TRUE;

-- Verify the update
SELECT
  id,
  name,
  city,
  cc_country,
  cc_local_area,
  location_confirmed,
  location_source
FROM trainers
WHERE LOWER(city) = 'london'
  AND is_active = TRUE
ORDER BY bmp_score DESC NULLS LAST;

-- COMMIT;   ← Uncomment and run this line to finalise, OR
-- ROLLBACK; ← Uncomment to undo (safe — run BEGIN again first)
-- The transaction stays open until you run COMMIT or ROLLBACK.
