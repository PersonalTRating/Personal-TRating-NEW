-- ════════════════════════════════════════════════════════════════
-- COACHCARDS — B3: Column-level SELECT restriction on public.trainers
-- File:    supabase_b3_column_grants.sql
-- Status:  NOT YET EXECUTED — FOR REVIEW ONLY
--
-- Prerequisites (must be live before running this file):
--   B1  supabase_b1_get_own_trainer_profile.sql  — DEPLOYED
--   B2  dashboard.astro changes                  — DEPLOYED
--   ∗   supabase_location_confirm.sql            — DEPLOYED
--       (provides the trainers_protect_geo trigger)
--
-- [SRC] = claim confirmed by reading application source files.
-- [LIVE] = requires a production Supabase query to confirm.
-- ════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════
-- ARCHITECTURE NOTES
-- ════════════════════════════════════════════════════════════════

-- (A) Table-level vs column-level interaction
--     Supabase's GRANT ALL on public.trainers includes a table-level
--     SELECT for anon, authenticated and service_role. A table-level
--     GRANT ALL overrides any column-level REVOKE — a column-level
--     REVOKE issued while the table-level grant exists is advisory
--     only. B3 therefore REVOKES table-level SELECT first (Step 1b),
--     then issues column-level GRANT for approved columns (Steps 1d-e).
--     INSERT, UPDATE, DELETE, REFERENCES and TRIGGER are not revoked
--     and are unaffected. service_role is not touched.

-- (B) Clearing pre-existing column grants — dynamic approach
--     A table-level REVOKE (Step 1b) does NOT remove column-level
--     grants that already exist. Step 1c dynamically enumerates and
--     REVOKEs ALL existing column-level SELECT grants to anon,
--     authenticated and PUBLIC on this table, regardless of which
--     columns they cover. Steps 1d-e then grant exactly the approved
--     whitelist. Step 1f asserts that nothing outside the whitelist
--     remains. No hardcoded list of private columns is required; the
--     approach is resilient to schema additions.

-- (C) PUBLIC pseudo-role
--     Every role inherits privileges granted to PUBLIC. Step 1b
--     includes REVOKE FROM PUBLIC (no-op if no PUBLIC SELECT grant
--     exists). Step 1c includes PUBLIC in the dynamic column-level
--     REVOKE enumeration. Step 1f asserts no PUBLIC column SELECT
--     remains after the migration.

-- (D) WHERE clause column privilege
--     PostgreSQL requires SELECT privilege on any column referenced
--     in a WHERE clause. All authenticated pages filter trainers by
--     user_id [SRC: signup.astro:727, login.astro:224,
--     account.astro:776+785, find-a-trainer.astro:1536,
--     for-trainers.astro:514, trainers/[id].astro:1058,
--     index.astro:1634]. All are inside if(session) guards —
--     authenticated role only. user_id is therefore in the
--     authenticated whitelist.
--     Privacy implication: authenticated users can read user_id
--     values from trainer rows visible to them via RLS. user_id is
--     a UUID; auth.users is inaccessible to authenticated. Risk is
--     low and the trade-off is necessary for the app to function.
--     Anon never filters by user_id; user_id is not in the anon list.

-- (E) RETURNING clause behaviour [SRC]
--     Profile save (dashboard.astro:3151): .update({...}).eq('id',id)
--       — no .select() → Prefer: return=minimal → NO RETURNING in SQL.
--     Avatar update (dashboard.astro:3736): same pattern.
--     Signup INSERT (signup.astro:731): no .select() → same.
--     PostgREST builds RETURNING by enumerating only columns the role
--     has SELECT on; it never issues a literal RETURNING * to the DB.
--     A .select() after a write returns only whitelisted columns
--     silently. No application path issues an explicit RETURNING on
--     a private column [SRC: confirmed by full audit of all
--     .update()/.insert() calls on trainers in the codebase].

-- (F) RLS policy interaction
--     RLS row visibility is decided before column grants restrict
--     what is readable within a visible row. B3 does not modify any
--     RLS policy. Production policies confirmed present [LIVE Step 0f]:
--       "PTs can insert own profile"     — INSERT WITH CHECK
--       "PTs can update own profile"     — UPDATE USING
--       "Trainers can update own profile"— UPDATE USING
--     These enforce row ownership on writes and are orthogonal to B3.

-- (G) trainers_protect_geo trigger — correct execution order
--     The PostgreSQL execution sequence for an UPDATE statement is:
--       1. ACL / privilege check (table-level and column-level grants)
--       2. RLS evaluation (USING clause for row visibility;
--          WITH CHECK for new values)
--       3. BEFORE row-level triggers fire here
--       4. Row modification written
--       5. AFTER row-level triggers
--     The cc_protect_geo_columns() BEFORE UPDATE trigger therefore
--     fires AFTER privilege checks and RLS, but BEFORE the row
--     modification is written.
--
--     Why the trigger is the effective guard despite firing third:
--     The column-level REVOKE UPDATE in supabase_location_confirm.sql
--     is issued against a table that has GRANT ALL at the table level.
--     The table-level grant overrides the column REVOKE, making the
--     REVOKE advisory only. Privilege checks (step 1) therefore pass
--     for geo columns. The RLS UPDATE policy checks only row ownership
--     (user_id = auth.uid()), which passes for an own-row update.
--     The trigger (step 3) is consequently the only mechanism that
--     actually intercepts and rejects the change.
--
--     What the trigger protects [SRC supabase_location_confirm.sql]:
--       Check A — cc_postcode: any UPDATE leaving cc_postcode IS NOT
--         NULL is rejected by ALL roles (column is retired).
--       Check B — geo columns: if any of cc_country, cc_local_area,
--         location_confirmed, location_confirmed_at, location_source,
--         location_cooldown_until, location_mapping_version changes
--         AND current_user NOT IN ('postgres','service_role',
--         'supabase_admin'), an exception is raised.
--     B3 does not modify this trigger. [LIVE Step 0h confirms body]
-- ════════════════════════════════════════════════════════════════


