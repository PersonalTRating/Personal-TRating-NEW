-- ══════════════════════════════════════════════════════════════════════════════
-- CoachCards — Production Trigger Compatibility Tests
-- File: supabase_compat_trigger_tests.sql
--
-- Tests the full production five-trigger stack against BMP v3.
-- Verifies that legacy functions no longer corrupt bmp_score and that all
-- trainer statistics remain correct across every review lifecycle event.
--
-- HOW RESULTS SURFACE
--   • 10 rows appear in the Supabase SQL Editor RESULTS panel.
--   • Any FAIL raises an EXCEPTION so the script cannot silently succeed.
--   • All synthetic changes roll back; nothing persists in the database.
--   • All five review triggers remain enabled throughout.
--
-- RUN ORDER (CoachCards-Test only):
--   1. supabase_test_environment_setup.sql
--   2. supabase_production_compat_patch.sql   ← installs legacy triggers
--   3. supabase_bmp_v3_migration.sql          ← Step 8 corrects legacy functions
--   4. THIS FILE
--
-- PREREQUISITES (verified by PRE-flight checks below):
--   • Synthetic trainers 00000000-0000-0000-face-000000000001 (tr_a)
--                         00000000-0000-0000-face-000000000002 (tr_b)
--   • Function calculate_bmp_for_trainer() present (v3)
--   • Function update_trainer_stats() present (corrected — no bmp_score write)
--   • Function update_trainer_star_rating() present (corrected — no bmp_score write)
--   • Trigger zzz_on_review_bmp_update present (comprehensive v3 trigger)
-- ══════════════════════════════════════════════════════════════════════════════


-- ── Step 0: Results table (outside transaction — structure survives ROLLBACK) ─
DROP TABLE IF EXISTS _compat_results;
CREATE TEMP TABLE _compat_results (
  num       INTEGER,
  test_name TEXT,
  expected  TEXT,
  actual    TEXT,
  status    TEXT   -- 'PASS' | 'FAIL'
);


-- ── Step 1: Pre-flight checks ─────────────────────────────────────────────────

SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE  event_object_schema = 'public'
      AND  event_object_table  = 'reviews'
      AND  trigger_name        = 'zzz_on_review_bmp_update'
  ) THEN 'PASS PRE-1: zzz_on_review_bmp_update present'
    ELSE 'FAIL PRE-1: run supabase_bmp_v3_migration.sql first'
  END AS preflight_bmp_trigger;

SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE  event_object_schema = 'public'
      AND  event_object_table  = 'reviews'
      AND  trigger_name        = 'on_review_created'
  ) THEN 'PASS PRE-2: on_review_created present'
    ELSE 'FAIL PRE-2: run supabase_production_compat_patch.sql first'
  END AS preflight_legacy_trigger;

SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc
    WHERE  pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
      AND  proname      = 'update_trainer_stats'
      AND  prosrc NOT LIKE '%bmp_score%'    -- confirms Step 8 correction applied
  ) THEN 'PASS PRE-3: update_trainer_stats() corrected (no bmp_score write)'
    ELSE 'FAIL PRE-3: run supabase_bmp_v3_migration.sql Step 8 first'
  END AS preflight_stats_fn;

SELECT
  CASE WHEN EXISTS (
    SELECT 1 FROM pg_proc
    WHERE  pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
      AND  proname      = 'update_trainer_star_rating'
      AND  prosrc NOT LIKE '%bmp_score%'    -- confirms Step 8 correction applied
  ) THEN 'PASS PRE-4: update_trainer_star_rating() corrected (no bmp_score write)'
    ELSE 'FAIL PRE-4: run supabase_bmp_v3_migration.sql Step 8 first'
  END AS preflight_star_rating_fn;

SELECT
  CASE WHEN COUNT(*) = 2
    THEN 'PASS PRE-5: both synthetic trainers present'
    ELSE 'FAIL PRE-5: run supabase_test_environment_setup.sql first'
  END AS preflight_trainers
FROM public.trainers
WHERE id IN (
  '00000000-0000-0000-face-000000000001',
  '00000000-0000-0000-face-000000000002'
);


-- ── Step 2: Main test transaction ─────────────────────────────────────────────

