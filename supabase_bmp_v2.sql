-- ─────────────────────────────────────────────────────────────────────────────
-- BMP v2 — Run this in Supabase → SQL Editor → New query
--
-- What this does:
--   1. Adds is_trending + rank_history columns to trainers
--   2. Creates calculate_bmp_for_trainer(UUID) — the v2 formula
--   3. Creates snapshot_weekly_ranks() — call weekly (manually or via cron)
--   4. Updates approve_review_by_token to call the new BMP function
--   5. Updates remove_appealed_review to call the new BMP function
--   6. Backfills all existing trainers with their v2 score (run once)
-- ─────────────────────────────────────────────────────────────────────────────


-- ── Step 1: Schema additions ──────────────────────────────────────────────────

ALTER TABLE trainers
  ADD COLUMN IF NOT EXISTS is_trending  BOOLEAN  DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS rank_history JSONB    DEFAULT '[]'::jsonb;


-- ── Step 2: Core BMP v2 calculation function ──────────────────────────────────
--
-- Formula:
--   Quality (70 pts)    — Bayesian-smoothed average star rating
--   Confidence (20 pts) — Logarithmic confidence based on review count
--   Momentum (10 pts)   — Weighted count of recent quality reviews (last 90 days)
--
-- Trending: trainer is trending when they have strong recent activity AND
--           their momentum is meaningful AND their overall quality is decent.
-- ─────────────────────────────────────────────────────────────────────────────

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
  -- Momentum sub-counts (capped to discourage burst gaming)
  v_period_7d      INTEGER;
  v_period_8_30d   INTEGER;
  v_period_31_90d  INTEGER;
  v_raw_momentum   FLOAT;
  v_is_trending    BOOLEAN;
BEGIN
  -- ── Fetch verified review stats ───────────────────────────────────────────
  SELECT
    COUNT(*),
    COALESCE(SUM(rating), 0)
  INTO v_review_count, v_sum_ratings
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE;

  -- No verified reviews → score is 0
  IF v_review_count = 0 THEN
    UPDATE trainers
    SET bmp_score = 0, is_trending = FALSE
    WHERE id = p_trainer_id;
    RETURN;
  END IF;

  -- ── Component 1: Quality (0–70 pts) ──────────────────────────────────────
  -- Bayesian smoothing: add 5 phantom reviews at 3.5 stars (global prior).
  -- This prevents a single 5-star review from dominating and drags new trainers
  -- toward the centre until they've earned enough real signal.
  v_smoothed_avg := (v_sum_ratings + 5.0 * 3.5) / (v_review_count::FLOAT + 5.0);
  v_quality_pts  := LEAST((v_smoothed_avg / 5.0) * 70.0, 70.0);

  -- ── Component 2: Confidence (0–20 pts) ───────────────────────────────────
  -- Logarithmic curve: LN(n+1) / LN(51).
  -- Reaches full 20 pts at 50 reviews, with fast early gains then diminishing returns.
  --   1 review  →  3.8 pts
  --   5 reviews →  9.0 pts
  --  10 reviews → 12.1 pts
  --  25 reviews → 16.8 pts
  --  50 reviews → 20.0 pts
  v_confidence_pts := LEAST(
    LN(v_review_count::FLOAT + 1.0) / LN(51.0),
    1.0
  ) * 20.0;

  -- ── Component 3: Momentum (0–10 pts) ─────────────────────────────────────
  -- Counts quality-gated recent reviews (rating >= 3.5) by time window.
  -- Burst cap: max 2 per 7-day window, 5 per 8-30d window, 7 per 31-90d window.
  -- Weights: 7d=3x, 8-30d=1.5x, 31-90d=0.75x.
  -- Normalised so ~1 quality review/week for 4 weeks = full momentum (7.5 pts / 7.5 = 10).
  SELECT
    LEAST(COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '7 days'), 2)::INTEGER,
    LEAST(COUNT(*) FILTER (
      WHERE created_at >= NOW() - INTERVAL '30 days'
        AND created_at <  NOW() - INTERVAL '7 days'
    ), 5)::INTEGER,
    LEAST(COUNT(*) FILTER (
      WHERE created_at >= NOW() - INTERVAL '90 days'
        AND created_at <  NOW() - INTERVAL '30 days'
    ), 7)::INTEGER
  INTO v_period_7d, v_period_8_30d, v_period_31_90d
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND rating >= 3.5
    AND created_at >= NOW() - INTERVAL '90 days';

  v_raw_momentum := (v_period_7d * 3.0)
                  + (v_period_8_30d * 1.5)
                  + (v_period_31_90d * 0.75);
  v_momentum_pts := LEAST(v_raw_momentum / 7.5, 1.0) * 10.0;

  -- ── Final BMP score ───────────────────────────────────────────────────────
  v_bmp_score := v_quality_pts + v_confidence_pts + v_momentum_pts;
  v_bmp_score := ROUND(v_bmp_score::NUMERIC, 1);

  -- ── Trending eligibility ──────────────────────────────────────────────────
  -- Must satisfy ALL of:
  --   • 5+ total verified reviews (credibility floor)
  --   • Meaningful momentum (>= 4.0 pts, i.e. consistent recent activity)
  --   • Active in last 7 days (at least 1 quality review)
  --   • Active across multiple windows (not a one-day burst)
  --   • Minimum quality (quality_pts >= 42 ≈ smoothed avg >= 3.0 stars)
  v_is_trending := (
    v_review_count >= 5
    AND v_momentum_pts >= 4.0
    AND v_period_7d >= 1
    AND (v_period_7d + v_period_8_30d) >= 2
    AND v_quality_pts >= 42.0
  );

  -- ── Write to trainers ─────────────────────────────────────────────────────
  UPDATE trainers
  SET
    bmp_score   = v_bmp_score,
    is_trending = v_is_trending
  WHERE id = p_trainer_id;