-- ════════════════════════════════════════════════════════════════
-- STEP 0 — READ-ONLY PRE-FLIGHT QUERIES
-- Run these queries first, outside any transaction. Review each
-- result before executing the migration in Step 1.
-- ════════════════════════════════════════════════════════════════

-- 0a. B1 RPC: must exist, be SECURITY DEFINER and return jsonb. [LIVE]
SELECT proname,
       prosecdef          AS is_security_definer,
       prorettype::regtype AS return_type
FROM   pg_proc
WHERE  pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND  proname      = 'get_own_trainer_profile';
-- EXPECTED: 1 row — is_security_definer = true, return_type = jsonb.

-- 0b. B1 RPC execute grants.                                    [LIVE]
SELECT
  has_function_privilege('anon',          'get_own_trainer_profile()', 'execute') AS anon_execute,
  has_function_privilege('authenticated', 'get_own_trainer_profile()', 'execute') AS auth_execute;
-- EXPECTED: anon_execute = false, auth_execute = true.

-- 0c. RLS enabled on trainers.                                  [LIVE]
SELECT relname, relrowsecurity AS rls_enabled, relforcerowsecurity
FROM   pg_class
WHERE  relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND  relname      = 'trainers';
-- EXPECTED: rls_enabled = true.

-- 0d. Current table-level privileges.                           [LIVE]
SELECT grantee, privilege_type, is_grantable
FROM   information_schema.table_privileges
WHERE  table_schema = 'public'
  AND  table_name   = 'trainers'
ORDER  BY grantee, privilege_type;
-- Review before running Step 1b. Expect SELECT rows for anon,
-- authenticated and service_role. Step 1b revokes SELECT only
-- from anon, authenticated and PUBLIC. All other rows are unchanged.

-- 0e. Existing column-level SELECT grants (expect 0 rows).     [LIVE]
SELECT column_name, grantee, privilege_type
FROM   information_schema.column_privileges
WHERE  table_schema = 'public'
  AND  table_name   = 'trainers'
  AND  privilege_type = 'SELECT'
ORDER  BY column_name, grantee;
-- EXPECTED: 0 rows on a clean pre-B3 database. Any rows mean
-- a prior partial run; Step 1c handles them dynamically.

-- 0f. Production RLS policies on trainers.                     [LIVE]
SELECT policyname, cmd, roles, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename  = 'trainers';
-- B3 does not add, remove or alter any policy. Compare this output
-- against Step 3d (post-execution) to confirm policies are unchanged.

-- 0g. All columns in public.trainers.                          [LIVE]
SELECT column_name, data_type, is_nullable
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name   = 'trainers'
ORDER  BY ordinal_position;
-- Cross-check the GRANT lists in Steps 1d-e against this output.
-- Every column in the GRANT must exist here; the pre-flight
-- assertion (Step 1a) will abort if any is absent. Any column
-- present here but absent from both GRANT lists becomes inaccessible
-- to anon and authenticated after B3 (service_role unaffected).

-- 0h. Trigger function definition — live inspection.           [LIVE]
SELECT pg_get_functiondef(p.oid)
FROM   pg_proc p
WHERE  p.pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND  p.proname      = 'cc_protect_geo_columns';
-- Read the returned body and confirm:
--   (A) The function rejects any UPDATE where NEW.cc_postcode IS NOT NULL.
--   (B) The function checks if cc_country, cc_local_area,
--       location_confirmed, location_confirmed_at, location_source,
--       location_cooldown_until or location_mapping_version
--       IS DISTINCT FROM OLD, and if current_user is not in
--       ('postgres','service_role','supabase_admin'), raises EXCEPTION.
-- If the body does not contain these protections, B3's security
-- model for geo columns does not hold — do not proceed.
-- Note: The trigger fires AFTER PostgreSQL privilege checks and RLS,
-- but BEFORE the row modification is written (see architecture note G).


