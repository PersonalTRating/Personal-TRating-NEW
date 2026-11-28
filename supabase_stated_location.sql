-- ============================================================
-- COACHCARDS: Stated-location rankings
-- File: supabase_stated_location.sql
-- Run order: after supabase_founder.sql (latest get_own_trainer_profile)
--
-- New rule: a trainer's STATED postcode district (city as fallback)
-- decides their country and local ranking area. Device location is an
-- optional check only and never overrides the stated location.
--
-- What this file does:
--   1. trainers.postcode_district (outward code only, e.g. SW1, M4, EH1)
--   2. location_source may also be 'city' (assigned from city fallback)
--   3. location_confirmed is repurposed: TRUE only when an opted-in device
--      check matched the stated area. All existing values are reset to
--      FALSE because they came from the old postcode/device confirmation
--      flow, not from a match check.
--   4. trainer_location_checks: admin-only location_mismatch flag
--      (RLS on, no policies → only service_role / SQL editor can read).
--   5. Full postcodes are no longer stored: trainer_private is dropped
--      together with cc_confirm_location_atomic().
--   6. cc_protect_geo_columns(): postcode_district joins the protected
--      columns, so trainers change it only through assign-location.js.
--   7. cc_assign_stated_location() and cc_record_device_check() RPCs
--      (service_role only), called by the Netlify functions.
--   8. get_trainer_ranks(): country/local ranks no longer need
--      location_confirmed — any trainer with an assigned area counts.
--   9. Ranking indexes rebuilt without the location_confirmed filter.
--  10. get_own_trainer_profile(): adds postcode_district.
--
-- Data fixes for existing trainers are in Stage 3 (separate statements).
-- DO NOT EXECUTE IN PRODUCTION without explicit approval.
-- ============================================================

BEGIN;

-- ── 1. postcode_district ─────────────────────────────────────
ALTER TABLE trainers
  ADD COLUMN IF NOT EXISTS postcode_district TEXT;

ALTER TABLE trainers DROP CONSTRAINT IF EXISTS trainers_postcode_district_format;
ALTER TABLE trainers
  ADD CONSTRAINT trainers_postcode_district_format
  CHECK (postcode_district IS NULL OR postcode_district ~ '^[A-Z]{1,2}[0-9][A-Z0-9]?$');

COMMENT ON COLUMN trainers.postcode_district IS
  'Stated UK postcode district (outward code only, uppercase, no space),
   e.g. SW1, M4, EH1. Decides cc_country / cc_local_area. Full postcodes
   are never stored. Written at signup (insert) and afterwards only via
   cc_assign_stated_location() (assign-location.js).';

-- ── 2. location_source gains 'city' ──────────────────────────
-- Drop whichever CHECK constraint currently restricts location_source
-- (auto-named by geo_01, normally trainers_location_source_check).
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT conname FROM pg_constraint
    WHERE  conrelid = 'public.trainers'::regclass
      AND  contype  = 'c'
      AND  pg_get_constraintdef(oid) ILIKE '%location_source%'
  LOOP
    EXECUTE format('ALTER TABLE trainers DROP CONSTRAINT %I', r.conname);
  END LOOP;
END $$;
ALTER TABLE trainers
  ADD CONSTRAINT trainers_location_source_check
  CHECK (location_source IN ('postcode', 'city', 'geolocation', 'admin'));

COMMENT ON COLUMN trainers.location_source IS
  'How cc_country / cc_local_area were assigned: postcode = stated postcode
   district; city = stated city (no usable district); admin = manual.
   geolocation is legacy (pre stated-location rule) and no longer written.';

-- ── 3. location_confirmed repurposed ─────────────────────────
-- Old meaning: "trainer confirmed a postcode / device location; gates rankings".
-- New meaning: "opted-in device location matched the stated area" — public
-- "Location confirmed" indicator on the profile only. No ranking effect.
UPDATE trainers
SET    location_confirmed      = FALSE,
       location_confirmed_at   = NULL,
       location_cooldown_until = NULL
WHERE  location_confirmed = TRUE
    OR location_confirmed_at IS NOT NULL
    OR location_cooldown_until IS NOT NULL;

COMMENT ON COLUMN trainers.location_confirmed IS
  'TRUE only when the trainer opted in to a device-location check and the
   device area matched their stated area. Shows the "Location confirmed"
   indicator on the public profile. Has NO effect on rankings.';
COMMENT ON COLUMN trainers.location_confirmed_at IS
  'When the matching device check happened. NULL when not confirmed.';
COMMENT ON COLUMN trainers.location_cooldown_until IS
  'Legacy (90-day lock from the old confirmation flow). No longer written.';

