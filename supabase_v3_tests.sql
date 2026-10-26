-- ══════════════════════════════════════════════════════════════════════════════
-- CoachCards — BMP v3 Validation Test Suite
-- Run ONLY on a Supabase branch or local dev instance. NEVER on production.
--
-- Structure:
--   Section A — Pre-flight checks (runs on any DB, read-only)
--   Section B — Formula math tests (pure SQL, no table writes)
--   Section C — Functional tests (require DB with v3 functions deployed)
--   Section D — Score simulation verification (matches BMP v3 report)
--
-- How to run on a Supabase branch:
--   1. Dashboard → Branching → New branch from main.
--   2. Run supabase_bmp_v3_migration.sql on the branch.
--   3. Open SQL Editor on the branch and run this file section by section.
--   4. All test data is ROLLED BACK at the end of Section C and D — no
--      test records persist after execution.
--
-- NEVER insert test reviews or test trainers into the production database.
-- ══════════════════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════════════════
-- SECTION A — Pre-flight checks (read-only, run on any environment)
-- ════════════════════════════════════════════════════════════════════════════

-- A1. Confirm v3 migration has been applied (distinct_reviewer_count column exists)
SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'trainers'
      AND column_name  = 'distinct_reviewer_count'
  ) THEN 'PASS A1: distinct_reviewer_count column present (v3 migration applied)'
    ELSE 'FAIL A1: distinct_reviewer_count column MISSING — run supabase_bmp_v3_migration.sql first'
  END AS check_a1;

-- A2. Confirm calculate_bmp_for_trainer exists and uses 8@4.0★ prior
SELECT
  CASE WHEN p.prosrc LIKE '%8.0 * 4.0%' OR p.prosrc LIKE '%32.0%'
    THEN 'PASS A2: calculate_bmp_for_trainer uses 8@4.0★ prior (v3)'
    ELSE 'FAIL A2: function body does not contain 8@4.0★ prior — check version'
  END AS check_a2
FROM pg_proc p
WHERE p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND p.proname = 'calculate_bmp_for_trainer';

-- A3. Confirm anon cap present in function body
SELECT
  CASE WHEN p.prosrc LIKE '%v_anon_ids%'
    THEN 'PASS A3: anon cap (v_anon_ids) present in calculate_bmp_for_trainer'
    ELSE 'FAIL A3: v_anon_ids not found — anon cap not implemented'
  END AS check_a3
FROM pg_proc p
WHERE p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND p.proname = 'calculate_bmp_for_trainer';

-- A4. Confirm refresh_trending_status also uses anon cap
SELECT
  CASE WHEN p.prosrc LIKE '%v_anon_ids%'
    THEN 'PASS A4: anon cap (v_anon_ids) present in refresh_trending_status'
    ELSE 'FAIL A4: v_anon_ids not found in refresh_trending_status'
  END AS check_a4
FROM pg_proc p
WHERE p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND p.proname = 'refresh_trending_status';

-- A5. Confirm get_own_trainer_profile returns distinct_reviewer_count
SELECT
  CASE WHEN p.prosrc LIKE '%distinct_reviewer_count%'
    THEN 'PASS A5: get_own_trainer_profile includes distinct_reviewer_count'
    ELSE 'FAIL A5: distinct_reviewer_count missing from get_own_trainer_profile'
  END AS check_a5
FROM pg_proc p
WHERE p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND p.proname = 'get_own_trainer_profile';

-- A6. Confirm zzz_on_review_bmp_update trigger exists
SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE event_object_schema = 'public'
      AND event_object_table  = 'reviews'
      AND trigger_name        = 'zzz_on_review_bmp_update'
  ) THEN 'PASS A6: trigger zzz_on_review_bmp_update exists on reviews'
    ELSE 'WARN A6: trigger zzz_on_review_bmp_update not found (check supabase_trending_autoupdate.sql)'
  END AS check_a6;

-- A7. Confirm refresh_all_trending batch wrapper exists
SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc p
    WHERE p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
      AND p.proname = 'refresh_all_trending'
  ) THEN 'PASS A7: refresh_all_trending batch wrapper exists'
    ELSE 'WARN A7: refresh_all_trending not found'
  END AS check_a7;

-- A8. Trainer and review counts (informational)
SELECT
  (SELECT COUNT(*) FROM public.trainers)             AS total_trainers,
  (SELECT COUNT(*) FROM public.trainers WHERE is_active) AS active_trainers,
  (SELECT COUNT(*) FROM public.trainers WHERE bmp_score > 0) AS scored_trainers,
  (SELECT COUNT(*) FROM public.reviews WHERE is_verified) AS verified_reviews,
  (SELECT COUNT(*) FROM public.reviews WHERE is_verified AND client_id IS NULL) AS anon_reviews;


-- ════════════════════════════════════════════════════════════════════════════
-- SECTION B — Formula math tests (pure SQL, no table writes)
-- These tests verify the formula arithmetic with inline calculations.
-- They pass on any PostgreSQL instance, regardless of whether the migration
-- has been applied. No ASSERT is used — results are shown as PASS/FAIL rows.
-- ════════════════════════════════════════════════════════════════════════════