-- ════════════════════════════════════════════════════════════════
-- STEP 1 — THE MIGRATION (ATOMIC TRANSACTION)
-- Steps 1a through 1f execute atomically. Any RAISE EXCEPTION
-- rolls back the entire transaction — the schema is unchanged.
-- ════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────
-- 1a. Pre-flight assertion
-- All checks abort the transaction on failure.
-- ────────────────────────────────────────────────────────────────
DO $preflight$
DECLARE
  _missing      TEXT[];
  _rpc_secdef   BOOLEAN;
  _anon_exec    BOOLEAN;
  _auth_exec    BOOLEAN;
  _trig_present BOOLEAN;
  _rls_on       BOOLEAN;
  _required     TEXT[] := ARRAY[
    -- 31 columns for anon whitelist
    'id',              'name',            'username',         'business_name',
    'city',            'location',        'bio',              'intro_message',
    'specialty',       'coaching_type',   'cert',
    'bmp_score',       'star_rating',     'review_count',
    'avatar_url',      'avatar_initials', 'avatar_bg',        'avatar_color',
    'is_trending',     'gyms',            'hero_theme',
    'social_facebook', 'social_instagram','social_whatsapp',  'social_email',
    'accepts_bookings','booking_url',
    'location_confirmed','cc_country',    'cc_local_area',    'is_active',
    -- + user_id for authenticated WHERE clauses (32nd column)
    'user_id'
  ];
BEGIN
  -- Check all 32 required columns exist.
  SELECT ARRAY_AGG(r ORDER BY r) INTO _missing
  FROM   UNNEST(_required) AS r
  WHERE  NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE  table_schema = 'public'
      AND  table_name   = 'trainers'
      AND  column_name  = r
  );
  IF _missing IS NOT NULL AND array_length(_missing, 1) > 0 THEN
    RAISE EXCEPTION
      E'B3 PRE-FLIGHT FAILED — required columns missing from public.trainers:\n  %\n'
      'Resolve the schema difference before running B3.',
      array_to_string(_missing, ', ');
  END IF;

  -- B1 RPC must exist and be SECURITY DEFINER.
  SELECT prosecdef INTO _rpc_secdef
  FROM   pg_proc
  WHERE  pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    AND  proname      = 'get_own_trainer_profile';
  IF _rpc_secdef IS NULL THEN
    RAISE EXCEPTION 'B3 PRE-FLIGHT FAILED — get_own_trainer_profile() not found. Deploy B1 first.';
  END IF;
  IF NOT _rpc_secdef THEN
    RAISE EXCEPTION 'B3 PRE-FLIGHT FAILED — get_own_trainer_profile() is not SECURITY DEFINER. B1 deployment incomplete.';
  END IF;

  -- B1 execute grants: anon must be denied, authenticated must be granted.
  SELECT has_function_privilege('anon',          'get_own_trainer_profile()', 'execute'),
         has_function_privilege('authenticated', 'get_own_trainer_profile()', 'execute')
  INTO   _anon_exec, _auth_exec;
  IF _anon_exec THEN
    RAISE EXCEPTION
      'B3 PRE-FLIGHT FAILED — anon can execute get_own_trainer_profile(). '
      'The B1 REVOKE EXECUTE FROM anon has not been applied.';
  END IF;
  IF NOT _auth_exec THEN
    RAISE EXCEPTION
      'B3 PRE-FLIGHT FAILED — authenticated cannot execute get_own_trainer_profile(). '
      'The B1 GRANT EXECUTE TO authenticated has not been applied.';
  END IF;

  -- trainers_protect_geo trigger must exist.
  SELECT TRUE INTO _trig_present
  FROM   information_schema.triggers
  WHERE  event_object_schema = 'public'
    AND  event_object_table  = 'trainers'
    AND  trigger_name        = 'trainers_protect_geo';
  IF NOT FOUND THEN
    RAISE EXCEPTION
      'B3 PRE-FLIGHT FAILED — trainers_protect_geo trigger missing. '
      'Deploy supabase_location_confirm.sql first.';
  END IF;

  -- RLS must be enabled on trainers.
  SELECT relrowsecurity INTO _rls_on
  FROM   pg_class
  WHERE  relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
    AND  relname      = 'trainers';
  IF NOT _rls_on THEN
    RAISE EXCEPTION
      'B3 PRE-FLIGHT FAILED — RLS is not enabled on public.trainers. '
      'Row-level access control is a security prerequisite. '
      'Enable RLS before running B3.';
  END IF;

  RAISE NOTICE
    'B3 pre-flight passed: 32 required columns present; '
    'RPC exists (SECURITY DEFINER, anon denied, authenticated granted); '
    'trainers_protect_geo trigger present; RLS enabled.';
END
$preflight$;


-- ────────────────────────────────────────────────────────────────
-- 1b. Revoke table-level and PUBLIC SELECT
-- Removes the GRANT ALL's SELECT component for anon, authenticated
-- and PUBLIC. INSERT/UPDATE/DELETE/REFERENCES/TRIGGER are unchanged.
-- REVOKE FROM PUBLIC is a no-op if no PUBLIC SELECT grant exists.
-- service_role is not touched.
-- ────────────────────────────────────────────────────────────────
REVOKE SELECT ON public.trainers FROM PUBLIC;
REVOKE SELECT ON public.trainers FROM anon;
REVOKE SELECT ON public.trainers FROM authenticated;


