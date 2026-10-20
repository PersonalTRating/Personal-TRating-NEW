-- ============================================================
-- COACHCARDS: Geo Hotfix — Scotland and Wales local area mapping
-- File: supabase_geo_hotfix_scotland_wales.sql
--
-- Problem:
--   resolve_postcode_area() matched ranking_areas.display_name
--   against p_admin_county for Scotland and Wales. Postcodes.io
--   returns admin_county = null for both nations (single-tier
--   council systems). The council area name is in admin_district,
--   so every Scottish and Welsh postcode resolved with
--   local_area_id = null.
--
-- Fix:
--   Scotland and Wales branches now match against p_admin_district.
--   England and Northern Ireland logic is unchanged.
--
-- Verified against live Postcodes.io:
--   KY11 8PZ → admin_district = "Fife"           → SCO_FIFE
--   EH8 9NX  → admin_district = "City of Edinburgh" → SCO_CITY_OF_EDINBURGH
--   CF10 1AA → admin_district = "Cardiff"         → WLS_CARDIFF
--
-- SAFE TO RE-RUN: CREATE OR REPLACE.
-- DO NOT EXECUTE IN PRODUCTION without explicit approval.
-- ============================================================

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
      -- Postcodes.io returns admin_county = null for all Scottish postcodes.
      -- Scotland uses a single-tier council system; the council area name
      -- is in admin_district (e.g. "Fife", "City of Edinburgh", "Highland").
      -- Match directly against ranking_areas.display_name.
      SELECT id INTO v_local
      FROM ranking_areas
      WHERE display_name = p_admin_district
        AND area_type    = 'local'
        AND country      = 'Scotland'
        AND is_active    = TRUE;

    WHEN 'Wales' THEN
      -- Postcodes.io returns admin_county = null for all Welsh postcodes.
      -- Wales uses a single-tier principal area system; the area name
      -- is in admin_district (e.g. "Cardiff", "Swansea", "Gwynedd").
      -- Match directly against ranking_areas.display_name.
      SELECT id INTO v_local
      FROM ranking_areas
      WHERE display_name = p_admin_district
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
   Scotland and Wales: matched via admin_district (admin_county is always null for both nations).
   England: two-tier counties via admin_county; UAs/metro/London via cc_lad_to_county crosswalk.
   Northern Ireland: matched via cc_lad_to_county crosswalk on admin_district.
   Returns NULL local_area_id for unrecognised areas.';

NOTIFY pgrst, 'reload schema';
