-- ══════════════════════════════════════════════════════════════════════════════
-- CoachCards — BMP v3 Rollback Script
--
-- Run this ONLY if supabase_bmp_v3_migration.sql needs to be undone.
-- Prerequisite: supabase_v3_preflight_backup.sql must have been executed
-- before the migration (backup table bmp_v3_migration_backup must exist).
--
-- What this does:
--   Step 1. Verifies the backup table exists and has data.
--   Step 2. Restores bmp_score, is_trending, recent_review_count,
--           star_rating and review_count from the latest backup run.
--   Step 3. Drops distinct_reviewer_count column (added by v3 step 1).
--   Step 4. Restores calculate_bmp_for_trainer to the trending_v3 body
--           (5@3.5★ prior, no Model C activity floor, no anon cap).
--   Step 5. Restores refresh_trending_status to the supabase_trending_autoupdate
--           body (plain COUNT of all verified reviews, no deduplication).
--   Step 6. Restores get_own_trainer_profile to the b1 body
--           (without distinct_reviewer_count in the JSONB output).
--   Step 7. NOTIFY pgrst to reload schema.
--
-- v2 of rollback (added after production trigger audit):
--   Step 7. Restore pre-v3 trigger configuration.
--   Step 8. Restore original bodies of update_trainer_stats() and
--           update_trainer_star_rating() (migration Step 8 had removed
--           their bmp_score writes; rollback reinstates them).
--   Step 9. NOTIFY pgrst to reload schema.
--
-- After rollback:
--   • Frontend SELECT queries will request distinct_reviewer_count but
--     get NULL (column absent). Fresh Face badges remain hidden — safe.
--   • BMP scores revert to last known pre-migration values from backup.
--     Scores will not reflect any reviews approved during the v3 window.
--
-- DO NOT execute production SQL until approved.
-- ══════════════════════════════════════════════════════════════════════════════

BEGIN;


-- ── Step 1: Verify backup table and data exist ───────────────────────────────
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name   = 'bmp_v3_migration_backup'
  ) THEN
    RAISE EXCEPTION
      'ROLLBACK ABORTED: Backup table bmp_v3_migration_backup does not exist. '
      'Run supabase_v3_preflight_backup.sql on this database before attempting rollback.';
  END IF;

  SELECT COUNT(*) INTO v_count FROM public.bmp_v3_migration_backup;
  IF v_count = 0 THEN
    RAISE EXCEPTION
      'ROLLBACK ABORTED: Backup table exists but contains no rows. '
      'Cannot restore from an empty backup.';
  END IF;

  RAISE NOTICE 'Step 1 PASS: backup table exists with % rows.', v_count;
END;
$$;


-- ── Step 2: Restore trainer BMP state from latest backup run ────────────────
DO $$
DECLARE
  v_latest_run  TIMESTAMPTZ;
  v_restored    INTEGER;
  v_total       INTEGER;
BEGIN
  SELECT MAX(backup_run) INTO v_latest_run
  FROM public.bmp_v3_migration_backup;

  SELECT COUNT(*) INTO v_total
  FROM public.bmp_v3_migration_backup
  WHERE backup_run = v_latest_run;

  UPDATE public.trainers t
  SET
    bmp_score           = b.bmp_score,
    is_trending         = b.is_trending,
    recent_review_count = b.recent_review_count,
    star_rating         = b.star_rating,
    review_count        = b.review_count
  FROM public.bmp_v3_migration_backup b
  WHERE b.trainer_id = t.id
    AND b.backup_run = v_latest_run;

  GET DIAGNOSTICS v_restored = ROW_COUNT;
  RAISE NOTICE 'Step 2: Restored % / % trainer rows from backup_run %.',
    v_restored, v_total, v_latest_run;

  IF v_restored <> v_total THEN
    RAISE WARNING 'Some trainers in the backup were not found in the trainers table '
      '(% missing). They may have been deleted after backup.', v_total - v_restored;
  END IF;
END;
$$;