-- ────────────────────────────────────────────────────────────────
-- 1c. Revoke ALL pre-existing column-level SELECT grants
--
-- Dynamically enumerates and revokes every column-level SELECT
-- grant currently held by anon, authenticated or PUBLIC on this
-- table — regardless of which columns they cover. This handles
-- prior partial B3 runs and any ad-hoc grants that may exist.
-- No hardcoded list of private columns is required; every grant
-- outside the whitelist is cleared before the whitelist is set.
-- ────────────────────────────────────────────────────────────────
DO $revoke_all_column_selects$
DECLARE
  _rec   RECORD;
  _count INT := 0;
BEGIN
  -- Read pg_attribute.attacl directly for explicit column-level SELECT grants.
  -- information_schema.column_privileges may include effective privileges derived
  -- from a table-level GRANT (relacl); attacl contains only explicit column-level
  -- ACL entries, so this query is unambiguous about what was actually granted
  -- per-column versus what was inherited from the table-level grant revoked
  -- in Step 1b. grantee OID 0 is the PUBLIC pseudo-role.
  FOR _rec IN
    SELECT a.attname AS column_name,
           CASE WHEN acl.grantee = 0
                THEN 'PUBLIC'
                ELSE pg_catalog.pg_get_userbyid(acl.grantee)
           END       AS grantee
    FROM   pg_attribute  a
    JOIN   pg_class      c ON c.oid = a.attrelid
    JOIN   pg_namespace  n ON n.oid = c.relnamespace,
    LATERAL aclexplode(COALESCE(a.attacl, ARRAY[]::aclitem[])) AS acl
    WHERE  n.nspname          = 'public'
      AND  c.relname          = 'trainers'
      AND  a.attnum           > 0
      AND  NOT a.attisdropped
      AND  acl.privilege_type = 'SELECT'
      AND  (
             acl.grantee = 0
             OR pg_catalog.pg_get_userbyid(acl.grantee) IN ('anon', 'authenticated')
           )
    ORDER  BY grantee, a.attname
  LOOP
    -- PUBLIC is a GRANT/REVOKE keyword, not a regular identifier.
    -- Using %I would produce "PUBLIC" (quoted), which is incorrect.
    IF _rec.grantee = 'PUBLIC' THEN
      EXECUTE format(
        'REVOKE SELECT (%I) ON public.trainers FROM PUBLIC',
        _rec.column_name
      );
    ELSE
      EXECUTE format(
        'REVOKE SELECT (%I) ON public.trainers FROM %I',
        _rec.column_name, _rec.grantee
      );
    END IF;
    RAISE NOTICE 'Cleared column SELECT: % FROM %.', _rec.column_name, _rec.grantee;
    _count := _count + 1;
  END LOOP;
  RAISE NOTICE 'Step 1c: % pre-existing column-level SELECT grant(s) cleared.', _count;
END
$revoke_all_column_selects$;


-- ────────────────────────────────────────────────────────────────
-- 1d. Grant approved display columns to anon (31 columns)
--
-- Confirmed against every client-side anon query [SRC]:
--   trainers/[id].astro client: bmp_score, star_rating, avatar_url,
--     avatar_color, city, bio, specialty, hero_theme, location_confirmed
--   account.astro reviews join: name, avatar_initials, avatar_bg,
--     avatar_color, bmp_score, review_count
--   account.astro conversations join: name, avatar_initials,
--     avatar_bg, avatar_color
--   dashboard leaderboard: id, name, username, city, location,
--     specialty, bmp_score, review_count, avatar_initials, avatar_bg,
--     avatar_color, avatar_url, cc_country, cc_local_area,
--     location_confirmed
--   admin.astro reviews join: name, city
-- is_active is required for WHERE is_active = TRUE filters.
-- All 31 columns confirmed present by the pre-flight assertion.
-- ────────────────────────────────────────────────────────────────
GRANT SELECT (
  id,              name,              username,          business_name,
  city,            location,          bio,               intro_message,
  specialty,       coaching_type,     cert,
  bmp_score,       star_rating,       review_count,
  avatar_url,      avatar_initials,   avatar_bg,         avatar_color,
  is_trending,     gyms,              hero_theme,
  social_facebook, social_instagram,  social_whatsapp,   social_email,
  accepts_bookings,booking_url,
  location_confirmed, cc_country,     cc_local_area,     is_active
) ON public.trainers TO anon;


-- ────────────────────────────────────────────────────────────────
-- 1e. Grant approved display columns to authenticated (32 columns)
--
-- Identical to anon plus user_id. user_id is required because
-- authenticated queries filter trainers by user_id in WHERE clauses
-- (see architecture note D). PostgreSQL requires SELECT privilege
-- on a column to reference it in WHERE. All such queries run as
-- authenticated (inside if(session) guards) — anon never uses
-- user_id in a WHERE clause.
--
-- Private fields (postcode, location_cooldown_until) are not
-- granted here. The dashboard reads them exclusively via
-- get_own_trainer_profile() (SECURITY DEFINER, runs as postgres,
-- bypasses column-level grants).
-- ────────────────────────────────────────────────────────────────
GRANT SELECT (
  id,              name,              username,          business_name,
  city,            location,          bio,               intro_message,
  specialty,       coaching_type,     cert,
  bmp_score,       star_rating,       review_count,
  avatar_url,      avatar_initials,   avatar_bg,         avatar_color,
  is_trending,     gyms,              hero_theme,
  social_facebook, social_instagram,  social_whatsapp,   social_email,
  accepts_bookings,booking_url,
  location_confirmed, cc_country,     cc_local_area,     is_active,
  user_id
) ON public.trainers TO authenticated;


