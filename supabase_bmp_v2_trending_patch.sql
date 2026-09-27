-- ─────────────────────────────────────────────────────────────────────────────
-- BMP v2 Trending Patch — Run in Supabase → SQL Editor → New query
--
-- Updates trending eligibility to the published thresholds:
--   • 5+ verified reviews overall
--   • 4+ verified reviews in the last 30 days
--   • Reviews across at least 2 separate calendar weeks in last 30 days
--
-- Also adds recent_review_count column (# of verified reviews in last 30 days)
-- so the leaderboard can display "N verified reviews recently" on the hot banner.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE trainers
  ADD COLUMN IF NOT EXISTS recent_review_count INTEGER DEFAULT 0;


-- Replace calculate_bmp_for_trainer with updated trending logic
CREATE OR REPLACE FUNCTION calculate_bmp_for_trainer(p_trainer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_review_count   INTEGER;
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
  -- Trending-specific counts
  v_reviews_30d    INTEGER;   -- total verified reviews in last 30 days (any rating)
  v_weeks_30d      INTEGER;   -- distinct calendar weeks with reviews in last 30 days
  v_is_trending    BOOLEAN;
BEGIN
  -- ── Verified review stats ─────────────────────────────────────────────────
  SELECT COUNT(*), COALESCE(SUM(rating), 0)
  INTO v_review_count, v_sum_ratings
  FROM reviews
  WHERE trainer_id = p_trainer_id AND is_verified = TRUE;

  IF v_review_count = 0 THEN
    UPDATE trainers
    SET bmp_score = 0, is_trending = FALSE, recent_review_count = 0
    WHERE id = p_trainer_id;
    RETURN;
  END IF;

  -- ── Component 1: Quality (0–70 pts) ──────────────────────────────────────
  v_smoothed_avg := (v_sum_ratings + 5.0 * 3.5) / (v_review_count::FLOAT + 5.0);
  v_quality_pts  := LEAST((v_smoothed_avg / 5.0) * 70.0, 70.0);

  -- ── Component 2: Confidence (0–20 pts) ───────────────────────────────────
  v_confidence_pts := LEAST(LN(v_review_count::FLOAT + 1.0) / LN(51.0), 1.0) * 20.0;

  -- ── Component 3: Momentum (0–10 pts) ─────────────────────────────────────
  SELECT
    LEAST(COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days'), 2)::INTEGER,
    LEAST(COUNT(*) FILTER (
      WHERE created_at >= NOW() - INTERVAL '30 days'
        AND created_at <  NOW() - INTERVAL '7 days'), 5)::INTEGER,
    LEAST(COUNT(*) FILTER (
      WHERE created_at >= NOW() - INTERVAL '90 days'
        AND created_at <  NOW() - INTERVAL '30 days'), 7)::INTEGER
  INTO v_period_7d, v_period_8_30d, v_period_31_90d
  FROM reviews
  WHERE trainer_id = p_trainer_id AND is_verified = TRUE AND rating >= 3.5
    AND created_at >= NOW() - INTERVAL '90 days';

  v_raw_momentum := (v_period_7d * 3.0) + (v_period_8_30d * 1.5) + (v_period_31_90d * 0.75);
  v_momentum_pts := LEAST(v_raw_momentum / 7.5, 1.0) * 10.0;

  -- ── Final BMP ─────────────────────────────────────────────────────────────
  v_bmp_score := ROUND((v_quality_pts + v_confidence_pts + v_momentum_pts)::NUMERIC, 1);

  -- ── Trending counts ───────────────────────────────────────────────────────
  SELECT
    COUNT(*),
    COUNT(DISTINCT DATE_TRUNC('week', created_at)::DATE)
  INTO v_reviews_30d, v_weeks_30d
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '30 days';

  -- ── Trending eligibility ──────────────────────────────────────────────────
  -- Must satisfy ALL of:
  --   1. 5+ verified reviews overall (credibility floor)
  --   2. 4+ verified reviews in the last 30 days
  --   3. Reviews spread across at least 2 separate calendar weeks in last 30 days
  --   4. Minimum quality score (prevents low-rated trainers from trending)
  v_is_trending := (
    v_review_count >= 5
    AND v_reviews_30d >= 4
    AND v_weeks_30d  >= 2
    AND v_quality_pts >= 42.0
  );

  -- ── Write ─────────────────────────────────────────────────────────────────
  UPDATE trainers
  SET
    bmp_score            = v_bmp_score,
    is_trending          = v_is_trending,
    recent_review_count  = v_reviews_30d
  WHERE id = p_trainer_id;

END;
$$;

GRANT EXECUTE ON FUNCTION calculate_bmp_for_trainer(UUID) TO service_role;


-- ── Backfill: recalculate all active trainers with new trending criteria ──────
DO $$
DECLARE t_id UUID;
BEGIN
  FOR t_id IN SELECT id FROM trainers WHERE is_active = TRUE
  LOOP
    UPDATE trainers
    SET
      star_rating  = (SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE trainer_id = t_id AND is_verified = TRUE),
      review_count = (SELECT COUNT(*)                  FROM reviews WHERE trainer_id = t_id AND is_verified = TRUE)
    WHERE id = t_id;
    PERFORM calculate_bmp_for_trainer(t_id);
  END LOOP;
END;
$$;
