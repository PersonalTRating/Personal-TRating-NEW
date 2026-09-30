-- ─────────────────────────────────────────────────────────────────────────────
-- CoachCards: 30-Day Review Rule + Latest-Per-Client BMP
-- Run this ONCE in Supabase → SQL Editor → New query
--
-- What this does:
--   1. Adds a partial UNIQUE index to prevent multiple simultaneous pending
--      reviews from the same client for the same trainer (race-condition guard)
--   2. Adds supporting indexes for efficient eligibility + BMP queries
--   3. Creates check_review_eligibility() — called by the review page for early UX
--   4. Creates submit_review_for_client() — atomic replacement for direct INSERT,
--      enforces the 30-day rolling rule server-side with advisory lock protection
--   5. Replaces calculate_bmp_for_trainer() — only each client's MOST RECENT
--      verified review contributes to Quality, Confidence, and Momentum.
--      Trending and recent_review_count still count ALL verified reviews.
--   6. Backfills all active trainers with the new BMP formula
-- ─────────────────────────────────────────────────────────────────────────────


-- ── Step 1: Indexes ───────────────────────────────────────────────────────────

-- Prevents two simultaneous pending reviews from the same client+trainer.
-- When a pending review is approved (is_verified → TRUE) or rejected (deleted),
-- the unique constraint no longer covers it, freeing the slot.
CREATE UNIQUE INDEX IF NOT EXISTS uq_one_pending_per_client_trainer
  ON reviews (client_id, trainer_id)
  WHERE is_verified = FALSE AND client_id IS NOT NULL;

-- Supports the "latest review per client per trainer" deduplication queries in BMP
-- and the eligibility check ordering by (trainer_id, client_id, created_at).
CREATE INDEX IF NOT EXISTS idx_reviews_trainer_client_created
  ON reviews (trainer_id, client_id, created_at DESC)
  WHERE is_verified = TRUE AND client_id IS NOT NULL;

-- Supports the pending-review check in eligibility/submission.
CREATE INDEX IF NOT EXISTS idx_reviews_client_trainer_pending
  ON reviews (client_id, trainer_id)
  WHERE is_verified = FALSE AND client_id IS NOT NULL;