-- ────────────────────────────────────────────────────────────────
-- 1f. Whitelist assertion
--
-- Verifies that after the GRANTs above, no SELECT access exists
-- for anon, authenticated or PUBLIC outside the approved column
-- lists. Any unexpected privilege causes an exception and rolls
-- back the entire transaction — the schema is left unchanged.
-- ────────────────────────────────────────────────────────────────
DO $assert_whitelist$
DECLARE
  _approved_anon TEXT[] := ARRAY[
    'id',              'name',            'username',         'business_name',
    'city',            'location',        'bio',              'intro_message',
    'specialty',       'coaching_type',   'cert',
    'bmp_score',       'star_rating',     'review_count',
    'avatar_url',      'avatar_initials', 'avatar_bg',        'avatar_color',
    'is_trending',     'gyms',            'hero_theme',
    'social_facebook', 'social_instagram','social_whatsapp',  'social_email',
    'accepts_bookings','booking_url',
    'location_confirmed','cc_country',    'cc_local_area',    'is_active'
  ];
  _approved_auth TEXT[] := ARRAY[
    'id',              'name',            'username',         'business_name',
    'city',            'location',        'bio',              'intro_message',
    'specialty',       'coaching_type',   'cert',
    'bmp_score',       'star_rating',     'review_count',
    'avatar_url',      'avatar_initials', 'avatar_bg',        'avatar_color',
    'is_trending',     'gyms',            'hero_theme',
    'social_facebook', 'social_instagram','social_whatsapp',  'social_email',
    'accepts_bookings','booking_url',
    'location_confirmed','cc_country',    'cc_local_area',    'is_active',
    'user_id'
  ];
  _private_cols TEXT[] := ARRAY[
    'postcode', 'email', 'location_cooldown_until',
    'cc_postcode', 'location_confirmed_at',
    'location_source', 'location_mapping_version'
  ];
  _rec         RECORD;
  _bad_rows    BOOLEAN := FALSE;
  _private_col TEXT;
BEGIN
  -- ── Grant-record checks (explicit ACL entries) ──────────────────────
  -- Check 1: No table-level SELECT for anon, authenticated or PUBLIC.
  IF EXISTS (
    SELECT 1 FROM information_schema.table_privileges
    WHERE  table_schema   = 'public'
      AND  table_name     = 'trainers'
      AND  privilege_type = 'SELECT'
      AND  grantee        IN ('anon', 'authenticated', 'PUBLIC')
  ) THEN
    RAISE EXCEPTION
      'B3 ASSERTION FAILED — table-level SELECT still present for anon, '
      'authenticated or PUBLIC. Transaction rolled back.';
  END IF;

  -- Check 2: No column-level SELECT for PUBLIC (would be inherited by all roles).
  IF EXISTS (
    SELECT 1 FROM information_schema.column_privileges
    WHERE  table_schema   = 'public'
      AND  table_name     = 'trainers'
      AND  privilege_type = 'SELECT'
      AND  grantee        = 'PUBLIC'
  ) THEN
    RAISE EXCEPTION
      'B3 ASSERTION FAILED — column-level SELECT granted to PUBLIC remains. '
      'All roles inherit this. Transaction rolled back.';
  END IF;

  -- Check 3: No column SELECT for anon outside the approved list.
  FOR _rec IN
    SELECT column_name
    FROM   information_schema.column_privileges
    WHERE  table_schema   = 'public'
      AND  table_name     = 'trainers'
      AND  privilege_type = 'SELECT'
      AND  grantee        = 'anon'
      AND  column_name    != ALL(_approved_anon)
  LOOP
    RAISE WARNING 'UNEXPECTED: anon has SELECT on column [%].', _rec.column_name;
    _bad_rows := TRUE;
  END LOOP;

  -- Check 4: No column SELECT for authenticated outside the approved list.
  FOR _rec IN
    SELECT column_name
    FROM   information_schema.column_privileges
    WHERE  table_schema   = 'public'
      AND  table_name     = 'trainers'
      AND  privilege_type = 'SELECT'
      AND  grantee        = 'authenticated'
      AND  column_name    != ALL(_approved_auth)
  LOOP
    RAISE WARNING 'UNEXPECTED: authenticated has SELECT on column [%].', _rec.column_name;
    _bad_rows := TRUE;
  END LOOP;

  IF _bad_rows THEN
    RAISE EXCEPTION
      'B3 ASSERTION FAILED — SELECT access exists outside the approved column '
      'lists (see WARNING messages above). Transaction rolled back. '
      'Investigate the unexpected grants and re-run.';
  END IF;

  -- ── Effective privilege checks ───────────────────────────────────────
  -- has_table_privilege / has_column_privilege resolve the full effective
  -- access PostgreSQL would grant, including any path through role
  -- inheritance, rather than examining ACL records alone. These checks
  -- catch any residual access not visible as an explicit grant record.

  -- Check 5: Effective table-level SELECT must be absent for anon and authenticated.
  IF has_table_privilege('anon', 'public.trainers', 'SELECT') THEN
    RAISE EXCEPTION
      'B3 ASSERTION FAILED — anon still has effective table-level SELECT on '
      'public.trainers. Transaction rolled back.';
  END IF;
  IF has_table_privilege('authenticated', 'public.trainers', 'SELECT') THEN
    RAISE EXCEPTION
      'B3 ASSERTION FAILED — authenticated still has effective table-level SELECT on '
      'public.trainers. Transaction rolled back.';
  END IF;

  -- Check 6: Known private columns must not be effectively readable.
  -- Columns absent from the current schema are skipped with a notice (non-fatal).
  FOREACH _private_col IN ARRAY _private_cols LOOP
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE  table_schema = 'public'
        AND  table_name   = 'trainers'
        AND  column_name  = _private_col
    ) THEN
      RAISE NOTICE 'Private column [%] not in schema — effective check skipped.', _private_col;
      CONTINUE;
    END IF;
    IF has_column_privilege('anon', 'public.trainers', _private_col, 'SELECT') THEN
      RAISE EXCEPTION
        'B3 ASSERTION FAILED — anon has effective SELECT on private column [%]. '
        'Transaction rolled back.', _private_col;
    END IF;
    IF has_column_privilege('authenticated', 'public.trainers', _private_col, 'SELECT') THEN
      RAISE EXCEPTION
        'B3 ASSERTION FAILED — authenticated has effective SELECT on private column [%]. '
        'Transaction rolled back.', _private_col;
    END IF;
  END LOOP;

  -- Check 7: Sample whitelist columns must be effectively readable.
  -- Verifies Steps 1d-e GRANTs actually took effect.
  IF NOT has_column_privilege('anon', 'public.trainers', 'id', 'SELECT') THEN
    RAISE EXCEPTION
      'B3 ASSERTION FAILED — anon cannot read whitelist column [id]. '
      'Step 1d GRANTs may not have applied. Transaction rolled back.';
  END IF;
  IF NOT has_column_privilege('authenticated', 'public.trainers', 'user_id', 'SELECT') THEN
    RAISE EXCEPTION
      'B3 ASSERTION FAILED — authenticated cannot read whitelist column [user_id]. '
      'Step 1e GRANTs may not have applied. Transaction rolled back.';
  END IF;

  RAISE NOTICE
    'B3 whitelist assertion passed: no SELECT access exists for anon, authenticated or PUBLIC '
    'outside the approved column lists; effective table-level SELECT absent; '
    'known private columns confirmed blocked; sample whitelist columns confirmed readable.';
