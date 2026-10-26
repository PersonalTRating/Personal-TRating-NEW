-- =============================================================================
-- CoachCards — Test Environment Setup
-- File: supabase_test_environment_setup.sql
-- Target: CoachCards-Test (Free plan, empty Supabase project)
-- Purpose: Reproduce the pre-BMP-v3 CoachCards schema for isolated testing
--
-- RUN ORDER (in the CoachCards-Test SQL editor):
--   1. THIS FILE                         — full schema + synthetic data
--   2. supabase_v3_preflight_backup.sql  — snapshot pre-migration BMP state
--   3. supabase_bmp_v3_migration.sql     — the v3 migration under test
--   4. supabase_v3_tests.sql             — validation test suite
--   5. supabase_v3_rollback.sql          — only if rolling back is needed
--
-- WHAT THIS FILE CREATES:
--   Tables  : ranking_areas, cc_lad_to_county, clients, trainers, reviews,
--             notifications, trainer_private, bmp_v3_migration_backup
--   Indexes : 5 indexes (composite, partial)
--   Functions: 20 functions (pre-v3 BMP versions where required)
--   Triggers: zzz_on_review_bmp_update, trainers_protect_geo
--   Grants  : per-role execute and column grants
--   RLS     : policies for trainers, notifications, trainer_private, clients
--   Data    : 5 synthetic ranking areas + 3 synthetic trainers (no real data)
--
-- CANNOT BE RELIABLY RECONSTRUCTED FROM REPOSITORY:
--   * Original CREATE TABLE statements for trainers and reviews — these were
--     created directly in the Supabase dashboard, not via a migration file.
--     Columns are reconstructed from all ALTER TABLE statements and function
--     parameter lists found across the migration files.
--   * Full geo reference data (supabase_geo_02_ranking_areas.sql: 118 rows;
--     supabase_geo_03_lad_crosswalk.sql: hundreds of rows). Replaced here
--     with 5 minimal synthetic rows sufficient for BMP tests.
--   * Production RLS SELECT policy on trainers — the policy name and exact
--     USING clause are confirmed present [LIVE] in audit but not in any file.
--     A functionally equivalent policy is provided below; verify before use.
--   * supabase_review_approval_notification_trigger.sql — file not read;
--     notification trigger (if separate from inline function logic) is absent.
--   * cc_protect_geo_columns() exact body — reconstructed from architecture
--     documentation in supabase_b3_column_grants.sql (architecture note G).
--
-- SECURITY:
--   * SYNTHETIC DATA ONLY — no real trainer records, postcodes, or credentials.
--   * B3 column-level grants NOT applied (file marked "NOT YET EXECUTED").
--     Apply supabase_b3_column_grants.sql separately after this file if needed.
--   * auth.users entries for test trainers are NOT created; tests use
--     SET LOCAL session_replication_role = 'replica' to bypass that FK.
--
-- IDEMPOTENT: Uses IF NOT EXISTS / CREATE OR REPLACE throughout.
-- =============================================================================


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 1: EXTENSIONS
-- ═════════════════════════════════════════════════════════════════════════════
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";  -- belt-and-suspenders for UUID


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 2: REFERENCE TABLES
-- Created first because trainers.cc_local_area FK references ranking_areas.id
-- ═════════════════════════════════════════════════════════════════════════════

-- 2a. Geographical ranking areas
CREATE TABLE IF NOT EXISTS public.ranking_areas (
  id           TEXT        NOT NULL,
  area_type    TEXT        NOT NULL,   -- 'uk', 'country', 'local'
  country      TEXT,
  display_name TEXT        NOT NULL,
  slug         TEXT        NOT NULL,
  parent_id    TEXT        REFERENCES public.ranking_areas(id),
  ons_code     TEXT,
  sort_order   INTEGER     DEFAULT 0,
  is_active    BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (id),
  UNIQUE (slug)
);

-- 2b. LAD-to-county crosswalk (England + Northern Ireland)
CREATE TABLE IF NOT EXISTS public.cc_lad_to_county (
  admin_district   TEXT    NOT NULL,
  ranking_area_id  TEXT    REFERENCES public.ranking_areas(id),
  ons_lad_code     TEXT,
  area_category    TEXT,
  notes            TEXT,
  verified         BOOLEAN DEFAULT FALSE,
  PRIMARY KEY (admin_district)
);


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 3: CORE TABLES
-- ═════════════════════════════════════════════════════════════════════════════

