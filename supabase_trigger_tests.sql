-- ══════════════════════════════════════════════════════════════════════════════
-- CoachCards — BMP Trigger Lifecycle Tests  (Results-panel edition)
--
-- How results surface:
--   • Nine rows appear in the Supabase SQL Editor RESULTS panel.
--   • Any FAIL row also raises an EXCEPTION so the run cannot silently succeed.
--   • All synthetic data is rolled back; nothing persists.
--   • Triggers remain enabled throughout.
--
-- Prerequisites (apply to CoachCards-Test in order):
--   1. supabase_test_environment_setup.sql
--   2. supabase_bmp_v3_migration.sql
--   3. supabase_bmp_trigger_fix.sql
-- ══════════════════════════════════════════════════════════════════════════════


-- ── Step 0: Results table ─────────────────────────────────────────────────────
-- Created OUTSIDE the test transaction so its structure survives ROLLBACK.
-- The rows inserted inside the transaction are rolled back after the SELECT.

DROP TABLE IF EXISTS _bmp_trigger_results;
CREATE TEMP TABLE _bmp_trigger_results (
  num       INTEGER,
  test_name TEXT,
  expected  TEXT,
  actual    TEXT,
  status    TEXT   -- 'PASS' | 'FAIL'
);


-- ── Step 1: Pre-flight checks (read-only) ────────────────────────────────────

SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE  event_object_schema = 'public'
      AND  event_object_table  = 'reviews'
      AND  trigger_name        = 'zzz_on_review_bmp_update'
  ) THEN 'PASS PRE-1: trigger present'
    ELSE 'FAIL PRE-1: run supabase_bmp_trigger_fix.sql first'
  END AS preflight_trigger;

SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc
    WHERE  pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
      AND  proname = 'trigger_recalculate_bmp'
  ) THEN 'PASS PRE-2: trigger_recalculate_bmp function present'
    ELSE 'FAIL PRE-2: function missing — run supabase_bmp_trigger_fix.sql first'
  END AS preflight_fn;

SELECT
  CASE WHEN COUNT(*) = 2
    THEN 'PASS PRE-3: both synthetic trainers present'
    ELSE 'FAIL PRE-3: run supabase_test_environment_setup.sql first'
  END AS preflight_trainers
FROM public.trainers
WHERE id IN (
  '00000000-0000-0000-face-000000000001',
  '00000000-0000-0000-face-000000000002'
);


-- ── Step 2: Main test transaction ────────────────────────────────────────────
-- All public.reviews / public.clients / public.trainers changes are rolled back.
-- _bmp_trigger_results rows are also rolled back, but Supabase captures the
-- SELECT in Step 3 before the ROLLBACK runs.

BEGIN;

DO $tests$
DECLARE
  tr_a UUID := '00000000-0000-0000-face-000000000001';
  tr_b UUID := '00000000-0000-0000-face-000000000002';
  cl_1 UUID := '00000000-0000-0000-bead-000000000001';
  cl_2 UUID := '00000000-0000-0000-bead-000000000002';
  cl_3 UUID := '00000000-0000-0000-bead-000000000003';

  rev_a      UUID;
  rev_b      UUID;
  rev_c      UUID;

  bmp_before DOUBLE PRECISION := 0;
  bmp_after  DOUBLE PRECISION := 0;
  bmp_tr_a   DOUBLE PRECISION := 0;
  bmp_tr_b   DOUBLE PRECISION := 0;
  drc_before INTEGER := 0;
  drc_after  INTEGER := 0;
  trend_before BOOLEAN;
  trend_after  BOOLEAN;

