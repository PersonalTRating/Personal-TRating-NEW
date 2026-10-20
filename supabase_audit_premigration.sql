-- ══════════════════════════════════════════════════════════════
-- COACHCARDS — Pre-migration Compatibility Audit
-- Read-only. Run in Supabase SQL Editor BEFORE executing:
--   1. supabase_location_confirm.sql
--   2. supabase_postcode_privacy.sql
--
-- Every statement is a SELECT from system catalogs or the
-- trainers table. Nothing is modified.
-- ══════════════════════════════════════════════════════════════


-- ── CHECK 1 ─────────────────────────────────────────────────
-- Trainers table: all columns referenced by the migrations.
-- EXPECTED: all 12 rows present.
-- If any row is missing, that migration will fail at runtime.
-- Pay attention to data_type — TEXT is required for postcode
-- columns; BOOLEAN for location_confirmed; TIMESTAMPTZ for
-- the _at / _until columns.
-- ─────────────────────────────────────────────────────────────

SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'trainers'
  AND  column_name  IN (
    'id',
    'user_id',
    'is_active',
    'bmp_score',
    'cc_postcode',
    'cc_country',
    'cc_local_area',
    'location_confirmed',
    'location_confirmed_at',
    'location_source',
    'location_cooldown_until',
    'location_mapping_version'
  )
ORDER BY column_name;


-- ── CHECK 2 ─────────────────────────────────────────────────
-- trainer_private table existence.
-- EXPECTED: 0 rows — table does not yet exist.
-- If 1 row is returned, supabase_postcode_privacy.sql has
-- already been partially executed.
-- ─────────────────────────────────────────────────────────────

SELECT table_name, table_type
FROM   information_schema.tables
WHERE  table_schema = 'public'
  AND  table_name   = 'trainer_private';


-- ── CHECK 3 ─────────────────────────────────────────────────
-- Functions that the migrations will create or replace.
-- EXPECTED:
--   get_trainer_ranks(uuid)   — SHOULD exist (deployed with
--     geo functions). Will be replaced by CREATE OR REPLACE.
--   cc_protect_geo_columns()  — may or may not exist.
--     Will be created / replaced.
--   cc_confirm_location_atomic(...) — SHOULD NOT exist.
--     If present, migrations have been partially run.
--   resolve_postcode_area(...)— SHOULD exist (confirmed deployed).
--     Used by the Netlify function; not changed by migrations.
--   get_ranking_area_display(...)— SHOULD exist (confirmed deployed).
--     Used by the Netlify function; not changed by migrations.
--
-- security_definer = true means the function runs as its owner
-- (postgres), not as the calling role. Required for
-- cc_confirm_location_atomic to bypass RLS.
-- ─────────────────────────────────────────────────────────────

SELECT
  p.proname                                        AS function_name,
  pg_get_function_identity_arguments(p.oid)        AS argument_types,
  r.rolname                                        AS owner,
  p.prosecdef                                      AS security_definer,
  CASE p.provolatile
    WHEN 'i' THEN 'IMMUTABLE'
    WHEN 's' THEN 'STABLE'
    WHEN 'v' THEN 'VOLATILE'
  END                                              AS volatility
FROM   pg_proc      p
JOIN   pg_roles     r ON r.oid = p.proowner
WHERE  p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND  p.proname IN (
    'get_trainer_ranks',
    'cc_protect_geo_columns',
    'cc_confirm_location_atomic',
    'resolve_postcode_area',
    'get_ranking_area_display'
  )
ORDER BY p.proname;


-- ── CHECK 4 ─────────────────────────────────────────────────
-- Existing trigger on trainers.
-- EXPECTED: 0 rows — trigger does not yet exist.
-- The migration runs DROP TRIGGER IF EXISTS before creating it,
-- so 1 existing row is also safe, but note it here.
-- ─────────────────────────────────────────────────────────────

SELECT
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
FROM   information_schema.triggers
WHERE  event_object_schema = 'public'
  AND  event_object_table  = 'trainers'
  AND  trigger_name        = 'trainers_protect_geo';


-- ── CHECK 5 ─────────────────────────────────────────────────
-- RLS status on the trainers table.
-- EXPECTED: relrowsecurity = false — RLS is not yet enabled.
-- If true, existing RLS policies (Check 6) govern access and
-- the migration REVOKEs may behave differently.
-- ─────────────────────────────────────────────────────────────

SELECT
  relname             AS table_name,
  relrowsecurity      AS rls_enabled,
  relforcerowsecurity AS rls_forced
FROM   pg_class
WHERE  relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND  relname      = 'trainers';


-- ── CHECK 6 ─────────────────────────────────────────────────
-- Existing RLS policies on the trainers table.
-- EXPECTED: 0 rows — no policies in place.
-- Any rows here should be reviewed before running migrations
-- to ensure they do not conflict with the trigger protections.
-- ─────────────────────────────────────────────────────────────

SELECT
  policyname,
  roles,
  cmd,
  qual
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename  = 'trainers';


