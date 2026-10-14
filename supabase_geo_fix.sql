-- ============================================================
-- COACHCARDS — GEO FIX: POPULATE REFERENCE TABLES + RLS POLICY
-- Run ONLY after reviewing supabase_geo_inspect.sql output.
--
-- What this does:
--   • Runs geo_02: inserts 118 rows into ranking_areas (UK, 4
--     countries, 113 local areas). ON CONFLICT DO NOTHING makes
--     it safe to re-run without duplicating rows.
--   • Runs geo_03: inserts ~142 rows into cc_lad_to_county.
--   • Runs geo_04: creates/replaces resolve_postcode_area() and
--     get_trainer_ranks() DB functions.
--   • Adds public SELECT policy on ranking_areas so the Astro
--     page (anon key) can read it at build/SSR time.
--
-- NO trainer data is modified by this file.
-- NO location_confirmed flags are changed.
-- NO BMP scores or UK rankings are affected.
-- ============================================================


-- ── Step 1: Run geo_02 (ranking_areas data) ──────────────────
-- Copy the full contents of supabase_geo_02_ranking_areas.sql here,
-- OR run that file directly in the SQL Editor.
-- It is safe to run: all INSERTs use ON CONFLICT (id) DO NOTHING.

-- Run supabase_geo_02_ranking_areas.sql


-- ── Step 2: Run geo_03 (cc_lad_to_county crosswalk) ─────────
-- Run supabase_geo_03_lad_crosswalk.sql


-- ── Step 3: Run geo_04 (DB functions) ───────────────────────
-- Run supabase_geo_04_functions.sql


-- ── Step 4: RLS policy — allow anon reads on ranking_areas ──
-- Only needed if query 4 in supabase_geo_inspect.sql showed
-- relrowsecurity = TRUE for ranking_areas.
-- Skip this step if RLS is disabled on that table.

DO $$
BEGIN
  -- Create policy only if it doesn't already exist
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'ranking_areas'
      AND policyname = 'public_read_ranking_areas'
  ) THEN
    EXECUTE 'CREATE POLICY public_read_ranking_areas
      ON ranking_areas
      FOR SELECT
      TO anon, authenticated
      USING (true)';
    RAISE NOTICE 'Created public_read_ranking_areas policy';
  ELSE
    RAISE NOTICE 'public_read_ranking_areas policy already exists — skipped';
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'cc_lad_to_county'
      AND policyname = 'public_read_lad_crosswalk'
  ) THEN
    EXECUTE 'CREATE POLICY public_read_lad_crosswalk
      ON cc_lad_to_county
      FOR SELECT
      TO anon, authenticated
      USING (true)';
    RAISE NOTICE 'Created public_read_lad_crosswalk policy';
  ELSE
    RAISE NOTICE 'public_read_lad_crosswalk policy already exists — skipped';
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
