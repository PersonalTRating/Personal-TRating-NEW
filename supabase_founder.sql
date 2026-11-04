-- ════════════════════════════════════════════════════════════════
-- Founder Programme Migration
--
-- DO NOT execute on production without reviewing each section.
-- Run sections in order; each is idempotent.
--
-- Prerequisites: supabase_rpc_consolidation_patch.sql must already
-- be live (Section 7 requires both distinct_reviewer_count and
-- ranking_visibility to exist on public.trainers).
--
-- What this does:
--   1. Adds is_founder column to trainers
--   2. Creates app_settings table for platform-level toggles
--   3. Seeds the founder_programme_enabled default (true)
--   4. Backfills ALL existing trainer accounts as Founders
--      (active and inactive; no review required)
--   5a. BEFORE INSERT trigger auto-awards Founder on new signup
--       when the programme is enabled
--   5b. BEFORE UPDATE trigger blocks any direct is_founder change
--       by authenticated trainers (SECURITY INVOKER required)
--   6. RLS on app_settings: public SELECT, admin-email-only write
--   7. Updates get_own_trainer_profile() to return is_founder
-- ════════════════════════════════════════════════════════════════


BEGIN;

-- ── 1 · is_founder column ────────────────────────────────────────
ALTER TABLE public.trainers
  ADD COLUMN IF NOT EXISTS is_founder BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.trainers.is_founder IS
  'Set TRUE when the trainer joined during the Founder Programme.
   Awarded automatically by trg_award_founder on INSERT while
   app_settings.founder_programme_enabled = ''true''.
   Also backfilled on migration day to cover all existing accounts
   (active and inactive) without requiring a verified review.
   Once awarded, this flag is permanent — trg_protect_founder
   blocks any direct change by the authenticated role.';


-- ── 2 · app_settings table ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.app_settings (
  key        TEXT        PRIMARY KEY,
  value      TEXT        NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.app_settings IS
  'Platform-level key/value settings. Currently used to control
   the Founder Programme toggle (founder_programme_enabled).';


-- ── 3 · Seed default ────────────────────────────────────────────
INSERT INTO public.app_settings (key, value)
VALUES ('founder_programme_enabled', 'true')
ON CONFLICT (key) DO NOTHING;


-- ── 4 · Backfill ALL existing trainer accounts ──────────────────
-- Awards Founder status to every trainer account that currently
-- has is_founder = FALSE, then records a permanent completion
-- marker in app_settings. The marker makes this section a true
-- one-time operation regardless of the programme's current state.
--
-- Why a permanent marker rather than checking the programme flag:
--   Checking founder_programme_enabled would still allow a
--   re-run to award post-off trainers if the programme were
--   subsequently re-enabled. The marker cannot be changed by
--   the trigger, by any RLS policy or by any client call; only
--   a manual service_role delete can remove it.
--
-- Atomicity: the UPDATE and marker INSERT are both inside a
--   single DO block, which executes as one statement. If either
--   step fails the whole block rolls back — the marker is never
--   written without the backfill completing, and the backfill is
--   never committed without the marker.
--
-- Re-run behaviour:
--   First run   → marker absent → backfill runs → marker written ✓
--   Any re-run  → marker present → entire block skipped ✓
--   OFF → ON → re-run → marker still present → skipped ✓
--
-- Rows already set TRUE are untouched (WHERE is_founder = FALSE).
-- No programmatic test-account exclusion is applied here because
-- there is no reliable marker in the schema that identifies test
-- accounts without risk of false positives. Exclude specific rows
-- manually via service_role after reviewing the data if needed.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.app_settings
    WHERE  key = 'founder_backfill_completed'
  ) THEN
    RAISE NOTICE 'Section 4: backfill skipped — permanent marker founder_backfill_completed already present.';
    RETURN;
  END IF;

  UPDATE public.trainers
  SET    is_founder = TRUE
  WHERE  is_founder = FALSE;

  INSERT INTO public.app_settings (key, value)
  VALUES (
    'founder_backfill_completed',
    to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS UTC')
  );

  RAISE NOTICE 'Section 4: backfill complete — Founder status awarded to all existing trainers. Permanent marker written.';
END;
$$;


-- ── 5 · Auto-award trigger ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.award_founder_on_signup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  _enabled TEXT;
BEGIN
  SELECT value INTO _enabled
  FROM   public.app_settings
  WHERE  key = 'founder_programme_enabled';

  -- Always override whatever the caller supplied for is_founder.
  -- The server unconditionally sets the correct value based on the
  -- programme setting; callers cannot self-award or block the award
  -- by including is_founder in their INSERT payload.
  IF _enabled = 'true' THEN
    NEW.is_founder := TRUE;
  ELSE
    NEW.is_founder := FALSE;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.award_founder_on_signup() IS
  'BEFORE INSERT trigger that unconditionally sets is_founder based on
   founder_programme_enabled: TRUE when ''true'', FALSE otherwise.
   Always overrides any caller-supplied value so a caller cannot
   self-award or suppress the award by including is_founder in the
   INSERT payload. SECURITY DEFINER so it can read app_settings.';