WITH formula_tests AS (

  -- B1. Quality formula: n=1, 5★, 8@4.0★ prior
  SELECT 'B1 Quality n=1 5★' AS test_id,
    57.6 AS expected,
    ROUND(LEAST((5.0 + 32.0) / (1.0 + 8.0) / 5.0 * 70.0, 70.0)::NUMERIC, 1) AS actual

  UNION ALL

  -- B2. Quality formula: n=5, all 5★
  SELECT 'B2 Quality n=5 5★',
    61.4,
    ROUND(LEAST((25.0 + 32.0) / (5.0 + 8.0) / 5.0 * 70.0, 70.0)::NUMERIC, 1)

  UNION ALL

  -- B3. Quality formula: n=60, all 5★ (cap)
  SELECT 'B3 Quality n=60 5★',
    68.4,
    ROUND(LEAST((300.0 + 32.0) / (60.0 + 8.0) / 5.0 * 70.0, 70.0)::NUMERIC, 1)

  UNION ALL

  -- B4. Quality formula: n=5, all 1★ (poor reviews)
  SELECT 'B4 Quality n=5 1★',
    39.9,
    ROUND(LEAST((5.0 + 32.0) / (5.0 + 8.0) / 5.0 * 70.0, 70.0)::NUMERIC, 1)

  UNION ALL

  -- B5. Confidence formula: n=1
  SELECT 'B5 Confidence n=1',
    3.5,
    ROUND(LEAST(LN(1.0 + 1.0) / LN(51.0), 1.0) * 20.0, 1)

  UNION ALL

  -- B6. Confidence formula: n=10
  SELECT 'B6 Confidence n=10',
    12.2,
    ROUND(LEAST(LN(10.0 + 1.0) / LN(51.0), 1.0) * 20.0, 1)

  UNION ALL

  -- B7. Confidence formula: n=50 (cap — should be exactly 20.0)
  SELECT 'B7 Confidence n=50 (cap)',
    20.0,
    ROUND(LEAST(LN(50.0 + 1.0) / LN(51.0), 1.0) * 20.0, 1)

  UNION ALL

  -- B8. Confidence formula: n=60 (above cap — should still be 20.0)
  SELECT 'B8 Confidence n=60 (above cap)',
    20.0,
    ROUND(LEAST(LN(60.0 + 1.0) / LN(51.0), 1.0) * 20.0, 1)

  UNION ALL

  -- B9. Activity: raw=7.5 (max theoretical from momentum), no trending
  -- momNorm = min(7.5/7.5,1)*10 = 10, activity = min(10*0.8+0,10) = 8.0
  SELECT 'B9 Activity raw=7.5 no trending',
    8.0,
    ROUND(GREATEST(LEAST(LEAST(7.5 / 7.5, 1.0) * 10.0 * 0.8 + 0.0, 10.0), 0.0)::NUMERIC, 1)

  UNION ALL

  -- B10. Activity: raw=7.5 WITH trending bonus (+2.0)
  -- momNorm=10, activity = min(10*0.8+2,10) = min(10,10) = 10.0
  SELECT 'B10 Activity raw=7.5 trending',
    10.0,
    ROUND(GREATEST(LEAST(LEAST(7.5 / 7.5, 1.0) * 10.0 * 0.8 + 2.0, 10.0), 0.0)::NUMERIC, 1)

  UNION ALL

  -- B11. Activity floor at n=20 (floor = 5.0), no momentum
  -- activity = max(min(0+0,10), 5.0) = 5.0
  SELECT 'B11 Activity floor n=20 no momentum',
    5.0,
    ROUND(GREATEST(LEAST(0.0 * 0.8 + 0.0, 10.0), LEAST(20.0 / 20.0, 1.0) * 5.0)::NUMERIC, 1)

  UNION ALL

  -- B12. Activity floor at n=10 (floor = 2.5), no momentum
  SELECT 'B12 Activity floor n=10 no momentum',
    2.5,
    ROUND(GREATEST(LEAST(0.0, 10.0), LEAST(10.0 / 20.0, 1.0) * 5.0)::NUMERIC, 1)

  UNION ALL

  -- B13. Activity floor at n=1 (floor = 0.25), no momentum
  SELECT 'B13 Activity floor n=1 no momentum',
    0.3,   -- ROUND(0.25, 1) = 0.3
    ROUND(GREATEST(LEAST(0.0, 10.0), LEAST(1.0 / 20.0, 1.0) * 5.0)::NUMERIC, 1)

  UNION ALL

  -- B14. Full BMP: n=1, 5★, in 7d, no trending
  -- 57.6 + 3.5 + 3.2 = 64.3
  SELECT 'B14 Full BMP n=1',
    64.3,
    ROUND((
      LEAST((5.0 + 32.0) / (1.0 + 8.0) / 5.0 * 70.0, 70.0) +
      LEAST(LN(2.0) / LN(51.0), 1.0) * 20.0 +
      GREATEST(LEAST(LEAST(3.0 / 7.5, 1.0) * 10.0 * 0.8 + 0.0, 10.0),
               LEAST(1.0 / 20.0, 1.0) * 5.0)
    )::NUMERIC, 1)

  UNION ALL

  -- B15. Full BMP: n=3, 5★, trending (2 in 7d + 1 in prev)
  -- 59.8 + 7.1 + 10.0 = 76.9
  SELECT 'B15 Full BMP n=3 trending',
    76.9,
    ROUND((
      LEAST((15.0 + 32.0) / (3.0 + 8.0) / 5.0 * 70.0, 70.0) +
      LEAST(LN(4.0) / LN(51.0), 1.0) * 20.0 +
      GREATEST(LEAST(LEAST(7.5 / 7.5, 1.0) * 10.0 * 0.8 + 2.0, 10.0),
               LEAST(3.0 / 20.0, 1.0) * 5.0)
    )::NUMERIC, 1)

  UNION ALL

  -- B16. Full BMP: n=20, 5★, trending (floor=5, capped at 10)
  -- 66.0 + 15.5 + 10.0 = 91.5
  SELECT 'B16 Full BMP n=20 trending',
    91.5,
    ROUND((
      LEAST((100.0 + 32.0) / (20.0 + 8.0) / 5.0 * 70.0, 70.0) +
      LEAST(LN(21.0) / LN(51.0), 1.0) * 20.0 +
      GREATEST(LEAST(LEAST(18.75 / 7.5, 1.0) * 10.0 * 0.8 + 2.0, 10.0),
               LEAST(20.0 / 20.0, 1.0) * 5.0)
    )::NUMERIC, 1)

)
SELECT
  test_id,
  expected,
  actual,
  CASE WHEN ABS(actual - expected) < 0.15
    THEN 'PASS'
    ELSE 'FAIL — delta: ' || (actual - expected)::TEXT
  END AS result
