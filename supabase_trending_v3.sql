-- ──────────────────────────────────────────────────────────────────────────────
-- MIGRATION: Trending Qualification v3
-- Replaces the 30-day trending criteria with a rolling two-window system.
--
-- New criteria (both conditions must be met):
--   Condition A: ≥2 verified reviews within the last 7 days (rolling)
--   Condition B: ≥1 verified review between 7 and 28 days ago (non-overlapping)
--
-- Changes from v2:
--   1. Trending: was (total≥5 AND 30d≥4 AND weeks≥2 AND quality≥42)
--                 now (7d≥2 AND prev_7_28d≥1) — no quality floor or count minimum
--   2. recent_review_count: now stores the 7-day count (was 30-day count)
--      Display text on cards changes from "N reviews in the last 30 days"
--      to "N verified reviews in the last 7 days".
--
-- After running: execute the backfill block below to update all active trainers.
-- BMP calculations (Quality / Confidence / Momentum) are UNCHANGED.
-- ──────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION calculate_bmp_for_trainer(p_trainer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_count    INTEGER;  -- total verified reviews
  v_eff_count      INTEGER;  -- effective unique-contributor count (for BMP quality/confidence)
  v_sum_ratings    FLOAT;
  v_smoothed_avg   FLOAT;
  v_quality_pts    FLOAT;
  v_confidence_pts FLOAT;
  v_momentum_pts   FLOAT;
  v_bmp_score      FLOAT;
  v_period_7d      INTEGER;
  v_period_8_30d   INTEGER;
  v_period_31_90d  INTEGER;
  v_raw_momentum   FLOAT;
  v_reviews_7d     INTEGER;  -- condition A: verified reviews in last 7 days
  v_reviews_prev   INTEGER;  -- condition B: verified reviews between 7 and 28 days ago
  v_is_trending    BOOLEAN;
BEGIN

  -- ── Total verified review count ───────────────────────────────────────────
  SELECT COUNT(*) INTO v_total_count
  FROM reviews
  WHERE trainer_id = p_trainer_id AND is_verified = TRUE;

  IF v_total_count = 0 THEN
    UPDATE trainers
    SET bmp_score = 0, is_trending = FALSE, recent_review_count = 0
    WHERE id = p_trainer_id;
    RETURN;
  END IF;

  -- ── Effective review count + sum (latest per client, plus anonymous) ──────
  -- DISTINCT ON (client_id) ordered by created_at DESC picks the most recent
  -- verified review for each authenticated client.  Anonymous reviews (client_id
  -- IS NULL) are included individually.
  WITH latest_per_client AS (
    SELECT DISTINCT ON (client_id)
      id, rating
    FROM reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NOT NULL
    ORDER BY client_id, created_at DESC
  ),
  anon_reviews AS (
    SELECT id, rating
    FROM reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NULL
  ),
  eff AS (
    SELECT id, rating FROM latest_per_client
    UNION ALL
    SELECT id, rating FROM anon_reviews
  )
  SELECT COUNT(*), COALESCE(SUM(rating), 0)
  INTO v_eff_count, v_sum_ratings
  FROM eff;

  -- ── Component 1: Quality (0-70 pts) ──────────────────────────────────────
  v_smoothed_avg := (v_sum_ratings + 5.0 * 3.5) / (v_eff_count::FLOAT + 5.0);
  v_quality_pts  := LEAST((v_smoothed_avg / 5.0) * 70.0, 70.0);

  -- ── Component 2: Confidence (0-20 pts) ───────────────────────────────────
  v_confidence_pts := LEAST(LN(v_eff_count::FLOAT + 1.0) / LN(51.0), 1.0) * 20.0;

  -- ── Component 3: Momentum (0-10 pts) — effective reviews only ────────────
  WITH latest_per_client AS (
    SELECT DISTINCT ON (client_id)
      id, rating, created_at
    FROM reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NOT NULL
    ORDER BY client_id, created_at DESC
  ),
  anon_reviews AS (
    SELECT id, rating, created_at
    FROM reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NULL
  ),
  eff AS (
    SELECT id, rating, created_at FROM latest_per_client
    UNION ALL
    SELECT id, rating, created_at FROM anon_reviews
  )
  SELECT
    LEAST(COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days'),  2)::INTEGER,
    LEAST(COUNT(*) FILTER (
      WHERE created_at >= NOW() - INTERVAL '30 days'
        AND created_at <  NOW() - INTERVAL '7 days'), 5)::INTEGER,
    LEAST(COUNT(*) FILTER (
      WHERE created_at >= NOW() - INTERVAL '90 days'
        AND created_at <  NOW() - INTERVAL '30 days'), 7)::INTEGER
  INTO v_period_7d, v_period_8_30d, v_period_31_90d
  FROM eff
  WHERE rating >= 3.5
    AND created_at >= NOW() - INTERVAL '90 days';

  v_raw_momentum := (v_period_7d * 3.0) + (v_period_8_30d * 1.5) + (v_period_31_90d * 0.75);
  v_momentum_pts := LEAST(v_raw_momentum / 7.5, 1.0) * 10.0;

  -- ── Final BMP ─────────────────────────────────────────────────────────────
  v_bmp_score := ROUND((v_quality_pts + v_confidence_pts + v_momentum_pts)::NUMERIC, 1);

  -- ── Trending: two-window rolling calculation ──────────────────────────────
  -- Counts ALL verified reviews (not deduplicated) — a new eligible repeat
  -- review is genuine new activity (spec §18-19).

  -- Condition A: recent burst — at least 2 verified reviews in the last 7 days
  SELECT COUNT(*) INTO v_reviews_7d
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '7 days';

  -- Condition B: consistency — at least 1 verified review in the preceding
  -- 21-day window (7–28 days ago, non-overlapping with condition A)
  SELECT COUNT(*) INTO v_reviews_prev
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '28 days'
    AND created_at <  NOW() - INTERVAL '7 days';

  -- ── Trending eligibility ──────────────────────────────────────────────────
  -- Both conditions are mandatory. No quality floor or total count minimum.
  v_is_trending := (v_reviews_7d >= 2 AND v_reviews_prev >= 1);

  -- ── Write ─────────────────────────────────────────────────────────────────
  -- recent_review_count stores the 7-day count for card display.
  UPDATE trainers
  SET
    bmp_score           = v_bmp_score,
    is_trending         = v_is_trending,
    recent_review_count = v_reviews_7d
  WHERE id = p_trainer_id;

END;
$$;

GRANT EXECUTE ON FUNCTION calculate_bmp_for_trainer(UUID) TO service_role;

-- ── Backfill all active trainers ──────────────────────────────────────────────
-- Recalculates BMP, is_trending, and recent_review_count (now 7-day) for every
-- active trainer under the new criteria.  Run this immediately after deploying
-- the function above.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM trainers WHERE is_active = TRUE LOOP
    PERFORM calculate_bmp_for_trainer(r.id);
  END LOOP;
END;
$$;


-- ── Optional: pg_cron daily recalculation for automatic trending expiry ───────
--
-- The is_trending column is recalculated whenever a review is approved or
-- removed.  Without a scheduled job, a trainer whose reviews age beyond the
-- 7-day window will keep is_trending = TRUE until the next review event fires.
--
-- To enable automatic expiry, turn on pg_cron in Supabase Dashboard →
-- Database → Extensions, then run the statement below once:
--
-- SELECT cron.schedule(
--   'recalculate-trending-daily',
--   '0 0 * * *',
--   $$
--   DO $job$
--   DECLARE r RECORD;
--   BEGIN
--     FOR r IN SELECT id FROM trainers WHERE is_active = TRUE LOOP
--       PERFORM calculate_bmp_for_trainer(r.id);
--     END LOOP;
--   END;
--   $job$;
--   $$
-- );
