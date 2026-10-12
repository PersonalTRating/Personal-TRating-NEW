-- ============================================================
-- COACHCARDS: Geographical Ranking System — Phase 1, File 1 of 5
-- Schema: ranking_areas table, LAD crosswalk table, trainer columns
--
-- Geographical framework
-- ──────────────────────
--   England      : 48 Ceremonial Counties (Lord Lieutenancy boundaries)
--   Scotland     : 32 Council Areas (local government, since 1996)
--   Wales        : 22 Principal Areas (local government, since 1996)
--   N. Ireland   : 11 Districts (post-2015 local government reform)
--
-- Data source strategy
-- ────────────────────
--   Postcode API : Postcodes.io (https://postcodes.io)
--                  Returns ONS field values: admin_county, admin_district, country
--   Direct match : Scotland and Wales admin_county values match
--                  ranking_areas.display_name directly
--   Crosswalk    : English LADs where admin_county = NULL (metro boroughs,
--                  London boroughs, unitary authorities) and all NI districts
--                  are resolved via cc_lad_to_county keyed on admin_district
--   ONS boundary : December 2023 release
--                  https://geoportal.statistics.gov.uk/
--
-- Run order: 01 → 02 → 03 → 04 → 05
-- This file: schema only. No data inserted.
-- SAFE TO RE-RUN: all DDL uses IF NOT EXISTS guards.
-- DO NOT RUN without review. No destructive operations in this file.
-- ============================================================


-- ──────────────────────────────────────────────────────────
-- 1. ranking_areas
--    Authoritative list of all supported UK ranking areas.
--    Every trainer with a confirmed location belongs to
--    exactly one local area and one country (both rows here).
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ranking_areas (
  id           TEXT PRIMARY KEY,
  area_type    TEXT NOT NULL
               CHECK (area_type IN ('national', 'country', 'local')),
  country      TEXT
               CHECK (country IN ('England','Scotland','Wales','Northern Ireland')
                      OR country IS NULL),
  display_name TEXT NOT NULL,
  slug         TEXT NOT NULL UNIQUE,
  parent_id    TEXT REFERENCES ranking_areas(id),
  ons_code     TEXT,
  sort_order   INTEGER NOT NULL DEFAULT 0,
  is_active    BOOLEAN NOT NULL DEFAULT TRUE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE ranking_areas IS
  'Authoritative UK ranking areas: 1 national, 4 countries, 113 local.
   Framework: ONS Administrative Geography December 2023.
   England = 48 Ceremonial Counties; Scotland = 32 Council Areas;
   Wales = 22 Principal Areas; Northern Ireland = 11 Districts.
   Total: 118 rows.';

COMMENT ON COLUMN ranking_areas.id IS
  'Stable short slug. Format: UK | ENG | SCO | WLS | NIR | ENG_KENT | SCO_FIFE etc.
   Never rename after trainers reference it — do a data migration instead.';

COMMENT ON COLUMN ranking_areas.ons_code IS
  'ONS geographical code. Countries: E92000001 England, S92000003 Scotland,
   W92000004 Wales, N92000002 Northern Ireland.
   Local areas: CTY/county council codes for English admin counties;
   LAD codes for Scottish/Welsh/NI council areas.
   Source: ONS Open Geography Portal, December 2023.
   NULL where no single ONS code covers the ceremonial extent.';

COMMENT ON COLUMN ranking_areas.slug IS
  'URL-safe identifier for /rankings/<slug> pages (Phase 5).
   Lowercase, hyphens only, globally unique across all countries.';

COMMENT ON COLUMN ranking_areas.parent_id IS
  'Hierarchy: local → country → UK.
   Used for breadcrumb navigation and filtering.';


-- ──────────────────────────────────────────────────────────
-- 2. cc_lad_to_county
--    Maps Postcodes.io admin_district strings to ranking_areas
--    for cases where Postcodes.io returns NULL for admin_county.
--
--    This applies to:
--      England  — Metropolitan Boroughs (36 LADs across 6 metro counties)
--      England  — London Boroughs (32 + City of London → Greater London)
--      England  — Unitary Authorities (~56 LADs, varying county assignments)
--      N.Ireland — All 11 Districts (no county tier in NI)
--
--    Scotland and Wales: admin_county is always populated by Postcodes.io
--    and matches ranking_areas.display_name directly. No crosswalk needed.
--
--    IMPORTANT: admin_district key values must match Postcodes.io output
--    exactly (case-sensitive). Verify with: https://postcodes.io/postcodes/<pc>
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cc_lad_to_county (
  admin_district  TEXT PRIMARY KEY,
  ranking_area_id TEXT NOT NULL REFERENCES ranking_areas(id),
  ons_lad_code    TEXT,
  area_category   TEXT
                  CHECK (area_category IN (
                    'metro_borough',
                    'london_borough',
                    'unitary_authority',
                    'ni_district'
                  )),
  notes           TEXT,
  verified        BOOLEAN NOT NULL DEFAULT FALSE
);

COMMENT ON TABLE cc_lad_to_county IS
  'Postcodes.io admin_district → ranking_areas.id crosswalk.
   Used when Postcodes.io admin_county is NULL.
   verified=TRUE: admin_district string confirmed against live Postcodes.io lookup.
   verified=FALSE: derived from ONS LAD list; string may need adjustment.
   Reference dataset: ONS LAD December 2023
   https://geoportal.statistics.gov.uk/';


-- ──────────────────────────────────────────────────────────
-- 3. New columns on trainers
--    All nullable. Zero impact on existing rows or BMP scores.
--    cc_* columns are populated only when a trainer actively
--    confirms their location in the dashboard (Phase 2).
-- ──────────────────────────────────────────────────────────
ALTER TABLE trainers
  ADD COLUMN IF NOT EXISTS cc_postcode              TEXT,
  ADD COLUMN IF NOT EXISTS cc_country               TEXT,
  ADD COLUMN IF NOT EXISTS cc_local_area            TEXT
    REFERENCES ranking_areas(id),
  ADD COLUMN IF NOT EXISTS location_confirmed       BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS location_confirmed_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS location_source          TEXT
    CHECK (location_source IN ('postcode', 'geolocation', 'admin')),
  ADD COLUMN IF NOT EXISTS location_cooldown_until  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS location_mapping_version TEXT;

COMMENT ON COLUMN trainers.cc_postcode IS
  'Validated postcode, space-normalised, uppercase (e.g. SW1A 1AA).
   Set only after Postcodes.io returns a valid result. Never raw input.';
COMMENT ON COLUMN trainers.cc_country IS
  'Postcodes.io ''country'' field at validation time.
   Values: England | Scotland | Wales | Northern Ireland.';
COMMENT ON COLUMN trainers.cc_local_area IS
  'FK → ranking_areas.id for this trainer''s ceremonial county or council area.
   NULL until trainer confirms location.';
COMMENT ON COLUMN trainers.location_confirmed IS
  'TRUE once trainer has actively confirmed via dashboard.
   Only confirmed trainers participate in country and local rankings.';
COMMENT ON COLUMN trainers.location_cooldown_until IS
  'If set, trainer cannot change location until this timestamp.
   Set to NOW() + INTERVAL ''90 days'' on first confirmation.';
COMMENT ON COLUMN trainers.location_mapping_version IS
  'Records which ONS boundary version resolved this trainer''s location.
   Enables bulk re-resolution on boundary changes. Format: ONS-YYYY-MM.';


-- Partial indexes for fast rank COUNT queries
-- The WHERE clause mirrors the filter used in get_trainer_ranks()
CREATE INDEX IF NOT EXISTS idx_trainers_country_bmp
  ON trainers (cc_country, bmp_score DESC NULLS LAST)
  WHERE location_confirmed = TRUE AND is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_trainers_local_bmp
  ON trainers (cc_local_area, bmp_score DESC NULLS LAST)
  WHERE location_confirmed = TRUE AND is_active = TRUE;


-- ──────────────────────────────────────────────────────────
-- Schema cache refresh
-- ──────────────────────────────────────────────────────────
NOTIFY pgrst, 'reload schema';