END
$assert_whitelist$;


COMMIT;


-- ════════════════════════════════════════════════════════════════
-- STEP 2 — SCHEMA CACHE REFRESH
-- Run immediately after COMMIT.
-- ════════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';


-- ════════════════════════════════════════════════════════════════
-- STEP 3 — POST-EXECUTION VERIFICATION (read-only)
-- ════════════════════════════════════════════════════════════════

-- 3a. Column-level SELECT grants.
SELECT column_name, grantee, privilege_type
FROM   information_schema.column_privileges
WHERE  table_schema = 'public'
  AND  table_name   = 'trainers'
  AND  privilege_type = 'SELECT'
ORDER  BY column_name, grantee;
-- EXPECTED: exactly 31 rows for anon (no user_id) and 32 rows for
-- authenticated (includes user_id). No rows for any private column
-- (postcode, email, location_cooldown_until, etc.) for any grantee.

-- 3b. Table-level SELECT removed for anon and authenticated.
SELECT grantee, privilege_type
FROM   information_schema.table_privileges
WHERE  table_schema = 'public'
  AND  table_name   = 'trainers'
  AND  privilege_type = 'SELECT'
ORDER  BY grantee;
-- EXPECTED: only service_role (and postgres/supabase_admin).
-- anon and authenticated must not appear here.

-- 3c. INSERT and UPDATE still present for authenticated.
SELECT grantee, privilege_type
FROM   information_schema.table_privileges
WHERE  table_schema = 'public'
  AND  table_name   = 'trainers'
  AND  grantee      = 'authenticated'
ORDER  BY privilege_type;
-- EXPECTED: DELETE, INSERT, REFERENCES, TRIGGER, UPDATE.
-- SELECT must not appear (it is now column-level only).

-- 3d. RLS policies unchanged.
SELECT policyname, cmd, roles, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  tablename  = 'trainers';
-- EXPECTED: identical to Step 0f output. B3 must not have altered
-- any policy.

-- 3e. trainers_protect_geo trigger unchanged.
SELECT trigger_name, event_manipulation, action_timing
FROM   information_schema.triggers
WHERE  event_object_schema = 'public'
  AND  event_object_table  = 'trainers'
  AND  trigger_name        = 'trainers_protect_geo';
-- EXPECTED: 1 row, BEFORE UPDATE. Must match Step 0h.

-- 3f. B1 RPC execute grants unchanged.
SELECT
  has_function_privilege('anon',          'get_own_trainer_profile()', 'execute') AS anon_execute,
  has_function_privilege('authenticated', 'get_own_trainer_profile()', 'execute') AS auth_execute;
-- EXPECTED: anon_execute = false, auth_execute = true.

