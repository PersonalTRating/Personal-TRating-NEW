-- ============================================================
-- COACHCARDS: Secure Location Confirmation — Database Layer
-- File: supabase_location_confirm.sql
-- Run order: after supabase_geo_04_functions.sql
--
-- All geo writes are performed by the Netlify function:
--   netlify/functions/confirm-location.js   (service_role)
--
-- Contents:
--   1. get_trainer_ranks()         — 10-trainer threshold
--   2. cc_protect_geo_columns()    — BEFORE UPDATE trigger
--      PRIMARY defence: blocks authenticated-role writes to
--      protected geo columns regardless of table-level GRANTs.
--   3. REVOKE UPDATE (geo cols) FROM authenticated
--      Secondary defence: effective when Supabase has only
--      column-level grants; harmless when a table-level GRANT
--      ALL exists (trigger is the authoritative guard in
--      that case).
--   4. REVOKE SELECT (cc_postcode) FROM anon
--      Secondary defence; see NOTE below.
--
-- NOTE — column-level REVOKE limitation:
--   PostgreSQL column-level REVOKE cannot override an existing
--   table-level GRANT ALL. If Supabase has granted ALL on the
--   trainers table (typical default), items 3 and 4 above are
--   advisory only. The trigger (item 2) is the authoritative
--   write-protection.
--
--   Full postcode read-privacy is addressed in the companion
--   file supabase_postcode_privacy.sql, which stores postcodes
--   in trainer_private (RLS: anon/authenticated denied) and
--   updates the trigger so no role can set trainers.cc_postcode
--   to a non-NULL value.
--
-- SAFE TO RE-RUN: CREATE OR REPLACE; REVOKE is idempotent;
--   trigger uses DROP IF EXISTS before CREATE.
-- DO NOT EXECUTE IN PRODUCTION without explicit approval.
-- ============================================================


-- ──────────────────────────────────────────────────────────
-- 1. get_trainer_ranks() — 10-trainer participation threshold
--
-- country_rank and local_rank are NULL when fewer than 10
-- confirmed trainers exist in the same country / local area.
-- Prevents misleading "Ranked #1 in Rutland (2 trainers)"
-- badges appearing in very sparse areas.
-- Replaces the version from supabase_geo_04_functions.sql.
-- ──────────────────────────────────────────────────────────
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
  v_confirmed     BOOLEAN;
  v_country_count INT;
  v_local_count   INT;
BEGIN
  SELECT bmp_score, cc_country, cc_local_area, location_confirmed
  INTO   v_bmp,     v_country,  v_local,       v_confirmed
  FROM   trainers
  WHERE  id        = p_trainer_id
    AND  is_active = TRUE;

  -- Inactive and non-existent trainers receive no rank.
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- ── UK rank (all active trainers; no location requirement) ──────────
  SELECT COUNT(*)::INT + 1 INTO uk_rank
  FROM   trainers
  WHERE  bmp_score > v_bmp
    AND  is_active = TRUE;

  -- ── Country rank (confirmed trainers; 10-trainer threshold) ─────────
  IF v_confirmed = TRUE AND v_country IS NOT NULL THEN
    SELECT COUNT(*)::INT INTO v_country_count
    FROM   trainers
    WHERE  cc_country         = v_country
      AND  location_confirmed = TRUE
      AND  is_active          = TRUE;

    IF v_country_count >= 10 THEN
      SELECT COUNT(*)::INT + 1 INTO country_rank
      FROM   trainers
      WHERE  bmp_score         > v_bmp
        AND  cc_country        = v_country
        AND  location_confirmed = TRUE
        AND  is_active          = TRUE;
    ELSE
      country_rank := NULL;
    END IF;
  ELSE
    country_rank := NULL;
  END IF;

  -- ── Local rank (confirmed trainers; 10-trainer threshold) ───────────
  IF v_confirmed = TRUE AND v_local IS NOT NULL THEN
    SELECT COUNT(*)::INT INTO v_local_count
    FROM   trainers
    WHERE  cc_local_area      = v_local
      AND  location_confirmed = TRUE
      AND  is_active          = TRUE;

    IF v_local_count >= 10 THEN
      SELECT COUNT(*)::INT + 1 INTO local_rank
      FROM   trainers
      WHERE  bmp_score         > v_bmp
        AND  cc_local_area     = v_local
        AND  location_confirmed = TRUE
        AND  is_active          = TRUE;
    ELSE
      local_rank := NULL;
    END IF;
  ELSE
    local_rank := NULL;
  END IF;

  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION get_trainer_ranks(UUID) IS
  'Returns (uk_rank, country_rank, local_rank) for a trainer.
   uk_rank: always populated (no location requirement).
   country_rank: NULL until location_confirmed AND >=10 confirmed trainers in country.
   local_rank:   NULL until location_confirmed AND >=10 confirmed trainers in local area.
   Rank 1 = highest BMP. Competition rank (1224): tied trainers
   share the same rank and the next position skips. Example: two
   trainers at rank 2 → next trainer is rank 4, not rank 3.';