-- ── 4. Admin-only mismatch flag ──────────────────────────────
CREATE TABLE IF NOT EXISTS trainer_location_checks (
  trainer_id        UUID        PRIMARY KEY REFERENCES trainers(id) ON DELETE CASCADE,
  location_mismatch BOOLEAN     NOT NULL DEFAULT FALSE,
  checked_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE trainer_location_checks IS
  'Admin-only result of the most recent opted-in device-location check.
   Stores ONLY a boolean and a timestamp — no coordinates, no postcode,
   no device area. RLS enabled with no policies: anon and authenticated
   cannot read or write; service_role and the SQL editor can.';
COMMENT ON COLUMN trainer_location_checks.location_mismatch IS
  'TRUE when the device area did not match the stated area. No public effect.';

ALTER TABLE trainer_location_checks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON trainer_location_checks FROM anon, authenticated;
GRANT  ALL ON trainer_location_checks TO service_role;

-- ── 5. Stop storing full postcodes ───────────────────────────
DROP FUNCTION IF EXISTS cc_confirm_location_atomic(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT);
DROP TABLE IF EXISTS trainer_private;
-- trainers.cc_postcode stays retired (always NULL, enforced by the trigger).

-- ── 6. Protect postcode_district alongside the geo columns ───
CREATE OR REPLACE FUNCTION cc_protect_geo_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.cc_postcode IS NOT NULL THEN
    RAISE EXCEPTION 'trainers.cc_postcode is retired. Full postcodes are not stored.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF (
    NEW.postcode_district        IS DISTINCT FROM OLD.postcode_district        OR
    NEW.cc_country               IS DISTINCT FROM OLD.cc_country               OR
    NEW.cc_local_area            IS DISTINCT FROM OLD.cc_local_area            OR
    NEW.location_confirmed       IS DISTINCT FROM OLD.location_confirmed       OR
    NEW.location_confirmed_at    IS DISTINCT FROM OLD.location_confirmed_at    OR
    NEW.location_source          IS DISTINCT FROM OLD.location_source          OR
    NEW.location_cooldown_until  IS DISTINCT FROM OLD.location_cooldown_until  OR
    NEW.location_mapping_version IS DISTINCT FROM OLD.location_mapping_version
  ) THEN
    IF current_user NOT IN ('postgres', 'service_role', 'supabase_admin') THEN
      RAISE EXCEPTION 'Location columns can only be changed through the location assignment flow.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ── 6b. Signup inserts cannot pre-set derived location columns ──
-- Signup (anon/authenticated INSERT) may set postcode_district and city,
-- but the derived area and the device-check status are always assigned
-- server-side afterwards.
CREATE OR REPLACE FUNCTION cc_sanitise_geo_on_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF current_user NOT IN ('postgres', 'service_role', 'supabase_admin') THEN
    NEW.cc_country               := NULL;
    NEW.cc_local_area            := NULL;
    NEW.location_source          := NULL;
    NEW.location_mapping_version := NULL;
    NEW.location_confirmed       := FALSE;
    NEW.location_confirmed_at    := NULL;
    NEW.location_cooldown_until  := NULL;
  END IF;
  NEW.cc_postcode := NULL;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trainers_sanitise_geo_insert ON trainers;
CREATE TRIGGER trainers_sanitise_geo_insert
  BEFORE INSERT ON trainers
  FOR EACH ROW
  EXECUTE FUNCTION cc_sanitise_geo_on_insert();