-- 3g. Smoke tests — run each block separately in Supabase SQL editor.
--
--   TEST 1 — anon reads safe columns (should succeed):
--     SET ROLE anon;
--     SELECT id, name, bmp_score, location_confirmed,
--            cc_country, cc_local_area, is_active
--     FROM   public.trainers
--     WHERE  is_active = TRUE LIMIT 5;
--     RESET ROLE;
--
--   TEST 2 — anon blocked from postcode (should error):
--     SET ROLE anon;
--     SELECT id, postcode FROM public.trainers LIMIT 1;
--     RESET ROLE;
--     EXPECTED: ERROR — permission denied for column postcode.
--
--   TEST 3 — anon blocked from user_id in WHERE (should error):
--     SET ROLE anon;
--     SELECT id FROM public.trainers WHERE user_id IS NOT NULL LIMIT 1;
--     RESET ROLE;
--     EXPECTED: ERROR — permission denied for column user_id.
--
--   TEST 4 — authenticated can filter by user_id (should not error):
--     SET ROLE authenticated;
--     SELECT id FROM public.trainers WHERE user_id = auth.uid();
--     RESET ROLE;
--     EXPECTED: no error (0 rows outside real JWT context is correct).
--
--   TEST 5 — authenticated blocked from postcode (should error):
--     SET ROLE authenticated;
--     SELECT id, postcode FROM public.trainers LIMIT 1;
--     RESET ROLE;
--     EXPECTED: ERROR — permission denied for column postcode.
--
--   TEST 6 — get_own_trainer_profile() returns private fields:
--     From a real authenticated trainer session (live dashboard):
--     SELECT get_own_trainer_profile();
--     EXPECTED: full JSONB including postcode and location_cooldown_until.
--
--   TEST 7 — profile save still works:
--     Perform a profile save in the live dashboard. saveProfile sends
--     .update({name,bio,...}).eq('id',trainerId) with no .select().
--     No RETURNING clause is generated. EXPECTED: save succeeds.


-- ════════════════════════════════════════════════════════════════
-- ROLLBACK PROCEDURE — TWO OPTIONS
-- ════════════════════════════════════════════════════════════════

-- ── OPTION A: Corrective grant (preferred — no exposure of private data)
-- ─────────────────────────────────────────────────────────────────────
-- Use when a specific column is missing from the whitelist and an
-- application query fails with "permission denied for column X".
-- This does not expose private columns and does not require a full rollback.
--
-- Identify the missing column from the error, then run:
--
--   -- Add to anon whitelist (if the column is needed publicly):
--   GRANT SELECT (missing_column_name) ON public.trainers TO anon;
--
--   -- Add to authenticated whitelist (if needed for authenticated queries):
--   GRANT SELECT (missing_column_name) ON public.trainers TO authenticated;
--
--   NOTIFY pgrst, 'reload schema';
--
-- Then re-run Step 3a to confirm the column appears and no private
-- column has been accidentally granted.
--
-- ── OPTION B: Full rollback (emergency only — EXPOSES PRIVATE COLUMNS)
-- ─────────────────────────────────────────────────────────────────────
-- WARNING: This restores the pre-B3 Supabase default table-level
-- GRANT ALL SELECT to anon and authenticated. ALL columns in
-- public.trainers immediately become readable again, including
-- postcode, email, location_cooldown_until and user_id for anon.
-- Use only when the application is critically broken and B3 must be
-- fully removed for immediate recovery. Re-apply B3 (or a corrected
-- version) as soon as the issue is diagnosed.
--
-- The pre-B3 state was table-level GRANT ALL (Supabase default).
-- This rollback restores to that state. If your pre-B3 state
-- included column-level grants, re-apply them after this rollback.
--
-- BEGIN;
--
-- -- Remove all column-level SELECT grants added by B3.
-- -- (These are the only column-level SELECT grants that should exist
-- -- after a clean B3 run. If Step 0e showed pre-existing grants
-- -- before B3, restore those too from your Step 0e snapshot.)
-- REVOKE SELECT (
--   id,              name,              username,          business_name,
--   city,            location,          bio,               intro_message,
--   specialty,       coaching_type,     cert,
--   bmp_score,       star_rating,       review_count,
--   avatar_url,      avatar_initials,   avatar_bg,         avatar_color,
--   is_trending,     gyms,              hero_theme,
--   social_facebook, social_instagram,  social_whatsapp,   social_email,
--   accepts_bookings,booking_url,
--   location_confirmed, cc_country,     cc_local_area,     is_active
-- ) ON public.trainers FROM anon;
--
-- REVOKE SELECT (
--   id,              name,              username,          business_name,
--   city,            location,          bio,               intro_message,
--   specialty,       coaching_type,     cert,
--   bmp_score,       star_rating,       review_count,
--   avatar_url,      avatar_initials,   avatar_bg,         avatar_color,
--   is_trending,     gyms,              hero_theme,
--   social_facebook, social_instagram,  social_whatsapp,   social_email,
--   accepts_bookings,booking_url,
--   location_confirmed, cc_country,     cc_local_area,     is_active,
--   user_id
-- ) ON public.trainers FROM authenticated;
--
-- -- Restore table-level SELECT.
-- -- WARNING: This immediately exposes all columns to anon and authenticated.
-- GRANT SELECT ON public.trainers TO anon;
-- GRANT SELECT ON public.trainers TO authenticated;
--
-- COMMIT;
-- NOTIFY pgrst, 'reload schema';
--
-- After Option B, re-run Steps 0d and 0e to confirm the pre-B3 state
-- is restored (table-level SELECT rows present; 0 column-level rows).
-- Diagnose the regression and re-apply a corrected B3 promptly.