-- ──────────────────────────────────────────────────────────
-- 2. BEFORE UPDATE trigger — primary protection for geo columns
--
-- This is the authoritative guard. It works regardless of
-- whether Supabase has table-level or column-level GRANTs,
-- because triggers fire before any privilege short-circuit.
--
-- Two distinct protections:
--
--   A. trainers.cc_postcode — RETIRED COLUMN
--      Postcodes are stored in trainer_private (see
--      supabase_postcode_privacy.sql). Any UPDATE that leaves
--      NEW.cc_postcode IS NOT NULL is rejected — including when
--      the value is unchanged from OLD. Only NULL is permitted.
--
--   B. Other geo columns (cc_country, cc_local_area,
--      location_confirmed, location_confirmed_at, etc.)
--      Only postgres, service_role and supabase_admin may
--      update these. authenticated and anon are blocked.
--
-- The trigger fires for ALL updates to trainers. Updates that
-- change none of these columns (bio, city, avatar, etc.) pass
-- through both checks instantly — zero performance impact.
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION cc_protect_geo_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- ── A. cc_postcode is permanently retired from this table ─────────
  -- No role (including service_role) may leave a non-NULL postcode
  -- on this row — even if the value is unchanged from OLD.
  -- Rejected: any UPDATE where NEW.cc_postcode IS NOT NULL.
  -- Permitted: setting the column to NULL (Step 2 data migration).
  IF NEW.cc_postcode IS NOT NULL THEN
    RAISE EXCEPTION 'trainers.cc_postcode is retired. Store postcodes in trainer_private via cc_confirm_location_atomic().'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- ── B. Protect remaining geo columns ──────────────────────────────
  -- Only postgres, service_role and supabase_admin may change these.
  IF (
    NEW.cc_country               IS DISTINCT FROM OLD.cc_country               OR
    NEW.cc_local_area            IS DISTINCT FROM OLD.cc_local_area            OR
    NEW.location_confirmed       IS DISTINCT FROM OLD.location_confirmed       OR
    NEW.location_confirmed_at    IS DISTINCT FROM OLD.location_confirmed_at    OR
    NEW.location_source          IS DISTINCT FROM OLD.location_source          OR
    NEW.location_cooldown_until  IS DISTINCT FROM OLD.location_cooldown_until  OR
    NEW.location_mapping_version IS DISTINCT FROM OLD.location_mapping_version
  ) THEN
    IF current_user NOT IN ('postgres', 'service_role', 'supabase_admin') THEN
      RAISE EXCEPTION 'Direct modification of location columns is not permitted. Use the authorised location confirmation flow.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION cc_protect_geo_columns() IS
  'BEFORE UPDATE trigger guard. Two protections:
   (A) trainers.cc_postcode: no role may set it to non-NULL —
       postcodes are stored in trainer_private.
   (B) Other geo columns: only postgres, service_role and
       supabase_admin may update them. Safe-passthrough for
       all non-geo column updates (bio, city, avatar, etc.).';

DROP TRIGGER IF EXISTS trainers_protect_geo ON trainers;
CREATE TRIGGER trainers_protect_geo
  BEFORE UPDATE ON trainers
  FOR EACH ROW
  EXECUTE FUNCTION cc_protect_geo_columns();

COMMENT ON TRIGGER trainers_protect_geo ON trainers IS
  'Guards two categories: (A) blocks ALL roles from writing a
   non-NULL value to cc_postcode (retired — use trainer_private);
   (B) blocks authenticated/anon from changing other location
   columns. Authorised geo-column write roles: postgres,
   service_role and supabase_admin (via cc_confirm_location_atomic).';


-- ──────────────────────────────────────────────────────────
-- 3. REVOKE UPDATE of geo columns from authenticated role
--
-- Secondary / defence-in-depth measure. Effective only when
-- Supabase has column-level (not table-level) grants. The
-- trigger above is the primary guard and does not depend on
-- this REVOKE being effective.
-- ──────────────────────────────────────────────────────────
REVOKE UPDATE (
  cc_postcode,
  cc_country,
  cc_local_area,
  location_confirmed,
  location_confirmed_at,
  location_source,
  location_cooldown_until,
  location_mapping_version
) ON trainers FROM authenticated;


-- ──────────────────────────────────────────────────────────
-- 4. REVOKE SELECT of cc_postcode from anon role
--
-- Secondary / defence-in-depth. Effective only when Supabase
-- has column-level grants. No application query currently
-- SELECTs cc_postcode from a public route.
--
-- For full postcode read-privacy, create a security-barrier
-- view post-launch that omits cc_postcode and point public
-- queries to it.
-- ──────────────────────────────────────────────────────────
REVOKE SELECT (cc_postcode) ON trainers FROM anon;


-- ──────────────────────────────────────────────────────────
-- Schema cache refresh
-- ──────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
