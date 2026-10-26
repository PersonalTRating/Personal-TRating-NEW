-- ──────────────────────────────────────────────────────────────────────────────
-- MIGRATION: BMP Formula v3 — Model C with Trending Integration
--
-- Builds on supabase_trending_v3.sql. Changes:
--   1. Add distinct_reviewer_count column to trainers table.
--   2. Prior changed: 5 phantom@3.5★ → 8 phantom@4.0★
--      (first perfect review lands ~64–66 BMP instead of ~65).
--   3. Activity component replaces Momentum (Model C formula):
--        activity = max(min(momentum_raw * 0.8 + trending_bonus, 10), activity_floor)
--        activity_floor = min(eff_count / 20, 1) * 5  (established trainers keep ≥5 pts)
--        trending_bonus = 2 if is_trending else 0
--   4. Trending conditions A & B now require rating ≥ 3.5 (consistent with momentum).
--   5. Store distinct_reviewer_count (authenticated only, used for Fresh Face badge).
--   6. Cap anonymous reviews at 5 most recent per trainer for all BMP components
--      (quality, confidence, activity, trending). Additional anonymous reviews remain
--      in the reviews table for moderation but do not inflate BMP.
--      Ordering is deterministic: created_at DESC, id DESC on ties.
--
-- DO NOT run the backfill on production until the matching UI changes are deployed.
-- ──────────────────────────────────────────────────────────────────────────────

-- ── 1. Schema: add distinct_reviewer_count ────────────────────────────────────
ALTER TABLE trainers
  ADD COLUMN IF NOT EXISTS distinct_reviewer_count INTEGER DEFAULT 0;