-- ════════════════════════════════════════════════════════════════
-- RISK ASSESSMENT
-- [SRC] confirmed by source-code audit | [LIVE] requires production query
-- ════════════════════════════════════════════════════════════════

-- 1. Private SELECT access eliminated
--    ADDRESSED. Step 1c dynamically revokes ALL existing column-level
--    SELECT grants to anon, authenticated and PUBLIC before the
--    whitelist is applied. Step 1f asserts nothing outside the
--    approved lists remains. The assertion aborts the transaction if
--    any unexpected grant survives. [LIVE Step 3a confirms post-run]

-- 2. Public display columns preserved
--    ADDRESSED. All columns required by every public-facing query
--    are in the anon whitelist [SRC: full audit of trainers SELECTs
--    across index.astro, find-a-trainer.astro, TrainerCard.astro,
--    trainers/[id].astro, account.astro, admin.astro, dashboard.astro].

-- 3. get_own_trainer_profile() continues to return private fields
--    ADDRESSED. SECURITY DEFINER runs as postgres. Column grants on
--    authenticated do not apply. postcode and location_cooldown_until
--    are returned intact. [SRC B1 SQL file; LIVE Step 3f]

-- 4. INSERT / UPDATE compatibility
--    ADDRESSED. B3 revokes only SELECT. INSERT and UPDATE are
--    retained from the table-level GRANT ALL. All profile saves,
--    avatar updates and signup inserts are confirmed to use no
--    .select() after writes (Prefer: return=minimal, no RETURNING
--    clause generated). [SRC dashboard.astro:3151, 3736;
--    signup.astro:731]

-- 5. INSERT / UPDATE RLS policies preserved
--    B3 issues no CREATE/DROP/ALTER POLICY statements. [LIVE Step 3d
--    confirms policies are identical before and after.]

-- 6. trainers_protect_geo — effective despite firing after ACL/RLS
--    The column-level REVOKE UPDATE in supabase_location_confirm.sql
--    is advisory only under table-level GRANT ALL. Privilege checks
--    therefore pass for geo columns. The RLS UPDATE policy passes for
--    own-row updates. The trigger fires third (after privilege and
--    RLS), checks current_user, and raises EXCEPTION for any role
--    not in ('postgres','service_role','supabase_admin'). This is the
--    only effective geo-write guard. B3 does not alter the trigger.
--    [SRC supabase_location_confirm.sql; LIVE Step 0h confirms body]

-- 7. Column grant / table grant / PUBLIC interaction
--    ADDRESSED. Execution order: REVOKE PUBLIC table → REVOKE anon/
--    authenticated table → dynamic REVOKE all column grants (anon/
--    auth/PUBLIC) → GRANT whitelist → assert no excess grants.
--    Step 1f explicitly checks PUBLIC column grants in addition to
--    per-role column grants. service_role is untouched throughout.

-- 8. Location confirmation compatibility
--    UNAFFECTED. Netlify function uses service_role (bypasses all
--    grants). cc_confirm_location_atomic() is SECURITY DEFINER.
--    Dashboard reads location_cooldown_until via RPC only.

-- 9. Reviews and messaging compatibility
--    ADDRESSED. All columns read through reviews/conversations joins
--    (name, avatar_initials, avatar_bg, avatar_color, bmp_score,
--    review_count, city) are in the whitelist. [SRC account.astro,
--    admin.astro]

-- 10. Remaining risks B3 does not address
--    (a) postcode column (legacy) still present and writable.
--        B3 prevents SELECT but authenticated can still UPDATE it
--        via the profile save form. The data migration
--        (supabase_postcode_privacy.sql Step 2) that moves values
--        to trainer_private and NULLs this column is pending.
--    (b) No confirmed SELECT RLS policy for authenticated [LIVE
--        Step 0f]. If no SELECT policy exists, direct authenticated
--        table queries return 0 rows via RLS — but the app relies
--        on this for identity lookups (select('id').eq('user_id',…)).
--        Confirm the complete policy set in Step 0f before proceeding.
--    (c) Role inheritance chains not checked. If anon or authenticated
--        inherit from a role that has SELECT on trainers, B3's REVOKEs
--        do not cover that inheritance path. Supabase's standard role
--        model does not use such inheritance; confirm with
--        SELECT rolname, pg_get_role_definition(oid) FROM pg_roles
--        WHERE rolname IN ('anon','authenticated') if uncertain.
--    (d) service_role key exposure is out of scope for B3.
--    (e) PostgREST cache: brief sub-second window between COMMIT and
--        NOTIFY where stale cache is in effect. Unavoidable.

-- ════════════════════════════════════════════════════════════════
-- END OF B3 MIGRATION — supabase_b3_column_grants.sql
-- ════════════════════════════════════════════════════════════════
