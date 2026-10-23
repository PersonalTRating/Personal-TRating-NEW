-- ════════════════════════════════════════════════════════════════════════════
-- CoachCards — Ranking Visibility Preference Migration
-- Requires: B3 (supabase_b3_column_grants.sql) already applied in production.
-- ════════════════════════════════════════════════════════════════════════════
--
-- Adds a trainer-controlled column `ranking_visibility`:
--
--   'all'        → UK, Country & Local  (default — all eligible tiers)
--   'uk_country' → UK & Country only    (opts out of local ranking)
--   'uk_only'    → UK ranking only      (opts out of country and local)
--
-- B3 revoked all table-level SELECT on public.trainers and replaced it with
-- explicit column-level grants to anon and authenticated. Any new column
-- therefore requires explicit GRANT SELECT before PostgREST or client-side
-- code can read it, and GRANT UPDATE before authenticated can write it.
-- ════════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Step 0: Pre-flight ────────────────────────────────────────────────────────
-- Confirm the column does not already exist.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE  table_schema = 'public'
      AND  table_name   = 'trainers'
      AND  column_name  = 'ranking_visibility'
  ) THEN
    RAISE EXCEPTION 'Column ranking_visibility already exists on public.trainers — migration already applied.';
  END IF;
END
$$;

-- ── Step 1: Add column ────────────────────────────────────────────────────────
ALTER TABLE public.trainers
  ADD COLUMN ranking_visibility TEXT NOT NULL DEFAULT 'all'
  CONSTRAINT trainers_ranking_visibility_check
    CHECK (ranking_visibility IN ('all', 'uk_country', 'uk_only'));

COMMENT ON COLUMN public.trainers.ranking_visibility IS
  'Trainer-controlled ranking tier opt-in. all = UK+Country+Local; uk_country = UK+Country; uk_only = UK only. Default all.';

-- ── Step 2: Column-level grants (required post-B3) ────────────────────────────
-- B3 removed table-level SELECT; every new column needs an explicit grant.

-- anon reads ranking_visibility at build time (Astro SSG service_role bypasses
-- column grants, but anon is needed for any future client-side queries).
GRANT SELECT (ranking_visibility) ON public.trainers TO anon;

-- authenticated reads their own value in the dashboard and can update it.
GRANT SELECT (ranking_visibility) ON public.trainers TO authenticated;

-- authenticated UPDATE is constrained to the trainer's own row by existing RLS
-- (trainers_update_own policy). No additional row-level change needed.
GRANT UPDATE (ranking_visibility) ON public.trainers TO authenticated;

-- ── Step 3: Verify ────────────────────────────────────────────────────────────
DO $$
DECLARE
  _col_exists   BOOLEAN;
  _grant_anon   BOOLEAN;
  _grant_auth   BOOLEAN;
  _total        BIGINT;
  _defaulted    BIGINT;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE  table_schema = 'public'
      AND  table_name   = 'trainers'
      AND  column_name  = 'ranking_visibility'
  ) INTO _col_exists;

  SELECT EXISTS (
    SELECT 1
    FROM   pg_attribute  a
    JOIN   pg_class      c ON c.oid = a.attrelid
    JOIN   pg_namespace  n ON n.oid = c.relnamespace,
    LATERAL aclexplode(COALESCE(a.attacl, ARRAY[]::aclitem[])) AS acl
    WHERE  n.nspname          = 'public'
      AND  c.relname          = 'trainers'
      AND  a.attname          = 'ranking_visibility'
      AND  acl.privilege_type = 'SELECT'
      AND  pg_catalog.pg_get_userbyid(acl.grantee) = 'anon'
  ) INTO _grant_anon;

  SELECT EXISTS (
    SELECT 1
    FROM   pg_attribute  a
    JOIN   pg_class      c ON c.oid = a.attrelid
    JOIN   pg_namespace  n ON n.oid = c.relnamespace,
    LATERAL aclexplode(COALESCE(a.attacl, ARRAY[]::aclitem[])) AS acl
    WHERE  n.nspname          = 'public'
      AND  c.relname          = 'trainers'
      AND  a.attname          = 'ranking_visibility'
      AND  acl.privilege_type = 'SELECT'
      AND  pg_catalog.pg_get_userbyid(acl.grantee) = 'authenticated'
  ) INTO _grant_auth;

  SELECT COUNT(*) INTO _total     FROM public.trainers;
  SELECT COUNT(*) INTO _defaulted FROM public.trainers WHERE ranking_visibility = 'all';

  RAISE NOTICE 'column exists:            %', _col_exists;
  RAISE NOTICE 'anon SELECT grant:        %', _grant_anon;
  RAISE NOTICE 'authenticated SELECT grant:%', _grant_auth;
  RAISE NOTICE 'total trainers:           %', _total;
  RAISE NOTICE 'defaulted to all:         % (should equal total)', _defaulted;

  IF NOT (_col_exists AND _grant_anon AND _grant_auth AND _total = _defaulted) THEN
    RAISE EXCEPTION 'Step 3 verification failed — rolling back.';
  END IF;
END
$$;

COMMIT;

-- ── Step 4: Schema cache refresh ─────────────────────────────────────────────
-- Signals PostgREST to reload its schema cache so the new column is visible
-- immediately via the REST API without restarting the service.
NOTIFY pgrst, 'reload schema';

-- ── Rollback ──────────────────────────────────────────────────────────────────
-- To undo (run outside a transaction after COMMIT above):
--
--   REVOKE SELECT (ranking_visibility) ON public.trainers FROM anon;
--   REVOKE SELECT (ranking_visibility) ON public.trainers FROM authenticated;
--   REVOKE UPDATE (ranking_visibility) ON public.trainers FROM authenticated;
--   ALTER TABLE public.trainers DROP COLUMN ranking_visibility;
--   NOTIFY pgrst, 'reload schema';