-- ── CHECK 7 ─────────────────────────────────────────────────
-- Table-level grants on trainers.
-- EXPECTED: SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER
-- granted to anon, authenticated and service_role (Supabase
-- defaults). This confirms why column-level REVOKE in the
-- migration is advisory only — the table-level GRANT ALL
-- overrides it. The trigger is therefore the authoritative guard.
-- ─────────────────────────────────────────────────────────────

SELECT
  grantee,
  privilege_type,
  is_grantable
FROM   information_schema.table_privileges
WHERE  table_schema = 'public'
  AND  table_name   = 'trainers'
ORDER BY grantee, privilege_type;


-- ── CHECK 8 ─────────────────────────────────────────────────
-- Column-level grants on the geo columns.
-- EXPECTED: 0 rows — no explicit column-level grants exist yet.
-- Any existing column-level grants mean a previous REVOKE was
-- attempted; they are advisory alongside the table-level grants.
-- ─────────────────────────────────────────────────────────────

SELECT
  column_name,
  grantee,
  privilege_type,
  is_grantable
FROM   information_schema.column_privileges
WHERE  table_schema = 'public'
  AND  table_name   = 'trainers'
  AND  column_name  IN (
    'cc_postcode',
    'cc_country',
    'cc_local_area',
    'location_confirmed',
    'location_confirmed_at',
    'location_source',
    'location_cooldown_until',
    'location_mapping_version'
  )
ORDER BY column_name, grantee, privilege_type;


-- ── CHECK 9 ─────────────────────────────────────────────────
-- Execute privileges on functions already deployed.
-- Shows TRUE/FALSE per role for each existing function.
-- cc_confirm_location_atomic is omitted — it does not exist yet.
--
-- EXPECTED:
--   get_trainer_ranks       — anon=true, authenticated=true
--                             (public function, anon access fine)
--   resolve_postcode_area   — anon=true, authenticated=true
--   get_ranking_area_display— anon=true, authenticated=true
--   cc_protect_geo_columns  — n/a (trigger function, not callable
--                             directly; shown for completeness)
--
-- After running supabase_postcode_privacy.sql, re-run Check 9
-- and add cc_confirm_location_atomic to verify it shows
-- anon=false, authenticated=false, service_role=true.
-- ─────────────────────────────────────────────────────────────

SELECT
  p.proname                                               AS function_name,
  has_function_privilege('anon',          p.oid, 'execute') AS anon_execute,
  has_function_privilege('authenticated', p.oid, 'execute') AS authenticated_execute,
  has_function_privilege('service_role',  p.oid, 'execute') AS service_role_execute
FROM   pg_proc p
WHERE  p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND  p.proname IN (
    'get_trainer_ranks',
    'cc_protect_geo_columns',
    'resolve_postcode_area',
    'get_ranking_area_display'
  )
ORDER BY p.proname;


-- ── CHECK 10 ────────────────────────────────────────────────
-- auth.uid() availability.
-- EXPECTED: 1 row — the auth.uid function must exist for the
-- trainer_private RLS policy to work. If 0 rows, the Supabase
-- auth schema is not configured correctly.
-- ─────────────────────────────────────────────────────────────

SELECT routine_schema, routine_name
FROM   information_schema.routines
WHERE  routine_schema = 'auth'
  AND  routine_name   = 'uid';


-- ── CHECK 11 ────────────────────────────────────────────────
-- Current cc_postcode data snapshot.
-- EXPECTED:
--   total_trainers         = 6
--   active_trainers        = 6 (or your current active count)
--   trainers_with_postcode = 0
--
-- If trainers_with_postcode > 0, you MUST run Step 2 of
-- supabase_postcode_privacy.sql (the data migration DO block)
-- before deploying the updated Netlify function. Otherwise
-- those postcodes will be lost.
-- ─────────────────────────────────────────────────────────────

SELECT
  COUNT(*)                                        AS total_trainers,
  COUNT(CASE WHEN is_active     THEN 1 END)       AS active_trainers,
  COUNT(CASE WHEN cc_postcode IS NOT NULL
               AND cc_postcode <> '' THEN 1 END)  AS trainers_with_postcode
FROM trainers;


-- ── CHECK 12 ────────────────────────────────────────────────
-- get_trainer_ranks current body: does it already have the
-- is_active filter on the initial trainer SELECT?
-- EXPECTED: 'YES — is_active filter present (already correct)'
-- If 'NO', the migration will add it via CREATE OR REPLACE.
-- ─────────────────────────────────────────────────────────────

SELECT
  p.proname AS function_name,
  CASE
    WHEN p.prosrc LIKE '%WHERE%id%=%p_trainer_id%AND%is_active%'
      OR p.prosrc LIKE '%AND%is_active = TRUE%'
      OR p.prosrc LIKE '%AND  is_active%'
    THEN 'YES — is_active filter present (already correct)'
    ELSE 'NO — is_active filter missing (migration will add it)'
  END AS initial_select_has_active_filter
FROM   pg_proc p
WHERE  p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND  p.proname      = 'get_trainer_ranks';


-- ══════════════════════════════════════════════════════════════
-- END OF AUDIT
-- Run all 12 checks, review results against expected values
-- above, then proceed with the migrations if all pass.
-- ══════════════════════════════════════════════════════════════