BEGIN;

DO $tests$
DECLARE
  tr_a UUID := '00000000-0000-0000-face-000000000001';
  tr_b UUID := '00000000-0000-0000-face-000000000002';
  cl_1 UUID := '00000000-0000-0000-bead-000000000001';
  cl_2 UUID := '00000000-0000-0000-bead-000000000002';
  cl_3 UUID := '00000000-0000-0000-bead-000000000003';

  rev_a UUID; rev_b UUID; rev_c UUID;

  bmp_before      DOUBLE PRECISION := 0;
  bmp_after       DOUBLE PRECISION := 0;
  bmp_tr_a        DOUBLE PRECISION := 0;
  bmp_tr_b        DOUBLE PRECISION := 0;
  star_before     DOUBLE PRECISION := 0;
  star_after      DOUBLE PRECISION := 0;
  count_before    INTEGER := 0;
  count_after     INTEGER := 0;
  drc_before      INTEGER := 0;
  drc_after       INTEGER := 0;
  trend_before    BOOLEAN;
  trend_after     BOOLEAN;
  notif_before    INTEGER := 0;
  notif_after     INTEGER := 0;

BEGIN

  -- ── Seed clients ─────────────────────────────────────────────────────────
  INSERT INTO public.clients (id, user_id) VALUES
    (cl_1, '00000000-0000-0000-bead-a00000000001'),
    (cl_2, '00000000-0000-0000-bead-a00000000002'),
    (cl_3, '00000000-0000-0000-bead-a00000000003')
  ON CONFLICT (id) DO NOTHING;

  -- Reset both trainers to known-zero state
  UPDATE public.trainers
  SET bmp_score = 0, is_trending = FALSE, distinct_reviewer_count = 0,
      review_count = 0, star_rating = 0, recent_review_count = 0
  WHERE id IN (tr_a, tr_b);

  DELETE FROM public.reviews WHERE trainer_id IN (tr_a, tr_b);


  -- ════════════════════════════════════════════════════════════════════════
  -- CT-1  Pending review INSERT — BMP, star_rating, review_count must not change
  --
  --   Setup: give tr_a one approved review so BMP > 0 going in.
  --   Then insert a pending review and confirm nothing moves.
  -- ════════════════════════════════════════════════════════════════════════
  rev_a := gen_random_uuid();
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name)
  VALUES (rev_a, tr_a, cl_1, 4.5, TRUE, 'Baseline Client');

  SELECT bmp_score, star_rating, review_count
  INTO   bmp_before, star_before, count_before
  FROM   public.trainers WHERE id = tr_a;

  -- Insert a pending review — no trigger should touch BMP or stats
  rev_b := gen_random_uuid();
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name)
  VALUES (rev_b, tr_a, cl_2, 1.0, FALSE, 'Pending Client');

  SELECT bmp_score, star_rating, review_count
  INTO   bmp_after, star_after, count_after
  FROM   public.trainers WHERE id = tr_a;

  INSERT INTO _compat_results VALUES (
    1, 'CT-1: Pending review INSERT — no stat change',
    'BMP, star_rating, review_count all unchanged',
    'BMP '  || ROUND(bmp_before::NUMERIC,2)  || '→' || ROUND(bmp_after::NUMERIC,2)  ||
    ', star ' || ROUND(star_before::NUMERIC,2) || '→' || ROUND(star_after::NUMERIC,2) ||
    ', cnt '  || count_before || '→' || count_after,
    CASE WHEN bmp_after = bmp_before
          AND star_after = star_before
          AND count_after = count_before
      THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- CT-2  Pending review edited — BMP, star_rating, review_count must not change
  --       (pending rev_b still exists from CT-1)
  -- ════════════════════════════════════════════════════════════════════════
  SELECT bmp_score, star_rating, review_count
  INTO   bmp_before, star_before, count_before
  FROM   public.trainers WHERE id = tr_a;

  -- Edit rating and text on the pending review
  UPDATE public.reviews
  SET rating = 5.0, review_text = 'Edited pending text'
  WHERE id = rev_b;

  SELECT bmp_score, star_rating, review_count
  INTO   bmp_after, star_after, count_after
  FROM   public.trainers WHERE id = tr_a;

  INSERT INTO _compat_results VALUES (
    2, 'CT-2: Pending review edited — no stat change',
    'BMP, star_rating, review_count all unchanged',
    'BMP '  || ROUND(bmp_before::NUMERIC,2)  || '→' || ROUND(bmp_after::NUMERIC,2)  ||
    ', star ' || ROUND(star_before::NUMERIC,2) || '→' || ROUND(star_after::NUMERIC,2) ||
    ', cnt '  || count_before || '→' || count_after,
    CASE WHEN bmp_after = bmp_before
          AND star_after = star_before
          AND count_after = count_before
      THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- CT-3  Review approved — Model C BMP calculated correctly
  --       Approve rev_b (pending 5★ from cl_2). tr_a now has:
  --         cl_1: 4.5★ (approved since CT-1)
  --         cl_2: 5.0★ (just approved, previously pending)
  --
  --   Expected: BMP > baseline (more reviews, higher avg), star_rating = 4.75
  -- ════════════════════════════════════════════════════════════════════════
  SELECT bmp_score INTO bmp_before FROM public.trainers WHERE id = tr_a;

  UPDATE public.reviews SET is_verified = TRUE WHERE id = rev_b;

  SELECT bmp_score, star_rating, review_count
  INTO   bmp_after, star_after, count_after
  FROM   public.trainers WHERE id = tr_a;

  INSERT INTO _compat_results VALUES (
    3, 'CT-3: Review approved — Model C BMP recalculated',
    'BMP rises, star_rating = 4.75, review_count = 2',
    'BMP ' || ROUND(bmp_before::NUMERIC,2) || '→' || ROUND(bmp_after::NUMERIC,2) ||
    ', star = ' || ROUND(star_after::NUMERIC,2) ||
    ', cnt = '  || count_after,
    CASE WHEN bmp_after > bmp_before
          AND ROUND(star_after::NUMERIC,2) = 4.75
          AND count_after = 2
      THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- CT-4  Approved review rating changed — BMP and star_rating update
  --       Change cl_2's review from 5★ → 2★. BMP should drop; star_rating drops.
  -- ════════════════════════════════════════════════════════════════════════
  SELECT bmp_score, star_rating INTO bmp_before, star_before
  FROM   public.trainers WHERE id = tr_a;

  UPDATE public.reviews SET rating = 2.0 WHERE id = rev_b;

  SELECT bmp_score, star_rating INTO bmp_after, star_after
  FROM   public.trainers WHERE id = tr_a;

  INSERT INTO _compat_results VALUES (
    4, 'CT-4: Approved review rating changed (5★→2★)',
    'BMP drops, star_rating drops',
    'BMP '  || ROUND(bmp_before::NUMERIC,2) || '→' || ROUND(bmp_after::NUMERIC,2) ||
    ', star ' || ROUND(star_before::NUMERIC,2) || '→' || ROUND(star_after::NUMERIC,2),
    CASE WHEN bmp_after < bmp_before AND star_after < star_before
      THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- CT-5  Approved review deleted — BMP, star_rating, review_count all update
  --       Delete rev_b (cl_2's 2★ review). Only cl_1's 4.5★ remains.
  -- ════════════════════════════════════════════════════════════════════════
  SELECT bmp_score, star_rating, review_count
  INTO   bmp_before, star_before, count_before
  FROM   public.trainers WHERE id = tr_a;

  DELETE FROM public.reviews WHERE id = rev_b;

  SELECT bmp_score, star_rating, review_count
  INTO   bmp_after, star_after, count_after
  FROM   public.trainers WHERE id = tr_a;

  -- After deletion: star_rating should be 4.5 (only cl_1), review_count = 1
  INSERT INTO _compat_results VALUES (
    5, 'CT-5: Approved review deleted — all stats update',
    'BMP changes, star_rating = 4.50, review_count = 1',
    'BMP '  || ROUND(bmp_before::NUMERIC,2) || '→' || ROUND(bmp_after::NUMERIC,2) ||
    ', star = ' || ROUND(star_after::NUMERIC,2) ||
    ', cnt = '  || count_after,
    CASE WHEN bmp_after <> bmp_before
          AND ROUND(star_after::NUMERIC,2) = 4.50
          AND count_after = 1
      THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- CT-6  Approved review unverified — all relevant statistics updated
  --       Set cl_1's approved review back to is_verified = FALSE.
  --       BMP should drop to 0, star_rating = 0, review_count = 0.
  -- ════════════════════════════════════════════════════════════════════════
  SELECT bmp_score, star_rating, review_count
  INTO   bmp_before, star_before, count_before
  FROM   public.trainers WHERE id = tr_a;

  UPDATE public.reviews SET is_verified = FALSE WHERE id = rev_a;

  SELECT bmp_score, star_rating, review_count
  INTO   bmp_after, star_after, count_after
  FROM   public.trainers WHERE id = tr_a;

  INSERT INTO _compat_results VALUES (
    6, 'CT-6: Approved review unverified — stats drop to 0',
    'BMP = 0, star_rating = 0, review_count = 0',
    'BMP = '  || ROUND(bmp_after::NUMERIC,2) ||
    ', star = ' || ROUND(star_after::NUMERIC,2) ||
    ', cnt = '  || count_after,
    CASE WHEN bmp_after = 0 AND star_after = 0 AND count_after = 0
      THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- CT-7  Multiple reviews — no legacy BMP overwrites
  --       Insert 3 verified + 1 pending review. BMP must match the
  --       v3 formula output (not the legacy formula).
  --       Verification: legacy formula (avg/5*70 + min(n*3,30)) would give a
  --       different value from the v3 Bayesian prior formula. We confirm
  --       bmp_score IS NOT the legacy result.
  -- ════════════════════════════════════════════════════════════════════════
  DELETE FROM public.reviews WHERE trainer_id = tr_a;
  UPDATE public.trainers
  SET bmp_score = 0, is_trending = FALSE, distinct_reviewer_count = 0,
      review_count = 0, star_rating = 0, recent_review_count = 0
  WHERE id = tr_a;

  rev_a := gen_random_uuid();
  rev_b := gen_random_uuid();
  rev_c := gen_random_uuid();

  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name)
  VALUES
    (rev_a, tr_a, cl_1, 5.0, TRUE,  'Client 1 verified'),
    (rev_b, tr_a, cl_2, 4.0, TRUE,  'Client 2 verified'),
    (rev_c, tr_a, cl_3, 3.0, TRUE,  'Client 3 verified');

  -- Insert a pending review (should not affect BMP)
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name)
  VALUES (gen_random_uuid(), tr_a, cl_3, 1.0, FALSE, 'Pending bad review');

  SELECT bmp_score INTO bmp_after FROM public.trainers WHERE id = tr_a;

  -- Legacy formula with 4 reviews (3 verified + 1 pending, no filter):
  --   avg = (5+4+3+1)/4 = 3.25, count = 4
  --   LEAST(100, ROUND(3.25/5*70 + LEAST(4*3,30))) = ROUND(45.5 + 12) = 58
  -- Legacy formula with 3 verified only:
  --   avg = (5+4+3)/3 = 4.0, count = 3
  --   ROUND(4.0/5*70 + LEAST(3*3,30)) = ROUND(56 + 9) = 65
  -- v3 formula with 3 verified (8@4★ prior):
  --   eff_count=3, sum=12, smoothed=(12+32)/(3+8)=4.0
  --   quality=4/5*70=56, confidence=LN(4)/LN(51)*20≈7.0, activity=varies
  --   Result is NOT 58 and NOT 65 in the same way
  --
  -- Simple check: bmp_score must NOT equal 58 (the pending-inclusive legacy result).
  -- Also star_rating must be 4.0 (3 verified only), review_count = 3.
  SELECT star_rating, review_count
  INTO   star_after, count_after
  FROM   public.trainers WHERE id = tr_a;

  INSERT INTO _compat_results VALUES (
    7, 'CT-7: Multiple reviews — no legacy BMP overwrite',
    'BMP ≠ 58 (no pending inflation), star_rating = 4.00, review_count = 3',
    'BMP = '   || ROUND(bmp_after::NUMERIC,2) ||
    ', star = ' || ROUND(star_after::NUMERIC,2) ||
    ', cnt = '  || count_after,
    CASE WHEN ROUND(bmp_after::NUMERIC,0) <> 58
          AND ROUND(star_after::NUMERIC,2) = 4.00
          AND count_after = 3
      THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- CT-8  Trainer reassignment — both affected trainers fully recalculated
  --       Move rev_a (cl_1, 5★ verified) from tr_a to tr_b.
  --       tr_a: loses one review (2 remain, avg 3.5★)
  --       tr_b: gains one review (avg 5.0★)
  --       star_rating and review_count must be correct on both.
  -- ════════════════════════════════════════════════════════════════════════
  -- Clean tr_b
  DELETE FROM public.reviews WHERE trainer_id = tr_b;
  UPDATE public.trainers
  SET bmp_score = 0, distinct_reviewer_count = 0,
      review_count = 0, star_rating = 0, recent_review_count = 0
  WHERE id = tr_b;

  UPDATE public.reviews SET trainer_id = tr_b WHERE id = rev_a;

  SELECT bmp_score, star_rating, review_count
  INTO   bmp_tr_a, star_before, count_before
  FROM   public.trainers WHERE id = tr_a;

  SELECT bmp_score, star_rating, review_count
  INTO   bmp_tr_b, star_after, count_after
  FROM   public.trainers WHERE id = tr_b;

  INSERT INTO _compat_results VALUES (
    8, 'CT-8: Trainer reassignment — both trainers updated',
    'tr_A: star=3.50 cnt=2 BMP>0; tr_B: star=5.00 cnt=1 BMP>0',
    'A: star=' || ROUND(star_before::NUMERIC,2) || ' cnt=' || count_before || ' bmp=' || ROUND(bmp_tr_a::NUMERIC,2) ||
    ' | B: star=' || ROUND(star_after::NUMERIC,2) || ' cnt=' || count_after || ' bmp=' || ROUND(bmp_tr_b::NUMERIC,2),
    CASE WHEN ROUND(star_before::NUMERIC,2) = 3.50 AND count_before = 2 AND bmp_tr_a > 0
          AND ROUND(star_after::NUMERIC,2)  = 5.00 AND count_after  = 1 AND bmp_tr_b > 0
      THEN 'PASS' ELSE 'FAIL' END
  );

  -- Restore: move rev_a back to tr_a for CT-9
  UPDATE public.reviews SET trainer_id = tr_a WHERE id = rev_a;
  DELETE FROM public.reviews WHERE trainer_id = tr_b;
  UPDATE public.trainers
  SET bmp_score = 0, distinct_reviewer_count = 0,
      review_count = 0, star_rating = 0, recent_review_count = 0
  WHERE id = tr_b;


  -- ════════════════════════════════════════════════════════════════════════
  -- CT-9  Fresh Face and Trending remain accurate
  --       Fresh setup with 3 reviews, distinct clients, explicit timestamps:
  --         cl_1: 5★, 20 days ago → condition B (1 qualifying review in 7–28d window)
  --         cl_2: 4★,  3 days ago → condition A candidate (≥3.5★, within 7d)
  --         cl_3: 5★,  2 days ago → condition A candidate (≥3.5★, within 7d)
  --       Condition A: cl_2 + cl_3 = 2 qualifying ≥3.5★ reviews in 7d → TRUE
  --       Condition B: cl_1 = 1 qualifying review in 7–28d → TRUE
  --       Distinct reviewers: cl_1 + cl_2 + cl_3 → drc = 3 (≥2 = Fresh Face eligible)
  --
  --       WHY a fresh setup instead of reusing prior state:
  --         The original fixture inserted a second review for cl_2, which already
  --         had rev_b. The BMP function's DISTINCT ON (client_id) deduplication
  --         keeps only the LATEST review per client — cl_2 still counts as ONE
  --         effective qualifying reviewer, not two. Condition A therefore got
  --         1 qualifying reviewer (not the required ≥2), causing is_trending = FALSE.
  -- ════════════════════════════════════════════════════════════════════════

  -- Start fresh: discard all tr_a reviews accumulated in prior tests.
  DELETE FROM public.reviews WHERE trainer_id = tr_a;
  UPDATE public.trainers
  SET bmp_score = 0, is_trending = FALSE, distinct_reviewer_count = 0,
      review_count = 0, star_rating = 0, recent_review_count = 0
  WHERE id = tr_a;

  -- Insert exactly the reviews needed with explicit timestamps so the result
  -- is deterministic regardless of when the DO block runs.
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name, created_at)
  VALUES
    (gen_random_uuid(), tr_a, cl_1, 5.0, TRUE, 'CT-9 Client 1', NOW() - INTERVAL '20 days'),
    (gen_random_uuid(), tr_a, cl_2, 4.0, TRUE, 'CT-9 Client 2', NOW() - INTERVAL  '3 days'),
    (gen_random_uuid(), tr_a, cl_3, 5.0, TRUE, 'CT-9 Client 3', NOW() - INTERVAL  '2 days');
  -- Triggers fire on each INSERT: zzz_on_review_bmp_update → calculate_bmp_for_trainer()
  -- which evaluates trending conditions A and B and writes is_trending + distinct_reviewer_count.

  SELECT is_trending, COALESCE(distinct_reviewer_count, 0)
  INTO   trend_after, drc_after
  FROM   public.trainers WHERE id = tr_a;

  INSERT INTO _compat_results VALUES (
    9, 'CT-9: Fresh Face and Trending accurate',
    'is_trending = TRUE, distinct_reviewer_count ≥ 2',
    'is_trending = ' || trend_after::TEXT ||
    ', drc = '       || drc_after,
    CASE WHEN trend_after = TRUE AND drc_after >= 2
      THEN 'PASS' ELSE 'FAIL' END
  );


  -- ════════════════════════════════════════════════════════════════════════
  -- CT-10 Reviewer notifications continue working after migration
  --       Insert a pending review for cl_1 (has user_id → notification target).
  --       Approve it. Confirm the notifications table received a new row.
  -- ════════════════════════════════════════════════════════════════════════
  DELETE FROM public.reviews WHERE trainer_id = tr_b;
  UPDATE public.trainers
  SET bmp_score = 0, distinct_reviewer_count = 0,
      review_count = 0, star_rating = 0, recent_review_count = 0
  WHERE id = tr_b;

  SELECT COUNT(*) INTO notif_before
  FROM public.notifications
  WHERE user_id = '00000000-0000-0000-bead-a00000000001';

  -- Insert pending review for cl_1 on tr_b (fresh trainer for clean notification test)
  rev_a := gen_random_uuid();
  INSERT INTO public.reviews (id, trainer_id, client_id, rating, is_verified, reviewer_name)
  VALUES (rev_a, tr_b, cl_1, 5.0, FALSE, 'Notification Test Client');

  -- Approve it — on_review_approved_notify_client should fire and insert a notification
  UPDATE public.reviews SET is_verified = TRUE WHERE id = rev_a;

  SELECT COUNT(*) INTO notif_after
  FROM public.notifications
  WHERE user_id = '00000000-0000-0000-bead-a00000000001';

  INSERT INTO _compat_results VALUES (
    10, 'CT-10: Reviewer notification sent on approval',
    'notification count increases by 1',
    'notifications: ' || notif_before || '→' || notif_after,
    CASE WHEN notif_after = notif_before + 1
      THEN 'PASS' ELSE 'FAIL' END
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
FROM _compat_results
ORDER BY num;


-- ── Step 4: Raise exception if any test failed ────────────────────────────────

DO $$
DECLARE failed_tests TEXT;
BEGIN
  SELECT STRING_AGG(num || ': ' || test_name, ', ' ORDER BY num)
  INTO   failed_tests
  FROM   _compat_results
  WHERE  status = 'FAIL';

  IF failed_tests IS NOT NULL THEN
    RAISE EXCEPTION 'Compatibility tests FAILED — %', failed_tests;
  END IF;
END;
$$;


-- ── Step 5: Roll back all test data ───────────────────────────────────────────
ROLLBACK;


-- ── Step 6: Tidy up ───────────────────────────────────────────────────────────
DROP TABLE IF EXISTS _compat_results;

SELECT 'All 10 BMP trigger compatibility tests PASSED. CoachCards-Test database unchanged.' AS summary;