-- ── 7a. Assign stated location (assign-location.js) ──────────
-- Writes the stated district and the area derived from it (or from the
-- city when no district). Resets the device "Location confirmed" status
-- when the assigned area changes, because the old check no longer applies.
CREATE OR REPLACE FUNCTION cc_assign_stated_location(
  p_trainer_id        UUID,
  p_postcode_district TEXT,
  p_cc_country        TEXT,
  p_cc_local_area     TEXT,
  p_source            TEXT,
  p_mapping_version   TEXT DEFAULT 'ONS-2023-12'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows INT;
BEGIN
  IF p_source NOT IN ('postcode', 'city') THEN
    RAISE EXCEPTION 'invalid source %', p_source;
  END IF;

  UPDATE trainers
  SET    postcode_district        = p_postcode_district,
         cc_country               = p_cc_country,
         cc_local_area            = p_cc_local_area,
         location_source          = p_source,
         location_mapping_version = p_mapping_version,
         location_confirmed       = CASE
                                      WHEN cc_country    IS DISTINCT FROM p_cc_country
                                        OR cc_local_area IS DISTINCT FROM p_cc_local_area
                                      THEN FALSE ELSE location_confirmed END,
         location_confirmed_at    = CASE
                                      WHEN cc_country    IS DISTINCT FROM p_cc_country
                                        OR cc_local_area IS DISTINCT FROM p_cc_local_area
                                      THEN NULL ELSE location_confirmed_at END
  WHERE  id = p_trainer_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN jsonb_build_object('success', v_rows = 1);
END;
$$;

REVOKE EXECUTE ON FUNCTION cc_assign_stated_location(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION cc_assign_stated_location(UUID,TEXT,TEXT,TEXT,TEXT,TEXT) TO service_role;

-- ── 7b. Record an opted-in device check (check-device-location.js) ──
-- Never touches postcode_district / cc_country / cc_local_area.
CREATE OR REPLACE FUNCTION cc_record_device_check(
  p_trainer_id UUID,
  p_matched    BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE trainers
  SET    location_confirmed    = p_matched,
         location_confirmed_at = CASE WHEN p_matched THEN NOW() ELSE NULL END
  WHERE  id = p_trainer_id;

  INSERT INTO trainer_location_checks (trainer_id, location_mismatch, checked_at)
  VALUES (p_trainer_id, NOT p_matched, NOW())
  ON CONFLICT (trainer_id) DO UPDATE
    SET location_mismatch = EXCLUDED.location_mismatch,
        checked_at        = EXCLUDED.checked_at;

  RETURN jsonb_build_object('success', TRUE, 'matched', p_matched);
END;
$$;

REVOKE EXECUTE ON FUNCTION cc_record_device_check(UUID,BOOLEAN) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION cc_record_device_check(UUID,BOOLEAN) TO service_role;

-- ── 8. get_trainer_ranks(): no location_confirmed requirement ─
CREATE OR REPLACE FUNCTION get_trainer_ranks(p_trainer_id UUID)
RETURNS TABLE(uk_rank INT, country_rank INT, local_rank INT)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_bmp           NUMERIC;
  v_country       TEXT;
  v_local         TEXT;
  v_country_count INT;
  v_local_count   INT;
BEGIN
  SELECT bmp_score, cc_country, cc_local_area
  INTO   v_bmp,     v_country,  v_local
  FROM   trainers
  WHERE  id        = p_trainer_id
    AND  is_active = TRUE;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT COUNT(*)::INT + 1 INTO uk_rank
  FROM   trainers
  WHERE  bmp_score > v_bmp
    AND  is_active = TRUE;

  country_rank := NULL;
  IF v_country IS NOT NULL THEN
    SELECT COUNT(*)::INT INTO v_country_count
    FROM   trainers
    WHERE  cc_country = v_country AND is_active = TRUE;

    IF v_country_count >= 10 THEN
      SELECT COUNT(*)::INT + 1 INTO country_rank
      FROM   trainers
      WHERE  bmp_score > v_bmp AND cc_country = v_country AND is_active = TRUE;
    END IF;
  END IF;

  local_rank := NULL;
  IF v_local IS NOT NULL THEN
    SELECT COUNT(*)::INT INTO v_local_count
    FROM   trainers
    WHERE  cc_local_area = v_local AND is_active = TRUE;

    IF v_local_count >= 10 THEN
      SELECT COUNT(*)::INT + 1 INTO local_rank
      FROM   trainers
      WHERE  bmp_score > v_bmp AND cc_local_area = v_local AND is_active = TRUE;
    END IF;
  END IF;

  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION get_trainer_ranks(UUID) IS
  'Returns (uk_rank, country_rank, local_rank). Country/local membership
   comes from the stated location (cc_country / cc_local_area, derived from
   postcode district or city). Device-location confirmation is NOT required.
   Country/local ranks are NULL below 10 trainers in the group.';

-- ── 9. Ranking indexes without the location_confirmed filter ─
DROP INDEX IF EXISTS idx_trainers_country_bmp;
DROP INDEX IF EXISTS idx_trainers_local_bmp;
CREATE INDEX idx_trainers_country_bmp
  ON trainers (cc_country, bmp_score DESC NULLS LAST)
  WHERE is_active = TRUE AND cc_country IS NOT NULL;
CREATE INDEX idx_trainers_local_bmp
  ON trainers (cc_local_area, bmp_score DESC NULLS LAST)
  WHERE is_active = TRUE AND cc_local_area IS NOT NULL;

-- ── 10. get_own_trainer_profile(): add postcode_district ─────
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
    'postcode_district',       t.postcode_district,
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

REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM anon;
GRANT  EXECUTE ON FUNCTION get_own_trainer_profile() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
