-- ============================================================
-- COACHCARDS: Geographical Ranking System — Phase 1, File 4 of 5
-- Functions: resolve_postcode_area(), get_trainer_ranks()
--
-- These functions are called by the dashboard (Phase 2 onwards).
-- Phase 1 creates them; Phase 2 wires them to the frontend.
--
-- SAFE TO RE-RUN: CREATE OR REPLACE.
-- ============================================================


-- ──────────────────────────────────────────────────────────
-- resolve_postcode_area(admin_county, admin_district, country)
--
-- Converts Postcodes.io API response fields into a
-- (cc_country, local_area_id) pair for storing on trainers.
--
-- Call this on the dashboard after a successful Postcodes.io
-- lookup, passing result.admin_county, result.admin_district,
-- and result.country from the API response.
--
-- Returns one row. local_area_id is NULL if the area cannot
-- be resolved (unrecognised admin_district or country).
--
-- Usage from PostgREST RPC:
--   POST /rpc/resolve_postcode_area
--   {"p_admin_county":"Kent","p_admin_district":"Tunbridge Wells","p_country":"England"}
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION resolve_postcode_area(
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
  -- Default country to the input value
  cc_country := p_country;
  v_local    := NULL;

  CASE p_country

    WHEN 'Scotland' THEN
      -- Postcodes.io always populates admin_county = council area name.
      -- Match directly against ranking_areas.display_name.
      SELECT id INTO v_local
      FROM ranking_areas
      WHERE display_name = p_admin_county
        AND area_type    = 'local'
        AND country      = 'Scotland'
        AND is_active    = TRUE;

    WHEN 'Wales' THEN
      -- Postcodes.io always populates admin_county = principal area name.
      SELECT id INTO v_local
      FROM ranking_areas
      WHERE display_name = p_admin_county
        AND area_type    = 'local'
        AND country      = 'Wales'
        AND is_active    = TRUE;

    WHEN 'Northern Ireland' THEN
      -- admin_county is always NULL for NI postcodes.
      -- Use crosswalk keyed on admin_district.
      SELECT ranking_area_id INTO v_local
      FROM cc_lad_to_county
      WHERE admin_district = p_admin_district;

    WHEN 'England' THEN
      -- Step 1: two-tier counties — admin_county is populated.
      IF p_admin_county IS NOT NULL AND p_admin_county <> '' THEN
        SELECT id INTO v_local
        FROM ranking_areas
        WHERE display_name = p_admin_county
          AND area_type    = 'local'
          AND country      = 'England'
          AND is_active    = TRUE;
      END IF;

      -- Step 2: UAs, metro boroughs, London boroughs — admin_county is NULL.
      -- Also handles cases where admin_county returned something unrecognised.
      IF v_local IS NULL THEN
        SELECT ranking_area_id INTO v_local
        FROM cc_lad_to_county
        WHERE admin_district = p_admin_district;
      END IF;

    ELSE
      -- Channel Islands, Isle of Man, BFPO, unknown
      cc_country := NULL;

  END CASE;

  local_area_id := v_local;
  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION resolve_postcode_area(TEXT, TEXT, TEXT) IS
  'Maps Postcodes.io API fields to ranking_areas.
   Input: admin_county, admin_district, country from Postcodes.io response.
   Output: cc_country (for trainers.cc_country) and local_area_id (for trainers.cc_local_area).
   Returns NULL local_area_id for unrecognised areas.';


-- ──────────────────────────────────────────────────────────
-- get_trainer_ranks(trainer_id)
--
-- Returns UK, country, and local rankings for a trainer.
-- Rank = count(trainers with higher bmp_score) + 1.
-- Ties share the same rank (no gap).
--
-- UK rank   : all active trainers (no location requirement).
-- Country   : active confirmed trainers in same cc_country.
-- Local     : active confirmed trainers in same cc_local_area.
-- country_rank and local_rank are NULL until location_confirmed = TRUE.
--
-- Usage from PostgREST RPC:
--   POST /rpc/get_trainer_ranks
--   {"p_trainer_id":"<uuid>"}
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_trainer_ranks(p_trainer_id UUID)
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
  FROM   trainers
  WHERE  id = p_trainer_id;

  IF NOT FOUND THEN
    RETURN;  -- trainer not found; return empty result set
  END IF;

  -- ── UK rank ─────────────────────────────────────────────
  -- Matches existing dashboard behaviour: count all active
  -- trainers with a strictly higher bmp_score.
  SELECT COUNT(*)::INT + 1 INTO uk_rank
  FROM   trainers
  WHERE  bmp_score > v_bmp
    AND  is_active = TRUE;

  -- ── Country rank ─────────────────────────────────────────
  IF v_confirmed = TRUE AND v_country IS NOT NULL THEN
    SELECT COUNT(*)::INT + 1 INTO country_rank
    FROM   trainers
    WHERE  bmp_score         > v_bmp
      AND  cc_country        = v_country
      AND  location_confirmed = TRUE
      AND  is_active          = TRUE;
  ELSE
    country_rank := NULL;
  END IF;

  -- ── Local rank ───────────────────────────────────────────
  IF v_confirmed = TRUE AND v_local IS NOT NULL THEN
    SELECT COUNT(*)::INT + 1 INTO local_rank
    FROM   trainers
    WHERE  bmp_score         > v_bmp
      AND  cc_local_area     = v_local
      AND  location_confirmed = TRUE
      AND  is_active          = TRUE;
  ELSE
    local_rank := NULL;
  END IF;

  RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION get_trainer_ranks(UUID) IS
  'Returns (uk_rank, country_rank, local_rank) for a trainer.
   uk_rank always populated (no location needed).
   country_rank and local_rank NULL until location_confirmed = TRUE.
   Rank 1 = highest BMP in the category.
   Rank calculation: COUNT(trainers with strictly higher bmp) + 1.';


-- ──────────────────────────────────────────────────────────
-- get_ranking_area_display(area_id)
--
-- Returns display info for a ranking area, used by the
-- dashboard and profile pages to show "Ranked #3 in Kent"
-- or "Ranked #12 in England".
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_ranking_area_display(p_area_id TEXT)
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
  FROM  ranking_areas ra
  LEFT JOIN ranking_areas parent ON parent.id = ra.parent_id
  WHERE ra.id = p_area_id;
$$;

COMMENT ON FUNCTION get_ranking_area_display(TEXT) IS
  'Returns display information for a ranking_area row including parent name.
   Used by dashboard and profile pages to construct ranking labels.';
