-- ──────────────────────────────────────────────────────────────────────────────
-- MIGRATION: Trending Auto-Update
-- Permanent automatic expiry for the is_trending flag.
--
-- What this migration does:
--   1. Creates refresh_trending_status(UUID) — lightweight function that updates
--      is_trending and recent_review_count only (no bmp_score recalculation).
--   2. Creates refresh_all_trending() — batch wrapper called by scheduled jobs.
--   3. Adds trigger zzz_on_review_bmp_update — fires on every admin-dashboard
--      approval (is_verified FALSE→TRUE), calling calculate_bmp_for_trainer.
--      The existing on_review_approved trigger is PRESERVED unchanged.
--   4. Immediate backfill — corrects any currently-stale is_trending values.
--
-- Prerequisites:
--   • calculate_bmp_for_trainer(UUID) must already be deployed
--     (supabase_trending_v3.sql).
--   • For Step 5 (pg_cron): enable the extension in Supabase Dashboard →
--     Database → Extensions, THEN run the cron.schedule statement below.
--
-- DO NOT EXECUTE until approved by the product owner.
-- ──────────────────────────────────────────────────────────────────────────────


-- ── 1. Lightweight trending-only refresh ─────────────────────────────────────
-- Recalculates is_trending and recent_review_count using the same two-window
-- formula as calculate_bmp_for_trainer, but does NOT touch bmp_score,
-- star_rating, or review_count.  Safe to run frequently on every active trainer.

CREATE OR REPLACE FUNCTION refresh_trending_status(p_trainer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviews_7d   INTEGER;
  v_reviews_prev INTEGER;
  v_is_trending  BOOLEAN;
BEGIN
  -- Condition A: ≥2 verified reviews in the last 7 days
  SELECT COUNT(*) INTO v_reviews_7d
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '7 days';

  -- Condition B: ≥1 verified review in the 7–28 day window (non-overlapping)
  SELECT COUNT(*) INTO v_reviews_prev
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '28 days'
    AND created_at <  NOW() - INTERVAL '7 days';

  v_is_trending := (v_reviews_7d >= 2 AND v_reviews_prev >= 1);

  UPDATE trainers
  SET
    is_trending         = v_is_trending,
    recent_review_count = v_reviews_7d
  WHERE id = p_trainer_id;
END;
$$;

GRANT EXECUTE ON FUNCTION refresh_trending_status(UUID) TO service_role;


-- ── 2. Batch wrapper for scheduled use ───────────────────────────────────────
-- Iterates all active trainers and returns the count refreshed.
-- Called by the Netlify scheduled function and optionally by pg_cron.

CREATE OR REPLACE FUNCTION refresh_all_trending()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r     RECORD;
  total INTEGER := 0;
BEGIN
  FOR r IN SELECT id FROM trainers WHERE is_active = TRUE LOOP
    PERFORM refresh_trending_status(r.id);
    total := total + 1;
  END LOOP;
  RETURN total;
END;
$$;

GRANT EXECUTE ON FUNCTION refresh_all_trending() TO service_role;


-- ── 3. Fix admin approval path: add BMP trigger ───────────────────────────────
-- Background: admin.astro approves via direct .update({ is_verified: true }).
-- This fires the existing on_review_approved trigger → update_trainer_stats()
-- which correctly updates star_rating and review_count, but does NOT call
-- calculate_bmp_for_trainer, leaving is_trending stale after admin approvals.
--
-- Fix: add a SECOND trigger that fires on the same event and calls
-- calculate_bmp_for_trainer.  The existing trigger is PRESERVED unchanged.
-- The 'zzz_' prefix ensures this fires AFTER on_review_approved (Postgres
-- fires same-event triggers in alphabetical order by name).
--
-- SECURITY DEFINER is required because calculate_bmp_for_trainer is granted
-- to service_role only.  Without it the trigger would fail when fired by an
-- authenticated (admin) user.

CREATE OR REPLACE FUNCTION trigger_calculate_bmp_on_approve()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM calculate_bmp_for_trainer(NEW.trainer_id);
  RETURN NEW;
END;
$$;

-- WHEN clause on the trigger restricts execution to FALSE→TRUE transitions.
DROP TRIGGER IF EXISTS zzz_on_review_bmp_update ON reviews;

CREATE TRIGGER zzz_on_review_bmp_update
  AFTER UPDATE OF is_verified ON reviews
  FOR EACH ROW
  WHEN (NEW.is_verified = TRUE AND OLD.is_verified IS DISTINCT FROM TRUE)
  EXECUTE FUNCTION trigger_calculate_bmp_on_approve();


-- ── 4. Immediate backfill ─────────────────────────────────────────────────────
-- Clears any stale is_trending values set before auto-expiry existed.
-- Run this block once immediately after deploying the functions above.

DO $$
DECLARE
  r RECORD;
  n INTEGER := 0;
BEGIN
  FOR r IN SELECT id FROM trainers WHERE is_active = TRUE LOOP
    PERFORM refresh_trending_status(r.id);
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'Backfill complete: % trainers updated', n;
END;
$$;


-- ── 5. Optional: pg_cron belt-and-suspenders ─────────────────────────────────
-- The Netlify scheduled function (refresh-trending.js) is the primary mechanism
-- for daily auto-expiry and SSG rebuilds.  pg_cron provides an independent
-- DB-level safety net that runs even if the Netlify function is skipped.
--
-- Step A: Enable pg_cron in Supabase Dashboard → Database → Extensions.
-- Step B: Run this statement ONCE (after enabling the extension):
--
-- SELECT cron.schedule(
--   'refresh-trending-daily',
--   '0 0 * * *',
--   $$ SELECT refresh_all_trending(); $$
-- );
--
-- To verify the job was scheduled:
-- SELECT * FROM cron.job WHERE jobname = 'refresh-trending-daily';
--
-- To remove it if needed:
-- SELECT cron.unschedule('refresh-trending-daily');