-- ── Step 3: Drop distinct_reviewer_count column ──────────────────────────────
-- IF EXISTS prevents failure if the migration was only partially applied.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'trainers'
      AND column_name  = 'distinct_reviewer_count'
  ) THEN
    EXECUTE 'ALTER TABLE public.trainers DROP COLUMN distinct_reviewer_count';
    RAISE NOTICE 'Step 3: distinct_reviewer_count column dropped.';
  ELSE
    RAISE NOTICE 'Step 3: distinct_reviewer_count column not present — nothing to drop.';
  END IF;
END;
$$;


-- ── Step 4: Restore calculate_bmp_for_trainer ────────────────────────────────
-- Restores to the supabase_trending_v3.sql version.
-- Formula: 5@3.5★ Bayesian prior, no Model C floor, no anon cap,
-- no distinct_reviewer_count, trending counts all verified reviews (not deduped).
CREATE OR REPLACE FUNCTION calculate_bmp_for_trainer(p_trainer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_count    INTEGER;
  v_eff_count      INTEGER;
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
  v_reviews_7d     INTEGER;
  v_reviews_prev   INTEGER;
  v_is_trending    BOOLEAN;
BEGIN

  SELECT COUNT(*) INTO v_total_count
  FROM reviews
  WHERE trainer_id = p_trainer_id AND is_verified = TRUE;

  IF v_total_count = 0 THEN
    UPDATE trainers
    SET bmp_score = 0, is_trending = FALSE, recent_review_count = 0
    WHERE id = p_trainer_id;
    RETURN;
  END IF;

  -- Effective review count + sum (latest per client, plus anonymous)
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

  -- Quality: 5@3.5★ prior (pre-v3)
  v_smoothed_avg := (v_sum_ratings + 5.0 * 3.5) / (v_eff_count::FLOAT + 5.0);
  v_quality_pts  := LEAST((v_smoothed_avg / 5.0) * 70.0, 70.0);

  -- Confidence
  v_confidence_pts := LEAST(LN(v_eff_count::FLOAT + 1.0) / LN(51.0), 1.0) * 20.0;

  -- Momentum (pre-v3: no activity floor)
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

  v_bmp_score := ROUND((v_quality_pts + v_confidence_pts + v_momentum_pts)::NUMERIC, 1);

  -- Trending (pre-v3: counts ALL verified reviews, not deduped, no ≥3.5★ filter)
  SELECT COUNT(*) INTO v_reviews_7d
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '7 days';

  SELECT COUNT(*) INTO v_reviews_prev
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '28 days'
    AND created_at <  NOW() - INTERVAL '7 days';

  v_is_trending := (v_reviews_7d >= 2 AND v_reviews_prev >= 1);

  UPDATE trainers
  SET
    bmp_score           = v_bmp_score,
    is_trending         = v_is_trending,
    recent_review_count = v_reviews_7d
  WHERE id = p_trainer_id;

END;
$$;

GRANT EXECUTE ON FUNCTION calculate_bmp_for_trainer(UUID) TO service_role;
DO $$ BEGIN RAISE NOTICE 'Step 4: calculate_bmp_for_trainer restored to trending_v3 version.'; END; $$;


-- ── Step 5: Restore refresh_trending_status ──────────────────────────────────
-- Restores to supabase_trending_autoupdate.sql version.
-- Counts ALL verified reviews (not deduped, no ≥3.5★ filter).
CREATE OR REPLACE FUNCTION refresh_trending_status(p_trainer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviews_7d     INTEGER;
  v_reviews_7d_all INTEGER;
  v_reviews_prev   INTEGER;
  v_is_trending    BOOLEAN;
BEGIN
  SELECT COUNT(*) INTO v_reviews_7d
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '7 days';

  SELECT COUNT(*) INTO v_reviews_7d_all
  FROM reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '7 days';

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
    recent_review_count = v_reviews_7d_all
  WHERE id = p_trainer_id;
END;
$$;

GRANT EXECUTE ON FUNCTION refresh_trending_status(UUID) TO service_role;
DO $$ BEGIN RAISE NOTICE 'Step 5: refresh_trending_status restored to autoupdate version.'; END; $$;


-- ── Step 6: Restore get_own_trainer_profile ──────────────────────────────────
-- Restores to supabase_b1_get_own_trainer_profile.sql version.
-- Does NOT include distinct_reviewer_count in the JSONB output.
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

REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM anon;
GRANT  EXECUTE ON FUNCTION get_own_trainer_profile() TO authenticated;

DO $$ BEGIN RAISE NOTICE 'Step 6: get_own_trainer_profile restored to b1 version.'; END; $$;


-- ── Step 7: Restore pre-v3 trigger configuration ────────────────────────────
-- Migration Step 7 replaced zzz_on_review_bmp_update with a comprehensive
-- AFTER INSERT OR UPDATE OR DELETE trigger calling trigger_recalculate_bmp().
-- The original trigger fired only on UPDATE OF is_verified (FALSE→TRUE).
-- trigger_calculate_bmp_on_approve() was never dropped by the migration.
-- Restore it here, then drop the v3 trigger function.

DROP TRIGGER IF EXISTS zzz_on_review_bmp_update ON public.reviews;

CREATE TRIGGER zzz_on_review_bmp_update
  AFTER UPDATE OF is_verified ON public.reviews
  FOR EACH ROW
  WHEN (NEW.is_verified = TRUE AND OLD.is_verified IS DISTINCT FROM TRUE)
  EXECUTE FUNCTION public.trigger_calculate_bmp_on_approve();

-- trigger_recalculate_bmp() is now unreferenced; drop it to keep the schema clean.
-- If the trigger above is still pointing to it for any reason, DROP will fail safely
-- (it will error with "cannot drop because trigger depends on it") — investigate before retrying.
DROP FUNCTION IF EXISTS public.trigger_recalculate_bmp();

DO $$ BEGIN
  RAISE NOTICE 'Step 7: trigger zzz_on_review_bmp_update restored to AFTER UPDATE OF is_verified (FALSE→TRUE approvals only). trigger_recalculate_bmp() dropped.';
END; $$;


-- ── Step 8: Restore original bodies of legacy trigger functions ──────────────
-- Migration Step 8 replaced update_trainer_stats() and update_trainer_star_rating()
-- to remove their bmp_score writes and add is_verified = TRUE filters.
-- Rollback restores both functions to their original production bodies.
-- The triggers (on_review_approved, on_review_created, trg_update_star_rating)
-- are NOT touched — they remain active and call these restored functions.

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
  SELECT COALESCE(AVG(rating), 0), COUNT(*)
  INTO   _avg, _count
  FROM   reviews
  WHERE  trainer_id = NEW.trainer_id;

  UPDATE trainers
  SET star_rating  = _avg,
      review_count = _count,
      bmp_score    = LEAST(100, ROUND((_avg / 5.0) * 70 + LEAST(_count * 3, 30)))
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
BEGIN
  _trainer_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.trainer_id ELSE NEW.trainer_id END;

  SELECT COALESCE(AVG(rating), 0) INTO _avg
  FROM   reviews
  WHERE  trainer_id = _trainer_id;

  UPDATE trainers
  SET star_rating  = _avg,
      review_count = (SELECT COUNT(*) FROM reviews WHERE trainer_id = _trainer_id),
      bmp_score    = _avg * 20
  WHERE id = _trainer_id;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_trainer_star_rating() TO service_role;

DO $$ BEGIN
  RAISE NOTICE 'Step 8: update_trainer_stats() and update_trainer_star_rating() restored to original production bodies (bmp_score writes reinstated).';
END; $$;


-- ── Step 9: Reload PostgREST schema ──────────────────────────────────────────
NOTIFY pgrst, 'reload schema';

COMMIT;

DO $$ BEGIN
  RAISE NOTICE '══════════════════════════════════════════════════════════';
  RAISE NOTICE 'ROLLBACK COMPLETE. Review the notices above for any warnings.';
  RAISE NOTICE 'Verify trainer scores match pre-migration expectations:';
  RAISE NOTICE '  SELECT id, bmp_score, is_trending FROM trainers LIMIT 10;';
  RAISE NOTICE '══════════════════════════════════════════════════════════';
END; $$;