BEGIN

  -- ── Seed ──────────────────────────────────────────────────────────────────
  INSERT INTO public.clients (id, user_id) VALUES
    (cl_1, '00000000-0000-0000-bead-a00000000001'),
    (cl_2, '00000000-0000-0000-bead-a00000000002'),
    (cl_3, '00000000-0000-0000-bead-a00000000003')
  ON CONFLICT (id) DO NOTHING;

  UPDATE public.trainers
  SET bmp_score = 0, is_trending = FALSE,
      distinct_reviewer_count = 0, review_count = 0,
      star_rating = 0, recent_review_count = 0
  WHERE id IN (tr_a, tr_b);

  DELETE FROM public.reviews WHERE trainer_id IN (tr_a, tr_b);


  -- ════════════════════════════════════════════════════════════════════════
  -- T1  INSERT already verified  →  BMP rises from 0
  -- ════════════════════════════════════════════════════════════════════════
  rev_a := gen_random_uuid();
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name)
  VALUES (rev_a, tr_a, cl_1, 5.0, TRUE, 'Test Client 1');

  SELECT bmp_score INTO bmp_after FROM public.trainers WHERE id = tr_a;

  INSERT INTO _bmp_trigger_results VALUES (
    1, 'T1: INSERT already verified',
    'BMP > 0',
    'BMP = ' || ROUND(bmp_after::NUMERIC, 2),
    CASE WHEN bmp_after > 0 THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- T2  Verified → unverified (un-approval)  →  BMP drops to 0
  -- ════════════════════════════════════════════════════════════════════════
  SELECT bmp_score INTO bmp_before FROM public.trainers WHERE id = tr_a;

  UPDATE public.reviews SET is_verified = FALSE WHERE id = rev_a;

  SELECT bmp_score INTO bmp_after FROM public.trainers WHERE id = tr_a;

  INSERT INTO _bmp_trigger_results VALUES (
    2, 'T2: Verified → unverified (un-approval)',
    'BMP = 0',
    'BMP ' || ROUND(bmp_before::NUMERIC, 2) || ' → ' || ROUND(bmp_after::NUMERIC, 2),
    CASE WHEN bmp_after = 0 THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- T3  Unverified → verified (re-approval)  →  BMP rises again
  -- ════════════════════════════════════════════════════════════════════════
  UPDATE public.reviews SET is_verified = TRUE WHERE id = rev_a;

  SELECT bmp_score INTO bmp_after FROM public.trainers WHERE id = tr_a;

  INSERT INTO _bmp_trigger_results VALUES (
    3, 'T3: Unverified → verified (re-approval)',
    'BMP > 0',
    'BMP = ' || ROUND(bmp_after::NUMERIC, 2),
    CASE WHEN bmp_after > 0 THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- T4  DELETE verified review  →  BMP drops to 0
  -- ════════════════════════════════════════════════════════════════════════
  SELECT bmp_score INTO bmp_before FROM public.trainers WHERE id = tr_a;

  DELETE FROM public.reviews WHERE id = rev_a;

  SELECT bmp_score INTO bmp_after FROM public.trainers WHERE id = tr_a;

  INSERT INTO _bmp_trigger_results VALUES (
    4, 'T4: DELETE verified review',
    'BMP = 0',
    'BMP ' || ROUND(bmp_before::NUMERIC, 2) || ' → ' || ROUND(bmp_after::NUMERIC, 2),
    CASE WHEN bmp_after = 0 THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- T5  Rating change on verified review  →  BMP increases (1★ → 5★)
  -- ════════════════════════════════════════════════════════════════════════
  rev_a := gen_random_uuid();
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name)
  VALUES (rev_a, tr_a, cl_1, 1.0, TRUE, 'Test Client 1');

  SELECT bmp_score INTO bmp_before FROM public.trainers WHERE id = tr_a;

  UPDATE public.reviews SET rating = 5.0 WHERE id = rev_a;

  SELECT bmp_score INTO bmp_after FROM public.trainers WHERE id = tr_a;

  INSERT INTO _bmp_trigger_results VALUES (
    5, 'T5: Rating change on verified review (1★ → 5★)',
    'BMP rises',
    'BMP ' || ROUND(bmp_before::NUMERIC, 2) || ' → ' || ROUND(bmp_after::NUMERIC, 2),
    CASE WHEN bmp_after > bmp_before THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- T6  trainer_id change — review moved between trainers
  --     Both old and new trainer must be recalculated.
  -- ════════════════════════════════════════════════════════════════════════
  SELECT bmp_score INTO bmp_tr_a FROM public.trainers WHERE id = tr_a;  -- > 0
  SELECT bmp_score INTO bmp_tr_b FROM public.trainers WHERE id = tr_b;  -- 0

  UPDATE public.reviews SET trainer_id = tr_b WHERE id = rev_a;

  SELECT bmp_score INTO bmp_tr_a FROM public.trainers WHERE id = tr_a;
  SELECT bmp_score INTO bmp_tr_b FROM public.trainers WHERE id = tr_b;

  INSERT INTO _bmp_trigger_results VALUES (
    6, 'T6: trainer_id change (review moved A → B)',
    'Trainer A BMP = 0, Trainer B BMP > 0',
    'A = ' || ROUND(bmp_tr_a::NUMERIC, 2) || ', B = ' || ROUND(bmp_tr_b::NUMERIC, 2),
    CASE WHEN bmp_tr_a = 0 AND bmp_tr_b > 0 THEN 'PASS' ELSE 'FAIL' END
  );

  -- Move review back to trainer A for remaining tests
  UPDATE public.reviews SET trainer_id = tr_a WHERE id = rev_a;


  -- ════════════════════════════════════════════════════════════════════════
  -- T7  client_id change (dedup identity / distinct_reviewer_count)
  --     Two reviews from same client → drc = 1 (DISTINCT ON dedup).
  --     Change one to a new client → drc rises to 2 and BMP rises.
  -- ════════════════════════════════════════════════════════════════════════
  -- rev_a is on trainer A: 5★, verified, cl_1 (from T5)
  rev_b := gen_random_uuid();
  INSERT INTO public.reviews
    (id, trainer_id, client_id, rating, is_verified, reviewer_name, created_at)
  VALUES
    (rev_b, tr_a, cl_1, 5.0, TRUE, 'Test Client 1 (older)', NOW() - INTERVAL '1 hour');

  SELECT bmp_score, COALESCE(distinct_reviewer_count, 0)
  INTO   bmp_before, drc_before
  FROM   public.trainers WHERE id = tr_a;
  -- drc_before expected = 1: two reviews but same client, DISTINCT ON dedup

  UPDATE public.reviews SET client_id = cl_2 WHERE id = rev_b;

  SELECT bmp_score, COALESCE(distinct_reviewer_count, 0)
  INTO   bmp_after, drc_after
  FROM   public.trainers WHERE id = tr_a;

  INSERT INTO _bmp_trigger_results VALUES (
    7, 'T7: client_id change (dedup identity, drc)',
    'BMP rises AND drc = 2',
    'BMP ' || ROUND(bmp_before::NUMERIC, 2) || '→' || ROUND(bmp_after::NUMERIC, 2) ||
    ', drc ' || drc_before || '→' || drc_after,
    CASE WHEN bmp_after > bmp_before AND drc_after = 2 THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- T8  Irrelevant field change (review_text)  →  BMP unchanged
  -- ════════════════════════════════════════════════════════════════════════
  SELECT bmp_score INTO bmp_before FROM public.trainers WHERE id = tr_a;

  UPDATE public.reviews
  SET review_text = 'Updated text — scoring-irrelevant change'
  WHERE trainer_id = tr_a;

  SELECT bmp_score INTO bmp_after FROM public.trainers WHERE id = tr_a;

  INSERT INTO _bmp_trigger_results VALUES (
    8, 'T8: review_text change (irrelevant field)',
    'BMP unchanged',
    'BMP before = ' || ROUND(bmp_before::NUMERIC, 2) ||
    ', after = '    || ROUND(bmp_after::NUMERIC, 2),
    CASE WHEN bmp_after = bmp_before THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- T9  created_at change  →  trending state updates correctly
  --     Setup:  2 reviews in 7d window + 1 in 7-28d window → IS TRENDING
  --     Action: push one 7d review to 8d ago → only 1 in 7d → NOT TRENDING
  -- ════════════════════════════════════════════════════════════════════════
  DELETE FROM public.reviews WHERE trainer_id = tr_a;
  UPDATE public.trainers
  SET bmp_score = 0, is_trending = FALSE,
      distinct_reviewer_count = 0, review_count = 0,
      star_rating = 0, recent_review_count = 0
  WHERE id = tr_a;

  rev_a := gen_random_uuid();
  rev_b := gen_random_uuid();
  rev_c := gen_random_uuid();

  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, created_at)
  VALUES
    (rev_a, tr_a, cl_1, 5.0, TRUE, 'Test Client 1', NOW() - INTERVAL  '1 day'),
    (rev_b, tr_a, cl_2, 5.0, TRUE, 'Test Client 2', NOW() - INTERVAL  '2 days'),
    (rev_c, tr_a, cl_3, 5.0, TRUE, 'Test Client 3', NOW() - INTERVAL '14 days');

  SELECT is_trending INTO trend_before FROM public.trainers WHERE id = tr_a;

  -- Push cl_2 review past 7-day boundary → only 1 in 7d → cond A fails
  UPDATE public.reviews SET created_at = NOW() - INTERVAL '8 days' WHERE id = rev_b;

  SELECT is_trending INTO trend_after FROM public.trainers WHERE id = tr_a;

  INSERT INTO _bmp_trigger_results VALUES (
    9, 'T9: created_at change (trending recency window)',
    'is_trending: TRUE → FALSE',
    'is_trending: ' || trend_before::TEXT || ' → ' || trend_after::TEXT,
    CASE WHEN trend_before = TRUE AND trend_after = FALSE THEN 'PASS' ELSE 'FAIL' END
  );

END;
$tests$;


-- ── Step 3: Show results in the Results panel ─────────────────────────────────

SELECT
  num         AS "#",
  test_name   AS "Test",
  expected    AS "Expected",
  actual      AS "Actual",
  status      AS "Result"
FROM _bmp_trigger_results
ORDER BY num;


-- ── Step 4: Raise an exception if any test failed ────────────────────────────
-- Transaction is automatically rolled back by PostgreSQL on exception.

DO $$
DECLARE failed_tests TEXT;
BEGIN
  SELECT STRING_AGG(num || ': ' || test_name, ', ' ORDER BY num)
  INTO   failed_tests
  FROM   _bmp_trigger_results
  WHERE  status = 'FAIL';

  IF failed_tests IS NOT NULL THEN
    RAISE EXCEPTION 'BMP trigger tests FAILED — %', failed_tests;
  END IF;
END;
$$;


-- ── Step 5: Roll back all test data ──────────────────────────────────────────
ROLLBACK;


-- ── Step 6: Tidy up ──────────────────────────────────────────────────────────
DROP TABLE IF EXISTS _bmp_trigger_results;

SELECT 'All 9 BMP trigger tests PASSED. CoachCards-Test database unchanged.' AS summary;