-- ── Step 2: Eligibility pre-check function ────────────────────────────────────
--
-- Called by the review page after the client is identified, BEFORE the form is
-- shown. Allows the UI to display a useful "You can review again on <date>"
-- message instead of letting the client fill out the entire form and then fail.
--
-- Returns JSONB:
--   { "status": "eligible" }
--   { "status": "pending_review" }
--   { "status": "blocked", "next_eligible_at": "<ISO timestamp>" }
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION check_review_eligibility(
  p_client_id  UUID,
  p_trainer_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_review_at     TIMESTAMPTZ;
  v_next_eligible TIMESTAMPTZ;
BEGIN
  -- No client_id → cannot determine identity, allow (handles the rare edge case
  -- where a logged-in user has no clients record)
  IF p_client_id IS NULL THEN
    RETURN jsonb_build_object('status', 'eligible');
  END IF;

  -- Block if a pending review already exists (prevent multiple simultaneous submissions)
  SELECT created_at INTO v_review_at
  FROM reviews
  WHERE client_id  = p_client_id
    AND trainer_id = p_trainer_id
    AND is_verified = FALSE
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object('status', 'pending_review');
  END IF;

  -- Block if within 30 rolling days of the most recent verified review.
  -- Clock starts from the original submission time (created_at) of the approved review.
  SELECT created_at INTO v_review_at
  FROM reviews
  WHERE client_id  = p_client_id
    AND trainer_id = p_trainer_id
    AND is_verified = TRUE
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    v_next_eligible := v_review_at + INTERVAL '30 days';
    IF NOW() < v_next_eligible THEN
      RETURN jsonb_build_object(
        'status',          'blocked',
        'next_eligible_at', v_next_eligible
      );
    END IF;
  END IF;

  RETURN jsonb_build_object('status', 'eligible');
END;
$$;

GRANT EXECUTE ON FUNCTION check_review_eligibility(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION check_review_eligibility(UUID, UUID) TO anon;


-- ── Step 3: Atomic submit function ───────────────────────────────────────────
--
-- Replaces the direct client-side INSERT into reviews.
-- Enforces the 30-day rolling rule server-side and is race-condition safe:
--   - pg_advisory_xact_lock serialises concurrent submissions for the same
--     (client, trainer) pair — the lock is automatically released on commit.
--   - The unique partial index (Step 1) provides a hard DB-level guard as backup.
--
-- Returns JSONB:
--   { "status": "ok",             "review_id": "<UUID>" }
--   { "status": "blocked",        "next_eligible_at": "<ISO timestamp>" }
--   { "status": "pending_review" }
--
-- The 30-day clock starts from created_at of a successfully VERIFIED review.
-- A pending (unverified) review blocks further submission until it is resolved
-- (approved → verified, or rejected → deleted).  A rejected review disappears
-- from the table, so the client can submit again immediately after rejection.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION submit_review_for_client(
  p_trainer_id            UUID,
  p_client_id             UUID,
  p_reviewer_name         TEXT,
  p_reviewer_initials     TEXT,
  p_reviewer_avatar_bg    TEXT,
  p_reviewer_avatar_color TEXT,
  p_reviewer_location     TEXT,
  p_rating                FLOAT8,
  p_review_text           TEXT,
  p_is_anonymous          BOOLEAN,
  p_approval_token        UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_review_at     TIMESTAMPTZ;
  v_next_eligible TIMESTAMPTZ;
  v_review_id     UUID;
BEGIN

  IF p_client_id IS NOT NULL THEN

    -- Advisory lock: serialise concurrent submissions from the same client+trainer.
    -- Uses two int4 hash keys; transaction-level so it auto-releases on commit/rollback.
    PERFORM pg_advisory_xact_lock(
      hashtext(p_client_id::text),
      hashtext(p_trainer_id::text)
    );

    -- Guard: block if a pending review already exists
    SELECT created_at INTO v_review_at
    FROM reviews
    WHERE client_id  = p_client_id
      AND trainer_id = p_trainer_id
      AND is_verified = FALSE
    ORDER BY created_at DESC
    LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object('status', 'pending_review');
    END IF;

    -- Guard: block if within 30 rolling days of the last verified review
    SELECT created_at INTO v_review_at
    FROM reviews
    WHERE client_id  = p_client_id
      AND trainer_id = p_trainer_id
      AND is_verified = TRUE
    ORDER BY created_at DESC
    LIMIT 1;

    IF FOUND THEN
      v_next_eligible := v_review_at + INTERVAL '30 days';
      IF NOW() < v_next_eligible THEN
        RETURN jsonb_build_object(
          'status',          'blocked',
          'next_eligible_at', v_next_eligible
        );
      END IF;
    END IF;

  END IF;

  -- All checks passed — insert the review
  INSERT INTO reviews (
    trainer_id,            client_id,
    reviewer_name,         reviewer_initials,
    reviewer_avatar_bg,    reviewer_avatar_color,
    reviewer_location,
    rating,                review_text,
    is_verified,           is_anonymous,
    approval_token
  )
  VALUES (
    p_trainer_id,          p_client_id,
    p_reviewer_name,       p_reviewer_initials,
    p_reviewer_avatar_bg,  p_reviewer_avatar_color,
    p_reviewer_location,
    p_rating,              p_review_text,
    FALSE,                 p_is_anonymous,
    p_approval_token
  )
  RETURNING id INTO v_review_id;

  RETURN jsonb_build_object('status', 'ok', 'review_id', v_review_id);
END;
$$;

GRANT EXECUTE ON FUNCTION submit_review_for_client(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT8, TEXT, BOOLEAN, UUID)
  TO authenticated;
GRANT EXECUTE ON FUNCTION submit_review_for_client(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT8, TEXT, BOOLEAN, UUID)
  TO anon;


-- ── Step 4: Updated BMP calculation — latest-per-client deduplication ─────────
--
-- Key change: for Quality, Confidence, and Momentum, only the MOST RECENT
-- verified review per authenticated client contributes.  Reviews with no
-- client_id (anonymous/guest edge cases) each count individually.
--
-- Trending and recent_review_count still count ALL verified reviews because a
-- new eligible repeat review is genuine new activity (spec sections 18-19).
-- The trending credibility floor (v_total_count >= 5) still uses the total
-- verified review count, not the deduplicated effective count.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION calculate_bmp_for_trainer(p_trainer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_count    INTEGER;  -- total verified reviews (for trending floor + star_rating ref)
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
  v_reviews_30d    INTEGER;
  v_weeks_30d      INTEGER;
  v_is_trending    BOOLEAN;
BEGIN

  -- ── Total verified review count (for trending credibility floor) ──────────
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
  -- IS NULL) are included individually — no persistent identity to deduplicate on.
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
  -- Based on the effective contributor count, not raw total, so repeat reviews
  -- from one client do not inflate confidence in the signal.
  v_confidence_pts := LEAST(LN(v_eff_count::FLOAT + 1.0) / LN(51.0), 1.0) * 20.0;

  -- ── Component 3: Momentum (0-10 pts) — effective reviews only ────────────
  -- Only the client's latest review counts for momentum; older superseded reviews
  -- from the same client do not additionally contribute to recent activity here.
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

  -- ── Trending counts — ALL verified reviews (not deduplicated) ────────────
  -- A new eligible repeat review is genuine new activity (spec §18-19),
  -- so it counts toward recent activity and the trending spread check.
  SELECT
    COUNT(*),
    COUNT(DISTINCT DATE_TRUNC('week', created_at)::DATE)
  INTO v_reviews_30d, v_weeks_30d
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '30 days';

  -- ── Trending eligibility ──────────────────────────────────────────────────
  -- Credibility floor uses v_total_count (total verified reviews) — unchanged
  -- from the previous formula so the trending threshold is not altered.
  v_is_trending := (
    v_total_count >= 5
    AND v_reviews_30d >= 4
    AND v_weeks_30d   >= 2
    AND v_quality_pts >= 42.0
  );

  -- ── Write ─────────────────────────────────────────────────────────────────
  UPDATE trainers
  SET
    bmp_score           = v_bmp_score,
    is_trending         = v_is_trending,
    recent_review_count = v_reviews_30d
  WHERE id = p_trainer_id;

END;
$$;

GRANT EXECUTE ON FUNCTION calculate_bmp_for_trainer(UUID) TO service_role;


-- ── Step 5: Backfill all active trainers ─────────────────────────────────────
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