-- 3a. Clients (reviewer accounts)
-- auth.users FK omitted here; enforced in production but bypassed in tests
-- via session_replication_role = 'replica'.
CREATE TABLE IF NOT EXISTS public.clients (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL UNIQUE,  -- references auth.users(id)
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3b. Trainers
-- Reconstructed from all ALTER TABLE migrations applied in production order.
-- Column order reflects chronological addition; all added via ALTER TABLE IF NOT EXISTS.
CREATE TABLE IF NOT EXISTS public.trainers (
  -- Core identity (original schema)
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID,                         -- references auth.users(id)
  name             TEXT,
  username         TEXT        UNIQUE,
  business_name    TEXT,
  city             TEXT,
  location         TEXT,
  bio              TEXT,
  intro_message    TEXT,
  specialty        TEXT,
  cert             TEXT,
  bmp_score        NUMERIC     DEFAULT 0,
  star_rating      NUMERIC     DEFAULT 0,
  review_count     INTEGER     DEFAULT 0,
  avatar_url       TEXT,
  avatar_initials  TEXT,
  avatar_bg        TEXT,
  avatar_color     TEXT,
  postcode         TEXT,                         -- legacy field (dashboard use)
  is_active        BOOLEAN     DEFAULT FALSE,
  gyms             JSONB       DEFAULT '[]',
  hero_theme       TEXT,

  -- Added by supabase_bmp_v2.sql
  is_trending          BOOLEAN DEFAULT FALSE,
  rank_history         JSONB   DEFAULT '[]',

  -- Added by supabase_bmp_v2_trending_patch.sql
  recent_review_count  INTEGER DEFAULT 0,

  -- Added by supabase_coaching_type.sql
  coaching_type        TEXT,                    -- 'online','in_person','hybrid' or NULL

  -- Added by supabase_social_links.sql
  social_facebook      TEXT,
  social_instagram     TEXT,
  social_whatsapp      TEXT,
  social_email         TEXT,
  accepts_bookings     BOOLEAN DEFAULT FALSE,
  booking_url          TEXT,

  -- Added by supabase_geo_01_schema.sql
  cc_postcode              TEXT,               -- retired; move triggers block new writes
  cc_country               TEXT,
  cc_local_area            TEXT REFERENCES public.ranking_areas(id),
  location_confirmed       BOOLEAN DEFAULT FALSE,
  location_confirmed_at    TIMESTAMPTZ,
  location_source          TEXT,
  location_cooldown_until  TIMESTAMPTZ,
  location_mapping_version TEXT,

  -- Added by supabase_ranking_visibility.sql
  ranking_visibility  TEXT NOT NULL DEFAULT 'all'
    CHECK (ranking_visibility IN ('all', 'uk_country', 'uk_only'))

  -- NOTE: distinct_reviewer_count is NOT included here.
  -- It is added by supabase_bmp_v3_migration.sql (Step 1).
);

-- 3c. Reviews
CREATE TABLE IF NOT EXISTS public.reviews (
  -- Core columns (original schema)
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id           UUID        NOT NULL REFERENCES public.trainers(id) ON DELETE CASCADE,
  client_id            UUID        REFERENCES public.clients(id),   -- NULL = anonymous
  reviewer_name        TEXT,
  reviewer_initials    TEXT,
  reviewer_avatar_bg   TEXT,
  reviewer_avatar_color TEXT,
  reviewer_location    TEXT,
  rating               FLOAT8,
  review_text          TEXT,
  is_verified          BOOLEAN     NOT NULL DEFAULT FALSE,
  is_anonymous         BOOLEAN     NOT NULL DEFAULT FALSE,
  approval_token       UUID        DEFAULT gen_random_uuid(),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- Added by supabase_appeal_fn.sql
  appeal_token         UUID        DEFAULT gen_random_uuid(),
  appeal_reason        TEXT,
  appeal_status        TEXT,

  -- Added by supabase_appeal_update.sql
  resolution_notes     TEXT,

  -- Added by supabase_notification_v2.sql
  notification_claimed_at    TIMESTAMPTZ,
  notification_sent_at       TIMESTAMPTZ,
  notification_attempt_count INTEGER NOT NULL DEFAULT 0
);


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 4: SUPPORT TABLES
-- ═════════════════════════════════════════════════════════════════════════════

-- 4a. In-app notifications (supabase_notifications.sql)
CREATE TABLE IF NOT EXISTS public.notifications (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL,
  type       TEXT        NOT NULL DEFAULT 'review_approved',
  title      TEXT,
  body       TEXT,
  link       TEXT,
  is_read    BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4b. Private trainer data — postcode stored here post-migration
--     (supabase_postcode_privacy.sql)
CREATE TABLE IF NOT EXISTS public.trainer_private (
  trainer_id  UUID        PRIMARY KEY REFERENCES public.trainers(id) ON DELETE CASCADE,
  cc_postcode TEXT        NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4c. BMP migration backup table (supabase_v3_preflight_backup.sql)
--     Created here so it exists before the backup script runs.
--     The backup script uses CREATE TABLE IF NOT EXISTS so it is safe to pre-create.
CREATE TABLE IF NOT EXISTS public.bmp_v3_migration_backup (
  backup_run                  TIMESTAMPTZ NOT NULL,
  trainer_id                  UUID        NOT NULL,
  bmp_score                   NUMERIC,
  is_trending                 BOOLEAN,
  recent_review_count         INTEGER,
  distinct_reviewer_count_pre INTEGER,
  star_rating                 NUMERIC,
  review_count                INTEGER,
  PRIMARY KEY (backup_run, trainer_id)
);

COMMENT ON TABLE public.bmp_v3_migration_backup IS
  'Pre-migration score snapshot for BMP v3 rollback testing.';


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 5: INDEXES
-- ═════════════════════════════════════════════════════════════════════════════

-- Geo indexes on trainers (supabase_geo_01_schema.sql)
CREATE INDEX IF NOT EXISTS idx_trainers_country_bmp
  ON public.trainers (cc_country, bmp_score DESC)
  WHERE is_active = TRUE AND location_confirmed = TRUE;

CREATE INDEX IF NOT EXISTS idx_trainers_local_bmp
  ON public.trainers (cc_local_area, bmp_score DESC)
  WHERE is_active = TRUE AND location_confirmed = TRUE;

-- Reviews indexes (supabase_30day_rule.sql)
CREATE UNIQUE INDEX IF NOT EXISTS uq_one_pending_per_client_trainer
  ON public.reviews (client_id, trainer_id)
  WHERE is_verified = FALSE AND client_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_reviews_trainer_client_created
  ON public.reviews (trainer_id, client_id, created_at DESC)
  WHERE is_verified = TRUE AND client_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_reviews_client_trainer_pending
  ON public.reviews (client_id, trainer_id)
  WHERE is_verified = FALSE AND client_id IS NOT NULL;

-- Notifications index (supabase_notifications.sql)
CREATE INDEX IF NOT EXISTS idx_notifications_user_id
  ON public.notifications (user_id);


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 6: ROW LEVEL SECURITY — ENABLE
-- ═════════════════════════════════════════════════════════════════════════════

ALTER TABLE public.trainers       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clients        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.trainer_private ENABLE ROW LEVEL SECURITY;


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 7: FUNCTIONS
-- Ordered by dependency: helpers first, then BMP, then review flow, then profile
-- ═════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- 7a. Geo trigger function — guards geo columns from direct writes
--     Reconstructed from architecture documentation in supabase_b3_column_grants.sql
--     (architecture note G) and supabase_postcode_privacy.sql.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.cc_protect_geo_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
  -- Check A: cc_postcode is retired — reject any UPDATE that would set it non-NULL
  IF NEW.cc_postcode IS NOT NULL THEN
    RAISE EXCEPTION
      'cc_postcode is retired. Use cc_confirm_location_atomic() to confirm location. '
      'Direct writes to cc_postcode are not permitted.';
  END IF;

  -- Check B: geo columns may only be written by postgres/service_role/supabase_admin
  IF (
    NEW.cc_country               IS DISTINCT FROM OLD.cc_country OR
    NEW.cc_local_area            IS DISTINCT FROM OLD.cc_local_area OR
    NEW.location_confirmed       IS DISTINCT FROM OLD.location_confirmed OR
    NEW.location_confirmed_at    IS DISTINCT FROM OLD.location_confirmed_at OR
    NEW.location_source          IS DISTINCT FROM OLD.location_source OR
    NEW.location_cooldown_until  IS DISTINCT FROM OLD.location_cooldown_until OR
    NEW.location_mapping_version IS DISTINCT FROM OLD.location_mapping_version
  ) AND current_user NOT IN ('postgres', 'service_role', 'supabase_admin') THEN
    RAISE EXCEPTION
      'Geo columns may only be updated via cc_confirm_location_atomic(). '
      'Role % is not authorised for direct geo-column writes.', current_user;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.cc_protect_geo_columns() IS
  'BEFORE UPDATE trigger on trainers. Blocks retired cc_postcode writes and '
  'restricts geo-column updates to postgres/service_role/supabase_admin only.';


-- ─────────────────────────────────────────────────────────────────────────────
-- 7b. BMP functions — PRE-V3 VERSIONS (trending_v3 state)
--     These are the exact function bodies the v3 migration will upgrade.
--     Bodies match supabase_v3_rollback.sql Steps 4 and 5 (confirmed pre-v3).
-- ─────────────────────────────────────────────────────────────────────────────

-- calculate_bmp_for_trainer — pre-v3 (5@3.5★ prior, DISTINCT ON dedup,
-- two-window trending on ALL verified reviews with no ≥3.5★ filter)
CREATE OR REPLACE FUNCTION public.calculate_bmp_for_trainer(p_trainer_id UUID)
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
  FROM public.reviews
  WHERE trainer_id = p_trainer_id AND is_verified = TRUE;

  IF v_total_count = 0 THEN
    UPDATE public.trainers
    SET bmp_score = 0, is_trending = FALSE, recent_review_count = 0
    WHERE id = p_trainer_id;
    RETURN;
  END IF;

  -- Effective review set: latest per authenticated client + all anonymous
  WITH latest_per_client AS (
    SELECT DISTINCT ON (client_id)
      id, rating
    FROM public.reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NOT NULL
    ORDER BY client_id, created_at DESC
  ),
  anon_reviews AS (
    SELECT id, rating
    FROM public.reviews
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

  -- Momentum (pre-v3: ≥3.5★ filter on effective reviews, three time windows)
  WITH latest_per_client AS (
    SELECT DISTINCT ON (client_id)
      id, rating, created_at
    FROM public.reviews
    WHERE trainer_id = p_trainer_id
      AND is_verified = TRUE
      AND client_id IS NOT NULL
    ORDER BY client_id, created_at DESC
  ),
  anon_reviews AS (
    SELECT id, rating, created_at
    FROM public.reviews
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

  -- Trending: ALL verified reviews (no dedup, no ≥3.5★ filter), two windows
  SELECT COUNT(*) INTO v_reviews_7d
  FROM public.reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '7 days';

  SELECT COUNT(*) INTO v_reviews_prev
  FROM public.reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '28 days'
    AND created_at <  NOW() - INTERVAL '7 days';

  v_is_trending := (v_reviews_7d >= 2 AND v_reviews_prev >= 1);

  UPDATE public.trainers
  SET
    bmp_score           = v_bmp_score,
    is_trending         = v_is_trending,
    recent_review_count = v_reviews_7d
  WHERE id = p_trainer_id;

END;
$$;

GRANT EXECUTE ON FUNCTION public.calculate_bmp_for_trainer(UUID) TO service_role;


-- refresh_trending_status — pre-v3 (plain COUNT, no dedup, no ≥3.5★ filter)
CREATE OR REPLACE FUNCTION public.refresh_trending_status(p_trainer_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviews_7d     INTEGER;
  v_reviews_prev   INTEGER;
  v_is_trending    BOOLEAN;
BEGIN
  SELECT COUNT(*) INTO v_reviews_7d
  FROM public.reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '7 days';

  SELECT COUNT(*) INTO v_reviews_prev
  FROM public.reviews
  WHERE trainer_id = p_trainer_id
    AND is_verified = TRUE
    AND created_at >= NOW() - INTERVAL '28 days'
    AND created_at <  NOW() - INTERVAL '7 days';

  v_is_trending := (v_reviews_7d >= 2 AND v_reviews_prev >= 1);

  UPDATE public.trainers
  SET
    is_trending         = v_is_trending,
    recent_review_count = v_reviews_7d
  WHERE id = p_trainer_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.refresh_trending_status(UUID) TO service_role;


-- refresh_all_trending — batch wrapper
CREATE OR REPLACE FUNCTION public.refresh_all_trending()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  t_id UUID;
BEGIN
  FOR t_id IN SELECT id FROM public.trainers WHERE is_active = TRUE
  LOOP
    PERFORM public.refresh_trending_status(t_id);
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.refresh_all_trending() TO service_role;


-- trigger function for BMP recalc on review approval
CREATE OR REPLACE FUNCTION public.trigger_calculate_bmp_on_approve()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM public.calculate_bmp_for_trainer(NEW.trainer_id);
  RETURN NEW;
END;
$$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 7c. Review flow functions
-- ─────────────────────────────────────────────────────────────────────────────

-- check_review_eligibility — secure single-param version (supabase_secure_review_submit.sql)
-- Derives client from auth.uid() server-side; p_client_id not exposed to client.
CREATE OR REPLACE FUNCTION public.check_review_eligibility(p_trainer_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_client_id     UUID;
  v_review_at     TIMESTAMPTZ;
  v_next_eligible TIMESTAMPTZ;
BEGIN
  SELECT id INTO v_client_id
  FROM public.clients
  WHERE user_id = auth.uid()
  LIMIT 1;

  IF v_client_id IS NULL THEN
    RETURN jsonb_build_object('status', 'eligible');
  END IF;

  SELECT created_at INTO v_review_at
  FROM public.reviews
  WHERE client_id  = v_client_id
    AND trainer_id = p_trainer_id
    AND is_verified = FALSE
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object('status', 'pending_review');
  END IF;

  SELECT created_at INTO v_review_at
  FROM public.reviews
  WHERE client_id  = v_client_id
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

GRANT EXECUTE ON FUNCTION public.check_review_eligibility(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_review_eligibility(UUID) TO anon;


-- submit_review_for_client — secure version (supabase_secure_review_submit.sql)
CREATE OR REPLACE FUNCTION public.submit_review_for_client(
  p_trainer_id            UUID,
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
SET search_path = public, auth
AS $$
DECLARE
  v_client_id     UUID;
  v_review_at     TIMESTAMPTZ;
  v_next_eligible TIMESTAMPTZ;
  v_review_id     UUID;
BEGIN
  SELECT id INTO v_client_id
  FROM public.clients
  WHERE user_id = auth.uid()
  LIMIT 1;

  IF v_client_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(
      hashtext(v_client_id::text),
      hashtext(p_trainer_id::text)
    );

    SELECT created_at INTO v_review_at
    FROM public.reviews
    WHERE client_id  = v_client_id
      AND trainer_id = p_trainer_id
      AND is_verified = FALSE
    ORDER BY created_at DESC LIMIT 1;

    IF FOUND THEN
      RETURN jsonb_build_object('status', 'pending_review');
    END IF;

    SELECT created_at INTO v_review_at
    FROM public.reviews
    WHERE client_id  = v_client_id
      AND trainer_id = p_trainer_id
      AND is_verified = TRUE
    ORDER BY created_at DESC LIMIT 1;

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

  INSERT INTO public.reviews (
    trainer_id, client_id,
    reviewer_name, reviewer_initials,
    reviewer_avatar_bg, reviewer_avatar_color, reviewer_location,
    rating, review_text, is_verified, is_anonymous, approval_token
  )
  VALUES (
    p_trainer_id, v_client_id,
    p_reviewer_name, p_reviewer_initials,
    p_reviewer_avatar_bg, p_reviewer_avatar_color, p_reviewer_location,
    p_rating, p_review_text, FALSE, p_is_anonymous, p_approval_token
  )
  RETURNING id INTO v_review_id;

  RETURN jsonb_build_object('status', 'ok', 'review_id', v_review_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_review_for_client(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,FLOAT8,TEXT,BOOLEAN,UUID)
  TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_review_for_client(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,FLOAT8,TEXT,BOOLEAN,UUID)
  TO anon;


-- approve_review_by_token (supabase_approve_review_fn.sql + supabase_notifications.sql)
CREATE OR REPLACE FUNCTION public.approve_review_by_token(p_token TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_review       public.reviews%ROWTYPE;
  v_trainer_uid  UUID;
  v_client_uid   UUID;
BEGIN
  SELECT * INTO v_review
  FROM public.reviews
  WHERE approval_token = p_token::UUID AND is_verified = FALSE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'not_found');
  END IF;

  UPDATE public.reviews
  SET is_verified = TRUE
  WHERE id = v_review.id;

  UPDATE public.trainers
  SET
    star_rating  = (SELECT COALESCE(AVG(rating), 0)
                    FROM public.reviews
                    WHERE trainer_id = v_review.trainer_id AND is_verified = TRUE),
    review_count = (SELECT COUNT(*)
                    FROM public.reviews
                    WHERE trainer_id = v_review.trainer_id AND is_verified = TRUE)
  WHERE id = v_review.trainer_id
  RETURNING user_id INTO v_trainer_uid;

  -- Insert in-app notification if the trainer has a user account
  IF v_trainer_uid IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, type, title, body, link)
    VALUES (
      v_trainer_uid,
      'review_approved',
      'New review approved',
      'A new review has been approved and is now live on your profile.',
      '/dashboard'
    );
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'review_id', v_review.id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_review_by_token(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.approve_review_by_token(TEXT) TO authenticated;


-- reject_review_by_token (supabase_reject_review_fn.sql)
CREATE OR REPLACE FUNCTION public.reject_review_by_token(p_token TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.reviews
  WHERE approval_token = p_token::UUID AND is_verified = FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_review_by_token(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.reject_review_by_token(TEXT) TO authenticated;


-- submit_review_appeal (supabase_appeal_update.sql version)
CREATE OR REPLACE FUNCTION public.submit_review_appeal(p_review_id UUID, p_reason TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_review     public.reviews%ROWTYPE;
  v_trainer_id UUID;
  v_token      UUID;
BEGIN
  SELECT * INTO v_review FROM public.reviews WHERE id = p_review_id AND is_verified = TRUE;
  IF NOT FOUND THEN RETURN json_build_object('error', 'not_found'); END IF;

  SELECT id INTO v_trainer_id
  FROM public.trainers WHERE id = v_review.trainer_id AND user_id = auth.uid();
  IF NOT FOUND THEN RETURN json_build_object('error', 'unauthorized'); END IF;

  IF v_review.appeal_status IS NOT NULL THEN
    RETURN json_build_object('error', 'already_appealed');
  END IF;

  v_token := gen_random_uuid();

  UPDATE public.reviews
  SET appeal_reason = p_reason,
      appeal_status = 'pending',
      appeal_token  = v_token
  WHERE id = p_review_id;

  RETURN json_build_object(
    'token',         v_token,
    'reviewer_name', v_review.reviewer_name,
    'review_text',   v_review.review_text,
    'rating',        v_review.rating
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.submit_review_appeal(UUID, TEXT) TO authenticated;


-- remove_appealed_review (supabase_appeal_update.sql version — 2-param)
CREATE OR REPLACE FUNCTION public.remove_appealed_review(
  p_token UUID,
  p_notes TEXT DEFAULT ''
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trainer_id      UUID;
  v_reviewer_name   TEXT;
  v_trainer_user_id UUID;
BEGIN
  SELECT trainer_id, reviewer_name INTO v_trainer_id, v_reviewer_name
  FROM public.reviews WHERE appeal_token = p_token AND appeal_status = 'pending';
  IF NOT FOUND THEN RETURN 'not_found'; END IF;

  SELECT user_id INTO v_trainer_user_id FROM public.trainers WHERE id = v_trainer_id;

  DELETE FROM public.reviews WHERE appeal_token = p_token;

  UPDATE public.trainers SET
    star_rating  = (SELECT COALESCE(AVG(rating), 0)
                    FROM public.reviews WHERE trainer_id = v_trainer_id AND is_verified = TRUE),
    review_count = (SELECT COUNT(*)
                    FROM public.reviews WHERE trainer_id = v_trainer_id AND is_verified = TRUE)
  WHERE id = v_trainer_id;

  IF v_trainer_user_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, type, title, body, link)
    VALUES (
      v_trainer_user_id, 'appeal_approved',
      'Appeal successful — review removed ✅',
      CASE WHEN p_notes != ''
           THEN 'The review has been removed from your profile. Admin note: ' || p_notes
           ELSE 'The review has been removed from your profile and your BMP score has been updated.'
      END,
      '/dashboard'
    );
  END IF;

  RETURN v_reviewer_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_appealed_review(UUID, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.remove_appealed_review(UUID, TEXT) TO authenticated;


-- uphold_appealed_review (supabase_appeal_update.sql version — 2-param)
CREATE OR REPLACE FUNCTION public.uphold_appealed_review(
  p_token UUID,
  p_notes TEXT DEFAULT ''
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_reviewer_name   TEXT;
  v_trainer_id      UUID;
  v_trainer_user_id UUID;
BEGIN
  UPDATE public.reviews
  SET appeal_status    = 'upheld',
      resolution_notes = p_notes
  WHERE appeal_token = p_token AND appeal_status = 'pending'
  RETURNING reviewer_name, trainer_id INTO v_reviewer_name, v_trainer_id;

  IF NOT FOUND THEN RETURN 'not_found'; END IF;

  SELECT user_id INTO v_trainer_user_id FROM public.trainers WHERE id = v_trainer_id;

  IF v_trainer_user_id IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, type, title, body, link)
    VALUES (
      v_trainer_user_id, 'appeal_declined',
      'Appeal outcome — review remains live',
      CASE WHEN p_notes != ''
           THEN 'After review, your appeal was not upheld. Admin note: ' || p_notes
           ELSE 'After review, your appeal was not upheld. The review will remain on your profile.'
      END,
      '/dashboard'
    );
  END IF;

  RETURN v_reviewer_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.uphold_appealed_review(UUID, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.uphold_appealed_review(UUID, TEXT) TO authenticated;


-- snapshot_weekly_ranks (supabase_bmp_v2.sql)
CREATE OR REPLACE FUNCTION public.snapshot_weekly_ranks()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.trainers t
  SET rank_history = (
    SELECT COALESCE(
      jsonb_agg(entry ORDER BY (entry->>'week')::DATE DESC),
      '[]'::jsonb
    )
    FROM (
      SELECT jsonb_array_elements(rank_history) AS entry
      FROM public.trainers WHERE id = t.id
      UNION ALL
      SELECT jsonb_build_object(
        'week',  DATE_TRUNC('week', NOW())::DATE,
        'rank',  (SELECT COUNT(*) + 1 FROM public.trainers
                  WHERE bmp_score > t.bmp_score AND is_active = TRUE)
      )
    ) sub
    LIMIT 52
  )
  WHERE is_active = TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.snapshot_weekly_ranks() TO service_role;


-- ─────────────────────────────────────────────────────────────────────────────
-- 7d. Notification functions — v2 (supabase_notification_v2.sql)
-- ─────────────────────────────────────────────────────────────────────────────

-- claim_approval_notification (admin path — by review UUID)
CREATE OR REPLACE FUNCTION public.claim_approval_notification(p_review_id UUID)
RETURNS TABLE(
  reviewer_email TEXT,
  reviewer_name  TEXT,
  trainer_name   TEXT,
  trainer_id     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_client_id UUID;
  v_user_id   UUID;
BEGIN
  UPDATE public.reviews
  SET    notification_claimed_at    = NOW(),
         notification_attempt_count = notification_attempt_count + 1
  WHERE  id                         = p_review_id
    AND  is_verified                = TRUE
    AND  client_id                  IS NOT NULL
    AND  notification_sent_at       IS NULL
    AND  (notification_claimed_at   IS NULL
          OR notification_claimed_at < NOW() - INTERVAL '5 minutes')
  RETURNING client_id INTO v_client_id;

  IF NOT FOUND THEN RETURN; END IF;

  SELECT c.user_id INTO v_user_id
  FROM public.clients c WHERE c.id = v_client_id;

  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    u.email::TEXT  AS reviewer_email,
    rv.reviewer_name,
    t.name::TEXT   AS trainer_name,
    t.id::TEXT     AS trainer_id
  FROM   public.reviews   rv
  JOIN   public.trainers  t  ON t.id = rv.trainer_id
  JOIN   auth.users       u  ON u.id = v_user_id
  WHERE  rv.id = p_review_id;
END;
$$;
-- No GRANT: callable only via service_role / postgres


-- claim_approval_notification_by_token (email-link path)
CREATE OR REPLACE FUNCTION public.claim_approval_notification_by_token(p_token TEXT)
RETURNS TABLE(
  reviewer_email TEXT,
  reviewer_name  TEXT,
  trainer_name   TEXT,
  trainer_id     TEXT,
  review_id      TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_review_id UUID;
  v_client_id UUID;
  v_user_id   UUID;
BEGIN
  UPDATE public.reviews
  SET    notification_claimed_at    = NOW(),
         notification_attempt_count = notification_attempt_count + 1
  WHERE  approval_token             = p_token::UUID
    AND  is_verified                = TRUE
    AND  client_id                  IS NOT NULL
    AND  notification_sent_at       IS NULL
    AND  (notification_claimed_at   IS NULL
          OR notification_claimed_at < NOW() - INTERVAL '5 minutes')
  RETURNING id, client_id INTO v_review_id, v_client_id;

  IF NOT FOUND THEN RETURN; END IF;

  SELECT c.user_id INTO v_user_id
  FROM public.clients c WHERE c.id = v_client_id;

  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    u.email::TEXT     AS reviewer_email,
    rv.reviewer_name,
    t.name::TEXT      AS trainer_name,
    t.id::TEXT        AS trainer_id,
    v_review_id::TEXT AS review_id
  FROM   public.reviews  rv
  JOIN   public.trainers t  ON t.id = rv.trainer_id
  JOIN   auth.users      u  ON u.id = v_user_id
  WHERE  rv.id = v_review_id;
END;
$$;


-- confirm_approval_notification (seals notification after Resend 2xx)
CREATE OR REPLACE FUNCTION public.confirm_approval_notification(p_review_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.reviews
  SET    notification_sent_at    = NOW(),
         notification_claimed_at = NOW()
  WHERE  id = p_review_id;
END;
$$;


-- claim_notification_retry_batch (scheduled retry function)
CREATE OR REPLACE FUNCTION public.claim_notification_retry_batch(
  p_max_retries INT DEFAULT 5,
  p_batch_size  INT DEFAULT 10
)
RETURNS TABLE(
  review_id      TEXT,
  reviewer_email TEXT,
  reviewer_name  TEXT,
  trainer_name   TEXT,
  trainer_id     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH claimed AS (
    UPDATE public.reviews
    SET    notification_claimed_at    = NOW(),
           notification_attempt_count = notification_attempt_count + 1
    WHERE  id IN (
      SELECT id FROM public.reviews
      WHERE  is_verified             = TRUE
        AND  client_id               IS NOT NULL
        AND  notification_sent_at    IS NULL
        AND  notification_claimed_at IS NOT NULL
        AND  notification_claimed_at < NOW() - INTERVAL '5 minutes'
        AND  notification_attempt_count < p_max_retries
      ORDER BY notification_claimed_at
      LIMIT  p_batch_size
      FOR UPDATE SKIP LOCKED
    )
    RETURNING id, client_id
  ),
  with_users AS (
    SELECT cl.id, c.user_id
    FROM   claimed cl
    JOIN   public.clients c ON c.id = cl.client_id
  )
  SELECT
    cl.id::TEXT      AS review_id,
    u.email::TEXT    AS reviewer_email,
    rv.reviewer_name,
    t.name::TEXT     AS trainer_name,
    t.id::TEXT       AS trainer_id
  FROM   claimed       cl
  JOIN   public.reviews   rv ON rv.id = cl.id
  JOIN   public.trainers  t  ON t.id  = rv.trainer_id
  JOIN   with_users    wu ON wu.id = cl.id
  JOIN   auth.users    u  ON u.id  = wu.user_id;
END;
$$;
-- No GRANT: callable only via service_role / postgres


-- ─────────────────────────────────────────────────────────────────────────────
-- 7e. Profile and ranking functions
-- ─────────────────────────────────────────────────────────────────────────────

-- get_own_trainer_profile — pre-v3 version with ranking_visibility, WITHOUT distinct_reviewer_count
-- (supabase_ranking_visibility_rpc_patch.sql — applied before v3)
CREATE OR REPLACE FUNCTION public.get_own_trainer_profile()
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
    'location_cooldown_until', t.location_cooldown_until,
    'ranking_visibility',      t.ranking_visibility
  )
  FROM   public.trainers t
  WHERE  t.user_id = auth.uid()
  LIMIT  1;
$$;

REVOKE EXECUTE ON FUNCTION public.get_own_trainer_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_own_trainer_profile() FROM anon;
GRANT  EXECUTE ON FUNCTION public.get_own_trainer_profile() TO authenticated;

COMMENT ON FUNCTION public.get_own_trainer_profile() IS
  'Pre-v3 version: no distinct_reviewer_count. Returns authenticated trainer''s '
  'own profile as JSONB. SECURITY DEFINER bypasses B3 column grants.';


-- cc_confirm_location_atomic (supabase_postcode_privacy.sql)
CREATE OR REPLACE FUNCTION public.cc_confirm_location_atomic(
  p_trainer_id      UUID,
  p_postcode        TEXT,
  p_cc_country      TEXT,
  p_cc_local_area   TEXT,
  p_source          TEXT,
  p_confirmed_at    TIMESTAMPTZ,
  p_cooldown_until  TIMESTAMPTZ,
  p_mapping_version TEXT DEFAULT 'ONS-2023-12'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_rows         INT;
  v_cooldown_end TIMESTAMPTZ;
BEGIN
  UPDATE public.trainers
  SET
    cc_country               = p_cc_country,
    cc_local_area            = p_cc_local_area,
    location_confirmed       = TRUE,
    location_confirmed_at    = p_confirmed_at,
    location_source          = p_source,
    location_cooldown_until  = p_cooldown_until,
    location_mapping_version = p_mapping_version
  WHERE id = p_trainer_id
    AND (
      location_confirmed      = FALSE
      OR location_cooldown_until IS NULL
      OR location_cooldown_until < NOW()
    );

  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows = 0 THEN
    SELECT location_cooldown_until INTO v_cooldown_end
    FROM public.trainers WHERE id = p_trainer_id;
    RETURN jsonb_build_object(
      'success',        FALSE,
      'error',          'cooldown_active',
      'cooldown_until', v_cooldown_end
    );
  END IF;

  INSERT INTO public.trainer_private (trainer_id, cc_postcode, updated_at)
  VALUES (p_trainer_id, p_postcode, p_confirmed_at)
  ON CONFLICT (trainer_id) DO UPDATE
    SET cc_postcode = EXCLUDED.cc_postcode,
        updated_at  = EXCLUDED.updated_at;

  RETURN jsonb_build_object('success', TRUE);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.cc_confirm_location_atomic(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.cc_confirm_location_atomic(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.cc_confirm_location_atomic(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.cc_confirm_location_atomic(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT) TO service_role;


-- resolve_postcode_area (supabase_geo_04_functions.sql)
CREATE OR REPLACE FUNCTION public.resolve_postcode_area(
  p_admin_county   TEXT,
  p_admin_district TEXT,
  p_country        TEXT
)
RETURNS TABLE(cc_country TEXT, local_area_id TEXT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_local TEXT;
BEGIN
  cc_country := p_country;
  v_local    := NULL;

  CASE p_country
    WHEN 'Scotland' THEN
      SELECT id INTO v_local
      FROM public.ranking_areas
      WHERE display_name = p_admin_district
        AND area_type    = 'local'
        AND country      = 'Scotland'
        AND is_active    = TRUE;

    WHEN 'Wales' THEN
      SELECT id INTO v_local
      FROM public.ranking_areas
      WHERE display_name = p_admin_district
        AND area_type    = 'local'
        AND country      = 'Wales'
        AND is_active    = TRUE;

    WHEN 'Northern Ireland' THEN
      SELECT ranking_area_id INTO v_local
      FROM public.cc_lad_to_county
      WHERE admin_district = p_admin_district;

    WHEN 'England' THEN
      IF p_admin_county IS NOT NULL AND p_admin_county <> '' THEN
        SELECT id INTO v_local
        FROM public.ranking_areas
        WHERE display_name = p_admin_county
          AND area_type    = 'local'
          AND country      = 'England'
          AND is_active    = TRUE;
      END IF;
      IF v_local IS NULL THEN
        SELECT ranking_area_id INTO v_local
        FROM public.cc_lad_to_county
        WHERE admin_district = p_admin_district;
      END IF;

    ELSE
      cc_country := NULL;
  END CASE;

  local_area_id := v_local;
  RETURN NEXT;
END;
$$;


-- get_trainer_ranks (supabase_geo_04_functions.sql)
CREATE OR REPLACE FUNCTION public.get_trainer_ranks(p_trainer_id UUID)
RETURNS TABLE(uk_rank INT, country_rank INT, local_rank INT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_bmp       NUMERIC;
  v_country   TEXT;
  v_local     TEXT;
  v_confirmed BOOLEAN;
BEGIN
  SELECT bmp_score, cc_country, cc_local_area, location_confirmed
  INTO   v_bmp,     v_country,  v_local,       v_confirmed
  FROM   public.trainers
  WHERE  id = p_trainer_id;

  IF NOT FOUND THEN RETURN; END IF;

  SELECT COUNT(*)::INT + 1 INTO uk_rank
  FROM   public.trainers
  WHERE  bmp_score > v_bmp AND is_active = TRUE;

  IF v_confirmed = TRUE AND v_country IS NOT NULL THEN
    SELECT COUNT(*)::INT + 1 INTO country_rank
    FROM   public.trainers
    WHERE  bmp_score > v_bmp AND cc_country = v_country
      AND  location_confirmed = TRUE AND is_active = TRUE;
  ELSE
    country_rank := NULL;
  END IF;

  IF v_confirmed = TRUE AND v_local IS NOT NULL THEN
    SELECT COUNT(*)::INT + 1 INTO local_rank
    FROM   public.trainers
    WHERE  bmp_score > v_bmp AND cc_local_area = v_local
      AND  location_confirmed = TRUE AND is_active = TRUE;
  ELSE
    local_rank := NULL;
  END IF;

  RETURN NEXT;
END;
$$;


-- get_ranking_area_display (supabase_geo_04_functions.sql)
CREATE OR REPLACE FUNCTION public.get_ranking_area_display(p_area_id TEXT)
RETURNS TABLE(
  id           TEXT,
  display_name TEXT,
  area_type    TEXT,
  country      TEXT,
  slug         TEXT,
  parent_name  TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT
    ra.id,
    ra.display_name,
    ra.area_type,
    ra.country,
    ra.slug,
    parent.display_name AS parent_name
  FROM  public.ranking_areas ra
  LEFT JOIN public.ranking_areas parent ON parent.id = ra.parent_id
  WHERE ra.id = p_area_id;
$$;


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 8: TRIGGERS
-- ═════════════════════════════════════════════════════════════════════════════

-- BMP recalc trigger on review approval
DROP TRIGGER IF EXISTS zzz_on_review_bmp_update ON public.reviews;
CREATE TRIGGER zzz_on_review_bmp_update
  AFTER UPDATE OF is_verified ON public.reviews
  FOR EACH ROW
  WHEN (NEW.is_verified = TRUE AND OLD.is_verified IS DISTINCT FROM TRUE)
  EXECUTE FUNCTION public.trigger_calculate_bmp_on_approve();

-- Geo columns protection trigger on trainers
DROP TRIGGER IF EXISTS trainers_protect_geo ON public.trainers;
CREATE TRIGGER trainers_protect_geo
  BEFORE UPDATE ON public.trainers
  FOR EACH ROW
  EXECUTE FUNCTION public.cc_protect_geo_columns();


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 9: TABLE-LEVEL GRANTS
-- ═════════════════════════════════════════════════════════════════════════════

-- trainers: anon + authenticated can SELECT (public leaderboard, find-a-trainer)
-- Note: B3 later restricts this to column-level SELECTs.
-- After applying supabase_b3_column_grants.sql, these table-level grants are
-- REVOKED and replaced with per-column grants. For now (pre-B3) the full table
-- SELECT is in effect as it was in production before B3.
GRANT SELECT ON public.trainers TO anon;
GRANT SELECT ON public.trainers TO authenticated;
GRANT INSERT, UPDATE, DELETE ON public.trainers TO authenticated;

-- reviews: trainers submit via functions, admin approves via functions
GRANT SELECT ON public.reviews TO authenticated;
GRANT SELECT ON public.reviews TO anon;
GRANT INSERT  ON public.reviews TO authenticated;
GRANT INSERT  ON public.reviews TO anon;

-- notifications: authenticated users read their own (enforced by RLS)
GRANT SELECT ON public.notifications TO authenticated;
GRANT UPDATE ON public.notifications TO authenticated;

-- trainer_private: authenticated can SELECT (RLS enforces own-row only)
GRANT SELECT ON public.trainer_private TO authenticated;
GRANT SELECT ON public.trainer_private TO anon;
GRANT ALL    ON public.trainer_private TO service_role;

-- clients: authenticated can SELECT own row
GRANT SELECT ON public.clients TO authenticated;

-- ranking_areas + cc_lad_to_county: read-only public reference data
GRANT SELECT ON public.ranking_areas     TO anon;
GRANT SELECT ON public.ranking_areas     TO authenticated;
GRANT SELECT ON public.cc_lad_to_county  TO anon;
GRANT SELECT ON public.cc_lad_to_county  TO authenticated;

-- ranking_visibility: trainers can update their own preference
GRANT SELECT (ranking_visibility) ON public.trainers TO anon;
GRANT SELECT (ranking_visibility), UPDATE (ranking_visibility) ON public.trainers TO authenticated;


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 10: RLS POLICIES
-- ═════════════════════════════════════════════════════════════════════════════

-- ── Trainers ────────────────────────────────────────────────────────────────

-- Public read: active trainers visible to everyone
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='trainers' AND policyname='Trainers are publicly readable'
  ) THEN
    CREATE POLICY "Trainers are publicly readable"
      ON public.trainers FOR SELECT
      USING (is_active = TRUE);
  END IF;
END $$;

-- Trainers can insert their own profile
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='trainers' AND policyname='PTs can insert own profile'
  ) THEN
    CREATE POLICY "PTs can insert own profile"
      ON public.trainers FOR INSERT
      TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- Trainers can update their own profile (policy A)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='trainers' AND policyname='PTs can update own profile'
  ) THEN
    CREATE POLICY "PTs can update own profile"
      ON public.trainers FOR UPDATE
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

-- Trainers can update their own profile (policy B — production has both names)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='trainers' AND policyname='Trainers can update own profile'
  ) THEN
    CREATE POLICY "Trainers can update own profile"
      ON public.trainers FOR UPDATE
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;


-- ── Notifications ────────────────────────────────────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='notifications' AND policyname='notifications_select_own'
  ) THEN
    CREATE POLICY notifications_select_own
      ON public.notifications FOR SELECT
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='notifications' AND policyname='notifications_update_own'
  ) THEN
    CREATE POLICY notifications_update_own
      ON public.notifications FOR UPDATE
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='notifications' AND policyname='notifications_insert_service'
  ) THEN
    CREATE POLICY notifications_insert_service
      ON public.notifications FOR INSERT
      WITH CHECK (TRUE);
  END IF;
END $$;


-- ── trainer_private ──────────────────────────────────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='trainer_private' AND policyname='trainer_private_select_own'
  ) THEN
    CREATE POLICY trainer_private_select_own
      ON public.trainer_private FOR SELECT
      TO authenticated
      USING (
        trainer_id = (
          SELECT id FROM public.trainers
          WHERE user_id = auth.uid()
          LIMIT 1
        )
      );
  END IF;
END $$;


-- ── Clients ──────────────────────────────────────────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='clients' AND policyname='clients_select_own'
  ) THEN
    CREATE POLICY clients_select_own
      ON public.clients FOR SELECT
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;


-- ── Reviews ──────────────────────────────────────────────────────────────────
-- Trainers can view reviews for their own profile
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='reviews' AND policyname='reviews_select_own_trainer'
  ) THEN
    CREATE POLICY reviews_select_own_trainer
      ON public.reviews FOR SELECT
      TO authenticated
      USING (
        trainer_id IN (
          SELECT id FROM public.trainers WHERE user_id = auth.uid()
        )
      );
  END IF;
END $$;

-- Verified reviews visible to all (for public profile pages)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename='reviews' AND policyname='reviews_select_verified'
  ) THEN
    CREATE POLICY reviews_select_verified
      ON public.reviews FOR SELECT
      USING (is_verified = TRUE);
  END IF;
END $$;


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 11: SYNTHETIC TEST DATA
-- No real trainer records, postcodes, or credentials.
-- ═════════════════════════════════════════════════════════════════════════════

-- 11a. Minimal ranking areas (5 rows — sufficient for BMP tests)
--      Full dataset is in supabase_geo_02_ranking_areas.sql (118 rows) and
--      supabase_geo_03_lad_crosswalk.sql. Import those files for complete geo tests.
INSERT INTO public.ranking_areas (id, area_type, country, display_name, slug, sort_order, is_active)
VALUES
  ('uk',          'uk',      NULL,      'United Kingdom', 'united-kingdom', 0, TRUE),
  ('england',     'country', NULL,      'England',        'england',        1, TRUE),
  ('scotland',    'country', NULL,      'Scotland',       'scotland',       2, TRUE),
  ('wales',       'country', NULL,      'Wales',          'wales',          3, TRUE),
  ('eng-london',  'local',   'England', 'London',         'london',         4, TRUE)
ON CONFLICT (id) DO NOTHING;

-- Set parent_id for local areas
UPDATE public.ranking_areas SET parent_id = 'england' WHERE id = 'eng-london';


-- 11b. Three synthetic trainers for exploratory / pre-run smoke tests
--      Tests in supabase_v3_tests.sql use their own UUIDs and clean up after themselves.
--      These trainers persist between runs and can be used for manual smoke tests.
INSERT INTO public.trainers (
  id, user_id, name, username, is_active,
  bmp_score, star_rating, review_count, is_trending, recent_review_count,
  cc_country, cc_local_area, location_confirmed
)
VALUES
  (
    '00000000-0000-0000-face-000000000001',
    '00000000-0000-0000-cafe-000000000001',
    'Alice Test PT',   'alice-test-pt',   TRUE,
    0, 0, 0, FALSE, 0, 'England', 'eng-london', FALSE
  ),
  (
    '00000000-0000-0000-face-000000000002',
    '00000000-0000-0000-cafe-000000000002',
    'Bob Test PT',     'bob-test-pt',     TRUE,
    0, 0, 0, FALSE, 0, 'England', 'eng-london', FALSE
  ),
  (
    '00000000-0000-0000-face-000000000003',
    '00000000-0000-0000-cafe-000000000003',
    'Carol Test PT',   'carol-test-pt',   FALSE,
    0, 0, 0, FALSE, 0, NULL, NULL, FALSE
  )
ON CONFLICT (id) DO NOTHING;


-- ═════════════════════════════════════════════════════════════════════════════
-- SECTION 12: SCHEMA CACHE REFRESH
-- ═════════════════════════════════════════════════════════════════════════════
NOTIFY pgrst, 'reload schema';


-- ═════════════════════════════════════════════════════════════════════════════
-- POST-SETUP VERIFICATION (run after this file, outside any transaction)
-- ═════════════════════════════════════════════════════════════════════════════
--
-- 1. Confirm all tables exist:
--    SELECT table_name FROM information_schema.tables
--    WHERE table_schema = 'public'
--    ORDER BY table_name;
--    EXPECTED: 8 rows including bmp_v3_migration_backup, cc_lad_to_county,
--              clients, notifications, ranking_areas, trainer_private,
--              trainers, reviews.
--
-- 2. Confirm pre-v3 BMP function (5@3.5★ prior — NOT 8@4.0★):
--    SELECT pg_get_functiondef(oid)
--    FROM pg_proc WHERE proname = 'calculate_bmp_for_trainer';
--    EXPECTED: body contains '5.0 * 3.5' (prior) and no 'v_anon_ids' variable.
--
-- 3. Confirm triggers exist:
--    SELECT trigger_name, event_object_table
--    FROM information_schema.triggers
--    WHERE trigger_schema = 'public'
--    ORDER BY trigger_name;
--    EXPECTED: trainers_protect_geo (trainers), zzz_on_review_bmp_update (reviews).
--
-- 4. Confirm RLS enabled:
--    SELECT relname, relrowsecurity
--    FROM pg_class
--    WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
--      AND relname IN ('trainers','reviews','notifications','trainer_private','clients');
--    EXPECTED: relrowsecurity = true for all 5 rows.
--
-- 5. Confirm distinct_reviewer_count does NOT exist yet (v3 adds it):
--    SELECT column_name FROM information_schema.columns
--    WHERE table_schema = 'public' AND table_name = 'trainers'
--      AND column_name = 'distinct_reviewer_count';
--    EXPECTED: 0 rows.
--
-- 6. Confirm synthetic trainers present:
--    SELECT id, name, is_active FROM trainers ORDER BY name;
--
-- ═════════════════════════════════════════════════════════════════════════════
-- END OF supabase_test_environment_setup.sql
-- =============================================================================