-- ── 2. Updated BMP calculation function ──────────────────────────────────────
CREATE OR REPLACE FUNCTION calculate_bmp_for_trainer(p_trainer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_count    INTEGER;   -- total verified reviews
  v_eff_count      INTEGER;   -- deduplicated effective count (quality/confidence/momentum)
  v_distinct_count INTEGER;   -- authenticated distinct reviewer count (Fresh Face)
  v_sum_ratings    FLOAT;
  v_smoothed_avg   FLOAT;
  v_quality_pts    FLOAT;
  v_confidence_pts FLOAT;
  v_raw_momentum   FLOAT;
  v_activity_pts   FLOAT;
  v_activity_floor FLOAT;
  v_bmp_score      FLOAT;
  v_period_7d      INTEGER;   -- capped 7d effective reviews for momentum
  v_period_8_30d   INTEGER;   -- capped 8-30d effective reviews for momentum
  v_period_31_90d  INTEGER;   -- capped 31-90d effective reviews for momentum
  v_reviews_7d     INTEGER;   -- total 7d count (all ratings) — stored as recent_review_count
  v_trending_7d    INTEGER;   -- 7d count, rating ≥ 3.5 — condition A
  v_trending_prev  INTEGER;   -- 7-28d count, rating ≥ 3.5 — condition B
  v_is_trending    BOOLEAN;
  v_anon_ids       UUID[];    -- IDs of the 5 most recent anonymous reviews (cap)
BEGIN

  -- ── Total verified review count ─────────────────────────────────────────────
  SELECT COUNT(*) INTO v_total_count
  FROM reviews
  WHERE trainer_id = p_trainer_id AND is_verified = TRUE;

  IF v_total_count = 0 THEN
    UPDATE trainers
    SET bmp_score               = 0,
        is_trending             = FALSE,
        recent_review_count     = 0,
        distinct_reviewer_count = 0
    WHERE id = p_trainer_id;
    RETURN;
  END IF;

  -- ── Anonymous review cap: 5 most recent, deterministic ordering ──────────────
  -- Capping is computed once and reused in every subsequent CTE to ensure quality,
  -- confidence, activity and trending all use exactly the same eligible set.
  SELECT ARRAY(
    SELECT id
    FROM reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NULL
    ORDER BY created_at DESC, id DESC
    LIMIT 5
  ) INTO v_anon_ids;

  -- ── Effective review count + sum (latest per client + capped anonymous) ──────
  WITH latest_per_client AS (
    SELECT DISTINCT ON (client_id)
      id, rating
    FROM reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NOT NULL
    ORDER BY client_id, created_at DESC
  ),
  anon_cap AS (
    SELECT id, rating
    FROM reviews
    WHERE id = ANY(v_anon_ids)
  ),
  eff AS (
    SELECT id, rating FROM latest_per_client
    UNION ALL
    SELECT id, rating FROM anon_cap
  )
  SELECT COUNT(*), COALESCE(SUM(rating), 0)
  INTO v_eff_count, v_sum_ratings
  FROM eff;

  -- ── Distinct authenticated reviewer count (for Fresh Face badge) ────────────
  SELECT COUNT(DISTINCT client_id) INTO v_distinct_count
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND client_id IS NOT NULL;

  -- ── Component 1: Quality (0-70 pts) — prior 8@4.0★ ──────────────────────────
  v_smoothed_avg := (v_sum_ratings + 8.0 * 4.0) / (v_eff_count::FLOAT + 8.0);
  v_quality_pts  := LEAST((v_smoothed_avg / 5.0) * 70.0, 70.0);

  -- ── Component 2: Confidence (0-20 pts) ──────────────────────────────────────
  v_confidence_pts := LEAST(LN(v_eff_count::FLOAT + 1.0) / LN(51.0), 1.0) * 20.0;

  -- ── Total 7-day count (all ratings, all verified reviews) — display only ──────
  -- Not capped: recent_review_count is a UI display field, not a BMP input.
  SELECT COUNT(*) INTO v_reviews_7d
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '7 days';

  -- ── Trending + Momentum: single pass over capped eligible set ────────────────
  -- Uses latest-per-client (authenticated) and the pre-computed v_anon_ids cap.
  -- Trending and momentum share the same eligible review set for consistency.
  WITH latest_per_client AS (
    SELECT DISTINCT ON (client_id)
      id, rating, created_at
    FROM reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NOT NULL
    ORDER BY client_id, created_at DESC
  ),
  anon_cap AS (
    SELECT id, rating, created_at
    FROM reviews
    WHERE id = ANY(v_anon_ids)
  ),
  eff AS (
    SELECT id, rating, created_at FROM latest_per_client
    UNION ALL
    SELECT id, rating, created_at FROM anon_cap
  )
  SELECT
    -- Trending condition A: ≥2 qualifying reviews in last 7 days
    COUNT(*) FILTER (
      WHERE rating >= 3.5
        AND created_at >= NOW() - INTERVAL '7 days'
    )::INTEGER,
    -- Trending condition B: ≥1 qualifying review in 7–28 day window
    COUNT(*) FILTER (
      WHERE rating >= 3.5
        AND created_at >= NOW() - INTERVAL '28 days'
        AND created_at <  NOW() - INTERVAL '7 days'
    )::INTEGER,
    -- Momentum window 1: 7d (capped at 2 for raw score)
    LEAST(COUNT(*) FILTER (
      WHERE rating >= 3.5
        AND created_at >= NOW() - INTERVAL '7 days'), 2)::INTEGER,
    -- Momentum window 2: 8–30d (capped at 5)
    LEAST(COUNT(*) FILTER (
      WHERE rating >= 3.5
        AND created_at >= NOW() - INTERVAL '30 days'
        AND created_at <  NOW() - INTERVAL '7 days'), 5)::INTEGER,
    -- Momentum window 3: 31–90d (capped at 7)
    LEAST(COUNT(*) FILTER (
      WHERE rating >= 3.5
        AND created_at >= NOW() - INTERVAL '90 days'
        AND created_at <  NOW() - INTERVAL '30 days'), 7)::INTEGER
  INTO v_trending_7d, v_trending_prev, v_period_7d, v_period_8_30d, v_period_31_90d
  FROM eff;

  v_is_trending := (v_trending_7d >= 2 AND v_trending_prev >= 1);

  v_raw_momentum := (v_period_7d * 3.0) + (v_period_8_30d * 1.5) + (v_period_31_90d * 0.75);

  -- ── Component 3: Activity (0-10 pts) — Model C formula ──────────────────────
  -- activity_floor: established trainers (20+ effective reviews) always keep ≥5 pts.
  -- Model C: floor applied AFTER cap, so gaming (floor > momentum+bonus) cannot
  -- exceed the floor — fairer than adding bonus on top of floor.
  v_activity_floor := LEAST(v_eff_count::FLOAT / 20.0, 1.0) * 5.0;
  v_activity_pts :=
    GREATEST(
      LEAST(
        LEAST(v_raw_momentum / 7.5, 1.0) * 10.0 * 0.8
          + CASE WHEN v_is_trending THEN 2.0 ELSE 0.0 END,
        10.0
      ),
      v_activity_floor
    );

  -- ── Final BMP ──────────────────────────────────────────────────────────────────
  v_bmp_score := ROUND((v_quality_pts + v_confidence_pts + v_activity_pts)::NUMERIC, 1);

  -- ── Write ─────────────────────────────────────────────────────────────────────
  UPDATE trainers
  SET
    bmp_score               = v_bmp_score,
    is_trending             = v_is_trending,
    recent_review_count     = v_reviews_7d,
    distinct_reviewer_count = v_distinct_count
  WHERE id = p_trainer_id;

END;
$$;

GRANT EXECUTE ON FUNCTION calculate_bmp_for_trainer(UUID) TO service_role;


-- ── 3. Update refresh_trending_status to match v3 criteria (rating ≥ 3.5) ─────
-- refresh_trending_status is called by the daily scheduled function and pg_cron.
-- It must use the same ≥3.5★ filter as calculate_bmp_for_trainer, otherwise the
-- scheduled refresh would overwrite is_trending with stale (unfiltered) criteria.
CREATE OR REPLACE FUNCTION refresh_trending_status(p_trainer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviews_7d_all INTEGER;  -- all-rating count stored as recent_review_count (display)
  v_reviews_7d     INTEGER;  -- qualifying count for trending condition A
  v_reviews_prev   INTEGER;  -- qualifying count for trending condition B
  v_is_trending    BOOLEAN;
  v_anon_ids       UUID[];   -- IDs of the 5 most recent anonymous reviews (cap)
BEGIN
  -- Anonymous review cap: same 5-most-recent rule as calculate_bmp_for_trainer
  SELECT ARRAY(
    SELECT id
    FROM reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NULL
    ORDER BY created_at DESC, id DESC
    LIMIT 5
  ) INTO v_anon_ids;

  -- All-rating 7d count for recent_review_count display (not capped — display only)
  SELECT COUNT(*) INTO v_reviews_7d_all
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '7 days';

  -- Trending conditions use capped eligible set (latest-per-client + top-5 anon)
  WITH latest_per_client AS (
    SELECT DISTINCT ON (client_id)
      id, rating, created_at
    FROM reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NOT NULL
    ORDER BY client_id, created_at DESC
  ),
  anon_cap AS (
    SELECT id, rating, created_at
    FROM reviews
    WHERE id = ANY(v_anon_ids)
  ),
  eff AS (
    SELECT id, rating, created_at FROM latest_per_client
    UNION ALL
    SELECT id, rating, created_at FROM anon_cap
  )
  SELECT
    -- Condition A: ≥2 qualifying reviews in last 7 days
    COUNT(*) FILTER (
      WHERE rating >= 3.5
        AND created_at >= NOW() - INTERVAL '7 days'
    )::INTEGER,
    -- Condition B: ≥1 qualifying review in 7–28 day window
    COUNT(*) FILTER (
      WHERE rating >= 3.5
        AND created_at >= NOW() - INTERVAL '28 days'
        AND created_at <  NOW() - INTERVAL '7 days'
    )::INTEGER
  INTO v_reviews_7d, v_reviews_prev
  FROM eff;

  v_is_trending := (v_reviews_7d >= 2 AND v_reviews_prev >= 1);

  UPDATE trainers
  SET
    is_trending         = v_is_trending,
    recent_review_count = v_reviews_7d_all
  WHERE id = p_trainer_id;
END;
$$;

GRANT EXECUTE ON FUNCTION refresh_trending_status(UUID) TO service_role;


-- ── 5. Backfill all active trainers ────────────────────────────────────────────
-- Run immediately after deploying the functions above.
-- DO NOT execute on production without confirming UI updates are deployed first.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id FROM trainers WHERE is_active = TRUE LOOP
    PERFORM calculate_bmp_for_trainer(r.id);
  END LOOP;
END;
$$;


-- ── 6. Update get_own_trainer_profile() to return distinct_reviewer_count ───────
-- Required for the dashboard Fresh Face indicator.  Must run AFTER step 1
-- (ALTER TABLE) because the function body references the new column.
CREATE OR REPLACE FUNCTION get_own_trainer_profile()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'id',                      t.id,
    'name',                    t.name,
    'username',                t.username,
    'business_name',           t.business_name,
    'city',                    t.city,
    'location',                t.location,
    'bio',                     t.bio,
    'intro_message',           t.intro_message,
    'specialty',               t.specialty,
    'coaching_type',           t.coaching_type,
    'cert',                    t.cert,
    'bmp_score',               t.bmp_score,
    'star_rating',             t.star_rating,
    'review_count',            t.review_count,
    'avatar_url',              t.avatar_url,
    'avatar_initials',         t.avatar_initials,
    'avatar_bg',               t.avatar_bg,
    'avatar_color',            t.avatar_color,
    'postcode',                t.postcode,
    'is_trending',             t.is_trending,
    'distinct_reviewer_count', t.distinct_reviewer_count,
    'gyms',                    t.gyms,
    'hero_theme',              t.hero_theme,
    'social_facebook',         t.social_facebook,
    'social_instagram',        t.social_instagram,
    'social_whatsapp',         t.social_whatsapp,
    'social_email',            t.social_email,
    'accepts_bookings',        t.accepts_bookings,
    'booking_url',             t.booking_url,
    'location_confirmed',      t.location_confirmed,
    'cc_country',              t.cc_country,
    'cc_local_area',           t.cc_local_area,
    'location_cooldown_until', t.location_cooldown_until
  )
  FROM   public.trainers t
  WHERE  t.user_id = auth.uid()
  LIMIT  1;
$$;

NOTIFY pgrst, 'reload schema';


-- ── 7. Comprehensive BMP recalculation trigger ────────────────────────────────
-- Replaces the earlier zzz_on_review_bmp_update trigger (FALSE→TRUE approvals only)
-- with a function that covers all seven review lifecycle events:
--   INSERT already verified, DELETE verified, TRUE→FALSE un-approval,
--   rating / client_id / created_at changes on verified review, trainer_id change.
-- See supabase_bmp_trigger_fix.sql for full rationale.

CREATE OR REPLACE FUNCTION public.trigger_recalculate_bmp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

  IF TG_OP = 'INSERT' THEN
    IF NEW.is_verified = TRUE THEN
      PERFORM public.calculate_bmp_for_trainer(NEW.trainer_id);
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF OLD.is_verified = TRUE THEN
      PERFORM public.calculate_bmp_for_trainer(OLD.trainer_id);
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.trainer_id IS DISTINCT FROM OLD.trainer_id THEN
      IF OLD.is_verified = TRUE THEN
        PERFORM public.calculate_bmp_for_trainer(OLD.trainer_id);
      END IF;
      IF NEW.is_verified = TRUE THEN
        PERFORM public.calculate_bmp_for_trainer(NEW.trainer_id);
      END IF;
      RETURN NEW;
    END IF;

    IF OLD.is_verified = FALSE AND NEW.is_verified = FALSE THEN
      RETURN NEW;
    END IF;

    IF NEW.is_verified  IS DISTINCT FROM OLD.is_verified  OR
       NEW.rating        IS DISTINCT FROM OLD.rating       OR
       NEW.client_id     IS DISTINCT FROM OLD.client_id    OR
       NEW.created_at    IS DISTINCT FROM OLD.created_at
    THEN
      PERFORM public.calculate_bmp_for_trainer(NEW.trainer_id);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.trigger_recalculate_bmp() TO service_role;

DROP TRIGGER IF EXISTS zzz_on_review_bmp_update ON public.reviews;

CREATE TRIGGER zzz_on_review_bmp_update
  AFTER INSERT OR UPDATE OR DELETE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_recalculate_bmp();


-- ── 8. Strip bmp_score writes from legacy trigger functions ───────────────────
-- Production has two trigger functions that pre-date the BMP scoring system:
--
--   update_trainer_stats()       called by on_review_approved + on_review_created
--   update_trainer_star_rating() called by trg_update_star_rating
--
-- Both functions write bmp_score using outdated formulas and query reviews
-- WITHOUT filtering is_verified = TRUE.  After this step:
--   • bmp_score is written ONLY by calculate_bmp_for_trainer() (via zzz_ trigger)
--   • star_rating and review_count are still maintained by both functions
--   • All queries filter is_verified = TRUE so pending reviews cannot corrupt stats
--   • A pending-review INSERT leaves every trainer statistic unchanged
--
-- This step does NOT drop or modify any triggers — only the underlying functions.
-- Alphabetical ordering (on_ < trg_ < zzz_) is preserved and remains correct:
--   on_review_approved / on_review_created  → update star_rating, review_count only
--   trg_update_star_rating                  → update star_rating, review_count only
--   zzz_on_review_bmp_update                → update bmp_score, is_trending, etc.

CREATE OR REPLACE FUNCTION public.update_trainer_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _avg   NUMERIC;
  _count INTEGER;
BEGIN
  -- on_review_created fires this on all INSERTs, including pending reviews.
  -- Skip entirely when the inserted or current review is not verified; no
  -- pending-review INSERT may change public trainer statistics.
  IF TG_OP = 'INSERT' AND NEW.is_verified IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  -- Read only from the verified-review set.
  SELECT COALESCE(AVG(rating), 0), COUNT(*)
  INTO   _avg, _count
  FROM   reviews
  WHERE  trainer_id = NEW.trainer_id
    AND  is_verified = TRUE;

  UPDATE trainers
  SET star_rating  = _avg,
      review_count = _count
      -- bmp_score intentionally omitted: calculate_bmp_for_trainer() owns it
  WHERE id = NEW.trainer_id;

  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_trainer_stats() TO service_role;


CREATE OR REPLACE FUNCTION public.update_trainer_star_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _trainer_id UUID;
  _avg        NUMERIC;
  _count      INTEGER;
BEGIN
  -- Pending-review INSERT: no change to any public statistics.
  IF TG_OP = 'INSERT' AND NEW.is_verified IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  -- UPDATE where review is not and was not verified: no change.
  IF TG_OP = 'UPDATE'
     AND NEW.is_verified IS NOT TRUE
     AND OLD.is_verified IS NOT TRUE
  THEN
    RETURN NEW;
  END IF;

  -- DELETE: only recalculate if the deleted review was verified.
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_verified = TRUE THEN
      SELECT COALESCE(AVG(rating), 0), COUNT(*)
      INTO   _avg, _count
      FROM   reviews
      WHERE  trainer_id = OLD.trainer_id
        AND  is_verified = TRUE;

      UPDATE trainers
      SET star_rating  = _avg,
          review_count = _count
      WHERE id = OLD.trainer_id;
    END IF;
    RETURN OLD;
  END IF;

  -- UPDATE with trainer_id change: recalculate the old trainer too.
  IF TG_OP = 'UPDATE' AND NEW.trainer_id IS DISTINCT FROM OLD.trainer_id THEN
    SELECT COALESCE(AVG(rating), 0), COUNT(*)
    INTO   _avg, _count
    FROM   reviews
    WHERE  trainer_id = OLD.trainer_id
      AND  is_verified = TRUE;

    UPDATE trainers
    SET star_rating  = _avg,
        review_count = _count
    WHERE id = OLD.trainer_id;
  END IF;

  -- INSERT or UPDATE (current/new trainer).
  _trainer_id := NEW.trainer_id;

  SELECT COALESCE(AVG(rating), 0), COUNT(*)
  INTO   _avg, _count
  FROM   reviews
  WHERE  trainer_id = _trainer_id
    AND  is_verified = TRUE;

  UPDATE trainers
  SET star_rating  = _avg,
      review_count = _count
      -- bmp_score intentionally omitted: calculate_bmp_for_trainer() owns it
  WHERE id = _trainer_id;

  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_trainer_star_rating() TO service_role;

DO $$ BEGIN
  RAISE NOTICE 'Step 8: update_trainer_stats() and update_trainer_star_rating() corrected — bmp_score writes removed, is_verified = TRUE filter added.';
END; $$;


-- ── Post-migration: frontend query updates required ────────────────────────────
-- After running this migration, update the following to activate Fresh Face on
-- public card surfaces:
--
--   src/pages/find-a-trainer.astro  — add distinct_reviewer_count to .select()
--                                   — pass distinctReviewerCount={t.distinct_reviewer_count ?? null}
--                                     to <TrainerCard>
--
--   src/pages/trainers/[id].astro   — add distinct_reviewer_count to .select()
--                                     (badge HTML already in place; null-safe)
--
--   src/pages/index.astro           — add to topTrainers select if showing Fresh Face there
--
-- Until these SELECT updates are deployed, Fresh Face badges are hidden on public
-- surfaces (TrainerCard.distinctReviewerCount defaults to null → no badge).
-- The dashboard Fresh Face indicator activates automatically once step 6 above
-- (get_own_trainer_profile update) is deployed.