FROM formula_tests
ORDER BY test_id;


-- ════════════════════════════════════════════════════════════════════════════
-- SECTION C — Functional tests (requires live DB with v3 applied)
-- ALL test data is ROLLED BACK at the end — nothing persists.
--
-- How these tests work:
--   • SET session_replication_role = 'replica' disables FK constraint triggers,
--     allowing test trainer + review rows to be inserted without real auth.users
--     or clients entries. Only safe inside a transaction that is rolled back.
--   • calculate_bmp_for_trainer is called, results read back, then ROLLBACK.
--   • RAISE NOTICE shows PASS/FAIL for each test.
-- ════════════════════════════════════════════════════════════════════════════

-- Shared test helper — persists in the test schema (not harmful; no data)
CREATE OR REPLACE FUNCTION public.assert_near(
  label     TEXT,
  actual    FLOAT,
  expected  FLOAT,
  tolerance FLOAT DEFAULT 0.15
)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF ABS(actual - expected) <= tolerance THEN
    RAISE NOTICE 'PASS %: % ≈ % (expected)',
      label, ROUND(actual::NUMERIC,1), ROUND(expected::NUMERIC,1);
  ELSE
    RAISE WARNING 'FAIL %: got % expected % (delta %)',
      label, ROUND(actual::NUMERIC,1), ROUND(expected::NUMERIC,1),
      ROUND((actual-expected)::NUMERIC,2);
  END IF;
END;
$$;

BEGIN;

-- Disable FK checks so test rows can be inserted without real auth.users entries
SET LOCAL session_replication_role = 'replica';

-- Fixed test UUIDs — chosen to be conspicuously fake
-- Trainer: 00000000-0000-0000-beef-300000000001
-- Clients: 00000000-0000-0000-beef-c00000000001 through ...c00000000020
-- Reviews: inserted with gen_random_uuid() per test

DO $$
DECLARE
  -- Test trainer
  t_id  UUID := '00000000-0000-0000-beef-300000000001';
  t_user UUID := '00000000-0000-0000-beef-a00000000001';

  v_bmp FLOAT;
  v_trending BOOLEAN;
  v_drc INTEGER;
  v_floor_bmp FLOAT;
  PASS_COUNT INTEGER := 0;
  FAIL_COUNT INTEGER := 0;