DROP TRIGGER IF EXISTS trg_award_founder ON public.trainers;

CREATE TRIGGER trg_award_founder
  BEFORE INSERT ON public.trainers
  FOR EACH ROW
  EXECUTE FUNCTION public.award_founder_on_signup();


-- ── 5b · Protect is_founder from direct UPDATE by trainers ───────
-- Mirrors the trainers_protect_geo pattern. Prevents any authenticated
-- trainer from self-awarding or revoking the Founder badge via a
-- direct API UPDATE. Only postgres / service_role / supabase_admin
-- may change is_founder after the initial INSERT.
--
-- CRITICAL: This function MUST be SECURITY INVOKER (the default).
-- If it were SECURITY DEFINER, current_user would always return the
-- function owner (postgres) instead of the actual calling role, so
-- the NOT IN (...) check would always pass for postgres and no
-- exception would ever fire — any trainer could change is_founder.
-- SECURITY INVOKER ensures current_user reflects the PostgREST role
-- set via SET LOCAL ROLE (e.g. 'authenticated' for trainer requests).
CREATE OR REPLACE FUNCTION public.protect_founder_flag()
RETURNS TRIGGER
LANGUAGE plpgsql
-- SECURITY INVOKER is the default and is REQUIRED here so that
-- current_user reflects the actual caller role, not the owner.
SET search_path = ''
AS $$
BEGIN
  IF NEW.is_founder IS DISTINCT FROM OLD.is_founder THEN
    IF current_user NOT IN ('postgres', 'service_role', 'supabase_admin') THEN
      RAISE EXCEPTION
        'is_founder may not be changed directly. '
        'Founder status is controlled by the platform only.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.protect_founder_flag() IS
  'SECURITY INVOKER BEFORE UPDATE trigger that blocks any role other
   than postgres / service_role / supabase_admin from changing
   is_founder. Must NOT be SECURITY DEFINER (that would make
   current_user = owner = postgres, defeating the check). PostgREST
   authenticated requests run as the ''authenticated'' role, so
   current_user = ''authenticated'' inside this function when a trainer
   calls a direct UPDATE — the NOT IN check then correctly fires.';

DROP TRIGGER IF EXISTS trg_protect_founder ON public.trainers;

CREATE TRIGGER trg_protect_founder
  BEFORE UPDATE ON public.trainers
  FOR EACH ROW
  EXECUTE FUNCTION public.protect_founder_flag();


-- ── 6 · Row-level security on app_settings ──────────────────────
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- Allow any visitor (including unauthenticated) to read settings
-- (the homepage leaderboard and admin page both need to read this
-- without additional round-trips).
DROP POLICY IF EXISTS "public_read_app_settings"  ON public.app_settings;
CREATE POLICY "public_read_app_settings"
  ON public.app_settings FOR SELECT
  USING (true);

-- Only the admin user may insert/update/delete settings.
-- Uses auth.email() so no service-role key is exposed client-side.
DROP POLICY IF EXISTS "admin_write_app_settings"  ON public.app_settings;
CREATE POLICY "admin_write_app_settings"
  ON public.app_settings FOR ALL
  USING     (auth.email() = 'modernisetraders@hotmail.com')
  WITH CHECK (auth.email() = 'modernisetraders@hotmail.com');

-- Grant table access to roles that need it
GRANT SELECT           ON public.app_settings TO anon, authenticated;
GRANT INSERT, UPDATE   ON public.app_settings TO authenticated;


-- ── 7 · Update get_own_trainer_profile() ────────────────────────
-- Based on the authoritative production version in
-- supabase_rpc_consolidation_patch.sql (last deployed).
-- Adds is_founder as the final field; all 34 fields preserved.
-- IMPORTANT: Run supabase_rpc_consolidation_patch.sql before this
-- if it has not yet been applied — this file requires both
-- distinct_reviewer_count and ranking_visibility to exist on
-- public.trainers.
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
    'location_cooldown_until', t.location_cooldown_until,
    'ranking_visibility',      t.ranking_visibility,
    'is_founder',              t.is_founder
  )
  FROM   public.trainers t
  WHERE  t.user_id = auth.uid()
  LIMIT  1;
$$;

COMMENT ON FUNCTION get_own_trainer_profile() IS
  'Returns the authenticated trainer''s own row as JSONB containing only the
   fields required by dashboard.astro. SECURITY DEFINER ensures postcode,
   location_cooldown_until, ranking_visibility, distinct_reviewer_count and
   is_founder are accessible even after B3 column grants restrict those columns
   from the authenticated role. Identity derived from auth.uid() only — no
   caller-supplied parameter. Returns NULL when unauthenticated or when no
   trainer record exists for the calling user.';

REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM anon;
GRANT  EXECUTE ON FUNCTION get_own_trainer_profile() TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