END;
$$;

GRANT EXECUTE ON FUNCTION calculate_bmp_for_trainer(UUID) TO service_role;


-- ── Step 3: Weekly rank snapshot ─────────────────────────────────────────────
--
-- Call this once a week (e.g. via a Supabase pg_cron job or manually).
-- Appends each trainer's current rank + BMP to their rank_history array,
-- keeping the last 8 snapshots (8 weeks of history).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION snapshot_weekly_ranks()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  snapshot_date TEXT := TO_CHAR(NOW(), 'YYYY-MM-DD');
BEGIN
  UPDATE trainers t
  SET rank_history = (
    -- Append new entry, keep last 8
    SELECT jsonb_agg(entry ORDER BY (entry->>'snapped_at') DESC)
    FROM (
      SELECT entry
      FROM jsonb_array_elements(
        COALESCE(t.rank_history, '[]'::jsonb) ||
        jsonb_build_array(
          jsonb_build_object(
            'rank',       ranked.rn,
            'bmp',        t.bmp_score,
            'snapped_at', snapshot_date
          )
        )
      ) AS entry
      LIMIT 8
    ) sub
  )
  FROM (
    SELECT id, ROW_NUMBER() OVER (ORDER BY bmp_score DESC NULLS LAST) AS rn
    FROM trainers
    WHERE is_active = TRUE AND bmp_score > 0
  ) ranked
  WHERE t.id = ranked.id;
END;
$$;

GRANT EXECUTE ON FUNCTION snapshot_weekly_ranks() TO service_role;


-- ── Step 4: Updated approve_review_by_token ───────────────────────────────────
--
-- Replaces the old version which only updated star_rating + review_count.
-- Now calls calculate_bmp_for_trainer to compute the full v2 BMP score.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION approve_review_by_token(p_token text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviewer_name text;
  v_trainer_id    uuid;
  v_is_verified   boolean;
BEGIN
  -- Check the review exists
  SELECT is_verified INTO v_is_verified
  FROM   reviews
  WHERE  approval_token::text = p_token
  LIMIT  1;

  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;

  IF v_is_verified = true THEN
    RETURN 'already_approved';
  END IF;

  -- Approve the review
  UPDATE reviews
  SET    is_verified = true
  WHERE  approval_token::text = p_token
    AND  is_verified = false
  RETURNING reviewer_name, trainer_id
       INTO v_reviewer_name, v_trainer_id;

  IF v_reviewer_name IS NULL THEN
    RETURN 'not_found';
  END IF;

  -- Update star_rating + review_count (kept for compatibility with existing queries)
  UPDATE trainers
  SET
    star_rating  = (
      SELECT COALESCE(AVG(rating), 0)
      FROM   reviews
      WHERE  trainer_id  = v_trainer_id
        AND  is_verified = true
    ),
    review_count = (
      SELECT COUNT(*)
      FROM   reviews
      WHERE  trainer_id  = v_trainer_id
        AND  is_verified = true
    )
  WHERE id = v_trainer_id;

  -- Calculate and write BMP v2 score + trending flag
  PERFORM calculate_bmp_for_trainer(v_trainer_id);

  RETURN v_reviewer_name;
END;
$$;

GRANT EXECUTE ON FUNCTION approve_review_by_token(text) TO anon;
GRANT EXECUTE ON FUNCTION approve_review_by_token(text) TO authenticated;


-- ── Step 5: Updated remove_appealed_review ────────────────────────────────────
--
-- Replaces the old version in supabase_appeal_fn.sql.
-- Now recalculates full BMP v2 after removing a review.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION remove_appealed_review(p_token uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_trainer_id    uuid;
  v_reviewer_name text;
BEGIN
  SELECT trainer_id, reviewer_name INTO v_trainer_id, v_reviewer_name
  FROM reviews WHERE appeal_token = p_token AND appeal_status = 'pending';
  IF NOT FOUND THEN RETURN 'not_found'; END IF;

  DELETE FROM reviews WHERE appeal_token = p_token;

  -- Update star_rating + review_count
  UPDATE trainers SET
    star_rating  = (SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE trainer_id = v_trainer_id AND is_verified = true),
    review_count = (SELECT COUNT(*)                  FROM reviews WHERE trainer_id = v_trainer_id AND is_verified = true)
  WHERE id = v_trainer_id;

  -- Recalculate BMP v2
  PERFORM calculate_bmp_for_trainer(v_trainer_id);

  RETURN v_reviewer_name;
END;
$$;

GRANT EXECUTE ON FUNCTION remove_appealed_review(uuid) TO anon;
GRANT EXECUTE ON FUNCTION remove_appealed_review(uuid) TO authenticated;


-- ── Step 6: Backfill all existing trainers ────────────────────────────────────
--
-- Run this ONCE after deploying the above to recalculate every trainer's
-- BMP score using the v2 formula. Safe to run again at any time.
-- ─────────────────────────────────────────────────────────────────────────────

DO $$
DECLARE
  t_id UUID;
BEGIN
  FOR t_id IN SELECT id FROM trainers WHERE is_active = TRUE
  LOOP
    -- First update star_rating and review_count
    UPDATE trainers
    SET
      star_rating  = (SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE trainer_id = t_id AND is_verified = TRUE),
      review_count = (SELECT COUNT(*)                  FROM reviews WHERE trainer_id = t_id AND is_verified = TRUE)
    WHERE id = t_id;
    -- Then calculate BMP v2
    PERFORM calculate_bmp_for_trainer(t_id);
  END LOOP;
END;
$$;