BEGIN
  -- ── Setup: insert test trainer ─────────────────────────────────
  INSERT INTO public.trainers (id, user_id, name, is_active, bmp_score, is_trending, review_count, star_rating, recent_review_count)
  VALUES (t_id, t_user, 'TEST BMP v3 Trainer', TRUE, 0, FALSE, 0, 0, 0)
  ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

  RAISE NOTICE '--- C1: No reviews → BMP=0, is_trending=FALSE, drc=0 ---';
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score, is_trending, COALESCE(distinct_reviewer_count, 0)
  INTO v_bmp, v_trending, v_drc FROM public.trainers WHERE id = t_id;
  PERFORM assert_near('C1 BMP=0', v_bmp, 0);
  IF NOT v_trending THEN RAISE NOTICE 'PASS C1 NOT trending'; ELSE RAISE WARNING 'FAIL C1 SHOULD NOT be trending'; END IF;
  IF v_drc = 0 THEN RAISE NOTICE 'PASS C1 drc=0'; ELSE RAISE WARNING 'FAIL C1 drc should=0, got=%', v_drc; END IF;

  RAISE NOTICE '--- C2: 1 auth client, 5★, today → BMP≈64.3, Fresh Face ---';
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
  VALUES (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000001', 5.0, TRUE, 'Test Client 1', gen_random_uuid(), NOW());
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score, is_trending, COALESCE(distinct_reviewer_count, 0)
  INTO v_bmp, v_trending, v_drc FROM public.trainers WHERE id = t_id;
  PERFORM assert_near('C2 BMP', v_bmp, 64.3);
  IF NOT v_trending THEN RAISE NOTICE 'PASS C2 NOT trending (only 1 review in 7d)'; ELSE RAISE WARNING 'FAIL C2 should NOT be trending'; END IF;
  IF v_drc = 1 THEN RAISE NOTICE 'PASS C2 drc=1 (Fresh Face ✓)'; ELSE RAISE WARNING 'FAIL C2 drc should=1 for Fresh Face, got=%', v_drc; END IF;

  RAISE NOTICE '--- C3: Same client reviews twice → dedup, eff_count still 1 ---';
  -- Add a second review from the SAME client (lower rating)
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
  VALUES (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000001', 3.0, TRUE, 'Test Client 1', gen_random_uuid(), NOW() - INTERVAL '1 hour');
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score, is_trending, COALESCE(distinct_reviewer_count, 0)
  INTO v_bmp, v_trending, v_drc FROM public.trainers WHERE id = t_id;
  -- eff_count should still be 1 (latest review from this client = 5★, the older 3★ is discarded)
  -- BMP should be same as C2 (deduplication preserves most recent = 5★)
  PERFORM assert_near('C3 BMP same as C2 (dedup)', v_bmp, 64.3);
  IF v_drc = 1 THEN RAISE NOTICE 'PASS C3 drc=1 (same client, still 1 distinct)'; ELSE RAISE WARNING 'FAIL C3 drc should=1, got=%', v_drc; END IF;

  RAISE NOTICE '--- C4: Add 2nd distinct auth client (yesterday) → Fresh Face, 2 distinct ---';
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
  VALUES (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000002', 5.0, TRUE, 'Test Client 2', gen_random_uuid(), NOW() - INTERVAL '12 hours');
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score, is_trending, COALESCE(distinct_reviewer_count, 0)
  INTO v_bmp, v_trending, v_drc FROM public.trainers WHERE id = t_id;
  IF v_drc = 2 THEN RAISE NOTICE 'PASS C4 drc=2 (Fresh Face ✓ at 2 distinct)'; ELSE RAISE WARNING 'FAIL C4 drc should=2, got=%', v_drc; END IF;

  RAISE NOTICE '--- C5: Add 3rd distinct auth client → Fresh Face expires (drc=3) ---';
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
  VALUES (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000003', 5.0, TRUE, 'Test Client 3', gen_random_uuid(), NOW() - INTERVAL '10 days');
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score, is_trending, COALESCE(distinct_reviewer_count, 0)
  INTO v_bmp, v_trending, v_drc FROM public.trainers WHERE id = t_id;
  IF v_drc = 3 THEN RAISE NOTICE 'PASS C5 drc=3 (Fresh Face ✗ at 3 distinct)'; ELSE RAISE WARNING 'FAIL C5 drc should=3, got=%', v_drc; END IF;
  -- Trending: 7d has 2 reviews (client1 + client2 from today/yesterday) ≥2 ✓
  --           prev(7-28d) has client3 (10 days ago) ≥1 ✓ → TRENDING
  IF v_trending THEN RAISE NOTICE 'PASS C5 IS trending (2 in 7d + 1 in prev window)'; ELSE RAISE WARNING 'FAIL C5 should be trending'; END IF;

  RAISE NOTICE '--- C6: Trending expires — simulate by adding old reviews only (no new 7d) ---';
  -- Clear all test reviews for this trainer, re-insert all with old dates
  DELETE FROM public.reviews WHERE trainer_id = t_id;
  -- 3 reviews, all 15+ days old (outside 7d window, inside 7-28d)
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
  VALUES
    (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000001', 5.0, TRUE, 'Test Client 1', gen_random_uuid(), NOW() - INTERVAL '15 days'),
    (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000002', 5.0, TRUE, 'Test Client 2', gen_random_uuid(), NOW() - INTERVAL '20 days'),
    (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000003', 5.0, TRUE, 'Test Client 3', gen_random_uuid(), NOW() - INTERVAL '25 days');
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score, is_trending, COALESCE(distinct_reviewer_count, 0)
  INTO v_bmp, v_trending, v_drc FROM public.trainers WHERE id = t_id;
  IF NOT v_trending THEN RAISE NOTICE 'PASS C6 NOT trending (0 reviews in 7d)'; ELSE RAISE WARNING 'FAIL C6 should NOT be trending'; END IF;
  -- Also test refresh_trending_status produces same result
  PERFORM refresh_trending_status(t_id);
  SELECT is_trending INTO v_trending FROM public.trainers WHERE id = t_id;
  IF NOT v_trending THEN RAISE NOTICE 'PASS C6 refresh_trending_status also NOT trending'; ELSE RAISE WARNING 'FAIL C6 refresh_trending_status should NOT be trending'; END IF;

  RAISE NOTICE '--- C7: Activity floor — 20 reviews, all >90d old (no momentum) ---';
  DELETE FROM public.reviews WHERE trainer_id = t_id;
  -- Insert 20 reviews from 20 distinct clients, all 100 days ago
  FOR i IN 1..20 LOOP
    INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
    VALUES (
      gen_random_uuid(), t_id,
      ('00000000-0000-0000-beef-c000000000' || LPAD(i::TEXT, 2, '0'))::UUID,
      5.0, TRUE, 'Client ' || i, gen_random_uuid(),
      NOW() - INTERVAL '100 days'
    );
  END LOOP;
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score, is_trending INTO v_bmp, v_trending FROM public.trainers WHERE id = t_id;
  -- Expected: quality=66.0, confidence=15.5, activity=floor=5.0 → BMP=86.5
  -- (floor = min(20/20,1)*5 = 5.0; no momentum)
  PERFORM assert_near('C7 BMP (floor only)', v_bmp, 86.5, 0.3);
  IF NOT v_trending THEN RAISE NOTICE 'PASS C7 NOT trending (0 reviews in 7d)'; ELSE RAISE WARNING 'FAIL C7 should NOT be trending'; END IF;

  RAISE NOTICE '--- C8: Anonymous review cap — 6 anon reviews, only 5 should count ---';
  DELETE FROM public.reviews WHERE trainer_id = t_id;
  -- Insert 6 anonymous reviews (client_id NULL), all from today
  FOR i IN 1..6 LOOP
    INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
    VALUES (
      gen_random_uuid(), t_id, NULL,
      5.0, TRUE, 'Anon ' || i, gen_random_uuid(),
      NOW() - (i * INTERVAL '10 minutes')  -- deterministic ordering: most recent first
    );
  END LOOP;
  PERFORM calculate_bmp_for_trainer(t_id);
  -- Expected: eff_count = 5 (cap), sum = 25, same BMP as 5 anon reviews
  -- quality=(25+32)/(5+8)/5*70=61.4, confidence=9.1, activity (5 in 7d, period_7d=min(5,2)=2)
  -- raw=6, momNorm=8, activity=max(6.4,1.25)=6.4
  -- BMP = 61.4 + 9.1 + 6.4 = 76.9 — NOT trending (no prev window)
  SELECT bmp_score, is_trending, COALESCE(distinct_reviewer_count, 0)
  INTO v_bmp, v_trending, v_drc FROM public.trainers WHERE id = t_id;
  PERFORM assert_near('C8 BMP 6→5 anon cap', v_bmp, 76.9, 0.3);
  IF v_drc = 0 THEN RAISE NOTICE 'PASS C8 drc=0 (anon reviews do not count toward Fresh Face)'; ELSE RAISE WARNING 'FAIL C8 drc should=0, got=%', v_drc; END IF;

  RAISE NOTICE '--- C8b: 20 anon reviews → same BMP as 5 (cap proof) ---';
  DELETE FROM public.reviews WHERE trainer_id = t_id;
  FOR i IN 1..20 LOOP
    INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
    VALUES (
      gen_random_uuid(), t_id, NULL,
      5.0, TRUE, 'Anon ' || i, gen_random_uuid(),
      NOW() - (i * INTERVAL '5 minutes')
    );
  END LOOP;
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score INTO v_bmp FROM public.trainers WHERE id = t_id;
  PERFORM assert_near('C8b BMP 20→5 anon cap (same as C8)', v_bmp, 76.9, 0.3);

  RAISE NOTICE '--- C9: Trigger test — insert unverified, then approve ---';
  DELETE FROM public.reviews WHERE trainer_id = t_id;
  -- Reset trainer
  UPDATE public.trainers SET bmp_score=0, is_trending=FALSE WHERE id=t_id;
  -- Insert unverified review
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
  VALUES (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000001', 5.0, FALSE, 'Test Client 1', gen_random_uuid(), NOW());
  -- Confirm BMP still 0 (unverified)
  SELECT bmp_score INTO v_bmp FROM public.trainers WHERE id = t_id;
  IF v_bmp = 0 THEN RAISE NOTICE 'PASS C9a Unverified review does not change BMP'; ELSE RAISE WARNING 'FAIL C9a BMP should still be 0, got=%', v_bmp; END IF;
  -- Approve it (triggers zzz_on_review_bmp_update → calculate_bmp_for_trainer)
  UPDATE public.reviews SET is_verified = TRUE
  WHERE trainer_id = t_id AND is_verified = FALSE;
  -- BMP should now be non-zero if trigger fired
  SELECT bmp_score INTO v_bmp FROM public.trainers WHERE id = t_id;
  IF v_bmp > 0 THEN RAISE NOTICE 'PASS C9b Approval trigger fired — BMP=% (non-zero)', ROUND(v_bmp::NUMERIC,1); ELSE RAISE WARNING 'FAIL C9b Trigger did not fire — BMP still 0 (check zzz_on_review_bmp_update trigger)'; END IF;

  RAISE NOTICE '--- C10: Building Reputation — trainer with 0 reviews (clean check) ---';
  DELETE FROM public.reviews WHERE trainer_id = t_id;
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score, is_trending INTO v_bmp, v_trending FROM public.trainers WHERE id = t_id;
  IF v_bmp = 0 THEN RAISE NOTICE 'PASS C10 BMP=0 (Building Reputation state)'; ELSE RAISE WARNING 'FAIL C10 BMP should=0, got=%', v_bmp; END IF;

  RAISE NOTICE '--- C11: Mixed good+bad reviews ---';
  DELETE FROM public.reviews WHERE trainer_id = t_id;
  -- 3 reviews: 5★ (today), 1★ (yesterday), 4★ (5 days ago), all auth
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
  VALUES
    (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000001', 5.0, TRUE, 'Client 1', gen_random_uuid(), NOW()),
    (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000002', 1.0, TRUE, 'Client 2', gen_random_uuid(), NOW() - INTERVAL '1 day'),
    (gen_random_uuid(), t_id, '00000000-0000-0000-beef-c00000000003', 4.0, TRUE, 'Client 3', gen_random_uuid(), NOW() - INTERVAL '5 days');
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score, is_trending INTO v_bmp, v_trending FROM public.trainers WHERE id = t_id;
  -- eff_count=3, sum=10, quality=(10+32)/(3+8)/5*70=53.4
  -- confidence=7.1, activity (all in 7d, but only 5★ and 4★ qualify ≥3.5)
  -- trending_7d: 5★ + 4★ in 7d = 2, trending_prev = 0 → NOT trending
  -- period_7d=min(2,2)=2, period_8_30d=0, raw=6, activity=max(6.4, 0.75)=6.4
  -- BMP = 53.4 + 7.1 + 6.4 = 66.9 Developing
  PERFORM assert_near('C11 BMP mixed reviews', v_bmp, 66.9, 0.5);
  IF NOT v_trending THEN RAISE NOTICE 'PASS C11 NOT trending (no prev window)'; ELSE RAISE WARNING 'FAIL C11 should NOT be trending'; END IF;

  RAISE NOTICE '--- C12: Backfill completeness check ---';
  -- Check that all active trainers have non-null bmp_score after backfill
  -- (checking that the backfill query would work, not running it here)
  RAISE NOTICE 'INFO C12: Backfill completeness is checked in Section D.';

END;
$$;

-- Clean up test data
DELETE FROM public.reviews WHERE trainer_id = '00000000-0000-0000-beef-300000000001';
DELETE FROM public.trainers WHERE id = '00000000-0000-0000-beef-300000000001';

ROLLBACK;  -- ensures nothing persists, including FK bypass state
DO $$ BEGIN RAISE NOTICE 'Section C complete. All test data rolled back.'; END; $$;


-- ════════════════════════════════════════════════════════════════════════════
-- SECTION D — Score simulation verification
-- Compares SQL formula output against the BMP v3 report simulation values.
-- Run INSIDE A TRANSACTION that is rolled back to avoid persisting test data.
-- ════════════════════════════════════════════════════════════════════════════

-- assert_near helper (idempotent — safe to re-run if Section D is run independently)
CREATE OR REPLACE FUNCTION public.assert_near(
  label     TEXT,
  actual    FLOAT,
  expected  FLOAT,
  tolerance FLOAT DEFAULT 0.15
)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF ABS(actual - expected) <= tolerance THEN
    RAISE NOTICE 'PASS %: % ≈ % (expected)',
      label, ROUND(actual::NUMERIC,1), ROUND(expected::NUMERIC,1);
  ELSE
    RAISE WARNING 'FAIL %: got % expected % (delta %)',
      label, ROUND(actual::NUMERIC,1), ROUND(expected::NUMERIC,1),
      ROUND((actual-expected)::NUMERIC,2);
  END IF;
END;
$$;

BEGIN;
SET LOCAL session_replication_role = 'replica';

DO $$
DECLARE
  t_id  UUID := '00000000-0000-0000-beef-400000000001';
  t_user UUID := '00000000-0000-0000-beef-a00000000002';
  v_bmp FLOAT;
  v_trending BOOLEAN;
  v_drc INTEGER;
  sim_expected FLOAT[][] := ARRAY[
    ARRAY[64.3, 0],   -- n=1,  no trending
    ARRAY[76.9, 1],   -- n=3,  trending
    ARRAY[80.5, 1],   -- n=5,  trending
    ARRAY[86.0, 1],   -- n=10, trending
    ARRAY[91.5, 1],   -- n=20, trending
    ARRAY[95.6, 1],   -- n=35, trending
    ARRAY[98.4, 1]    -- n=60, trending
  ];
  sim_n INT[] := ARRAY[1, 3, 5, 10, 20, 35, 60];
  i INT;
  prev_n INT := 0;
  cur_n INT;
  spread_7d INT;
  spread_prev INT;
  spread_31_90d INT;
  remaining INT;

BEGIN
  INSERT INTO public.trainers (id, user_id, name, is_active, bmp_score, is_trending, review_count, star_rating, recent_review_count)
  VALUES (t_id, t_user, 'TEST Sim Trainer', TRUE, 0, FALSE, 0, 0, 0);

  FOR i IN 1..array_length(sim_n, 1) LOOP
    cur_n := sim_n[i];

    -- Insert reviews for the batch (from prev_n+1 to cur_n)
    -- Spread: 2 in 7d, up to 5 in 7-30d, remainder in 31-90d
    -- For small batches all fit in ≤30d
    remaining := cur_n - prev_n;
    FOR j IN 1..remaining LOOP
      DECLARE
        c_id UUID := ('00000000-0000-0000-51b0-c' || LPAD((prev_n + j)::TEXT, 11, '0'))::UUID;
        rev_age INTERVAL;
      BEGIN
        -- Assign ages: first 2 go in 7d, next 5 in 8-30d, rest in 31-90d
        IF (prev_n + j) <= 2 THEN
          rev_age := ((prev_n + j) * 12) * INTERVAL '1 hour';
        ELSIF (prev_n + j) <= 7 THEN
          rev_age := (8 + (prev_n + j - 2)) * INTERVAL '1 day';
        ELSE
          rev_age := (31 + (prev_n + j - 7)) * INTERVAL '1 day';
        END IF;

        INSERT INTO public.reviews
          (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
        VALUES
          (gen_random_uuid(), t_id, c_id, 5.0, TRUE, 'Sim Client ' || (prev_n+j), gen_random_uuid(), NOW() - rev_age);
      END;
    END LOOP;

    PERFORM calculate_bmp_for_trainer(t_id);
    SELECT bmp_score, is_trending INTO v_bmp, v_trending
    FROM public.trainers WHERE id = t_id;

    PERFORM assert_near('D' || i || ' BMP n=' || cur_n, v_bmp, sim_expected[i][1]);

    IF sim_expected[i][2] = 1 THEN
      IF v_trending THEN
        RAISE NOTICE 'PASS D% trending n=%: IS trending', i, cur_n;
      ELSE
        -- n=1 and n=3 first iteration: trending requires prev window which may not be populated
        -- depending on exact age assignments. Allow a note here.
        IF cur_n <= 2 THEN
          RAISE NOTICE 'NOTE D% n=%: Not trending as expected (insufficient prev window)', i, cur_n;
        ELSE
          RAISE WARNING 'FAIL D% trending n=%: expected IS trending but got NOT trending', i, cur_n;
        END IF;
      END IF;
    ELSE
      IF NOT v_trending THEN
        RAISE NOTICE 'PASS D% not trending n=%: NOT trending', i, cur_n;
      ELSE
        RAISE WARNING 'FAIL D% n=%: expected NOT trending but IS trending', i, cur_n;
      END IF;
    END IF;

    prev_n := cur_n;
  END LOOP;

  -- D-extra: poor review scenario (1★ only)
  DELETE FROM public.reviews WHERE trainer_id = t_id;
  prev_n := 0;
  FOR j IN 1..5 LOOP
    INSERT INTO public.reviews
      (id, trainer_id, client_id, rating, is_verified, reviewer_name, approval_token, created_at)
    VALUES (
      gen_random_uuid(), t_id,
      ('00000000-0000-0000-0bad-c' || LPAD(j::TEXT, 11, '0'))::UUID,
      1.0, TRUE, 'Poor Client ' || j, gen_random_uuid(),
      NOW() - (j * INTERVAL '1 day')
    );
  END LOOP;
  PERFORM calculate_bmp_for_trainer(t_id);
  SELECT bmp_score INTO v_bmp FROM public.trainers WHERE id = t_id;
  -- Expected: n=5, sum=5, quality=(5+32)/(5+8)/5*70=39.9, confidence=9.1, activity=6.4 (if in 7d)
  -- But ratings < 3.5 → momentum period_7d=0 → activity=max(0,1.25)=1.25
  -- BMP = 39.9 + 9.1 + 1.25 = 50.3 Developing
  PERFORM assert_near('D-poor BMP n=5 all 1★', v_bmp, 50.3, 0.5);

  RAISE NOTICE '--- D: Bracket verification ---';
  DECLARE bmp_vals FLOAT[] := ARRAY[64.3, 76.9, 80.5, 91.5, 95.6, 98.4];
  DECLARE brackets TEXT[] := ARRAY['Developing','Established','Strong','Advanced','Elite','Elite'];
  DECLARE threshold_labels TEXT[] := ARRAY['<70','70-79','80-89','90-94','95-100','95-100'];
  BEGIN
    FOR k IN 1..array_length(bmp_vals,1) LOOP
      IF (bmp_vals[k] < 70 AND brackets[k] = 'Developing') OR
         (bmp_vals[k] >= 70 AND bmp_vals[k] < 80 AND brackets[k] = 'Established') OR
         (bmp_vals[k] >= 80 AND bmp_vals[k] < 90 AND brackets[k] = 'Strong') OR
         (bmp_vals[k] >= 90 AND bmp_vals[k] < 95 AND brackets[k] = 'Advanced') OR
         (bmp_vals[k] >= 95 AND brackets[k] = 'Elite') THEN
        RAISE NOTICE 'PASS D-bracket %.1f → %', bmp_vals[k], brackets[k];
      ELSE
        RAISE WARNING 'FAIL D-bracket %.1f → expected % does not match threshold %',
          bmp_vals[k], brackets[k], threshold_labels[k];
      END IF;
    END LOOP;
  END;

END;
$$;

DELETE FROM public.reviews WHERE trainer_id IN (
  '00000000-0000-0000-beef-400000000001',
  '00000000-0000-0000-beef-300000000001'
);
DELETE FROM public.trainers WHERE id IN (
  '00000000-0000-0000-beef-400000000001',
  '00000000-0000-0000-beef-300000000001'
);

ROLLBACK;
DO $$ BEGIN RAISE NOTICE 'Section D complete. All test data rolled back.'; END; $$;


-- ════════════════════════════════════════════════════════════════════════════
-- SECTION E — Post-migration state checks (read-only, run AFTER backfill)
-- ════════════════════════════════════════════════════════════════════════════

-- E1. All active trainers have non-NULL bmp_score after backfill
SELECT
  CASE WHEN COUNT(*) FILTER (WHERE bmp_score IS NULL AND is_active) = 0
    THEN 'PASS E1: All active trainers have bmp_score'
    ELSE 'FAIL E1: ' || COUNT(*) FILTER (WHERE bmp_score IS NULL AND is_active) ||
         ' active trainers have NULL bmp_score — rerun backfill'
  END AS check_e1
FROM public.trainers;

-- E2. All active trainers have non-NULL distinct_reviewer_count
SELECT
  CASE WHEN COUNT(*) FILTER (WHERE distinct_reviewer_count IS NULL AND is_active) = 0
    THEN 'PASS E2: All active trainers have distinct_reviewer_count'
    ELSE 'FAIL E2: ' || COUNT(*) FILTER (WHERE distinct_reviewer_count IS NULL AND is_active) ||
         ' active trainers have NULL distinct_reviewer_count'
  END AS check_e2
FROM public.trainers;

-- E3. Score distribution (sanity check — no scores > 100 or < 0)
SELECT
  CASE WHEN COUNT(*) FILTER (WHERE bmp_score > 100 OR bmp_score < 0) = 0
    THEN 'PASS E3: All bmp_score values in [0, 100]'
    ELSE 'FAIL E3: Out-of-range bmp_score detected'
  END AS check_e3
FROM public.trainers WHERE bmp_score IS NOT NULL;

-- E4. Trending rate (informational — flag if unexpectedly high or zero)
SELECT
  COUNT(*) FILTER (WHERE is_active)                  AS active_trainers,
  COUNT(*) FILTER (WHERE is_active AND is_trending)  AS trending,
  ROUND(100.0 * COUNT(*) FILTER (WHERE is_active AND is_trending) /
    NULLIF(COUNT(*) FILTER (WHERE is_active), 0), 1) AS trending_pct,
  'INFO E4: Review trending % for unexpected values' AS note
FROM public.trainers;

-- E5. Fresh Face candidates (distinct_reviewer_count in [1,2])
SELECT
  COUNT(*) FILTER (WHERE is_active AND distinct_reviewer_count BETWEEN 1 AND 2) AS fresh_face_eligible,
  COUNT(*) FILTER (WHERE is_active AND distinct_reviewer_count = 0)              AS no_auth_reviewers,
  COUNT(*) FILTER (WHERE is_active AND distinct_reviewer_count >= 3)             AS past_fresh_face,
  'INFO E5: Fresh Face distribution' AS note
FROM public.trainers;

-- E6. get_own_trainer_profile JSONB field check
-- Verify the function returns distinct_reviewer_count key in output structure
SELECT
  CASE WHEN p.prosrc LIKE '%distinct_reviewer_count%'
    THEN 'PASS E6: get_own_trainer_profile includes distinct_reviewer_count'
    ELSE 'FAIL E6: distinct_reviewer_count missing from get_own_trainer_profile'
  END AS check_e6
FROM pg_proc p
WHERE p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND p.proname = 'get_own_trainer_profile';
