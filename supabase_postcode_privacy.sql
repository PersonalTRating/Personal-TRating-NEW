-- ============================================================
-- COACHCARDS: Postcode Privacy — Private Table Migration
-- File: supabase_postcode_privacy.sql
-- Run order: after supabase_location_confirm.sql
--
-- Problem:
--   cc_postcode is stored on the trainers table. Supabase sets
--   GRANT ALL ON trainers TO anon by default, so column-level
--   REVOKE SELECT (cc_postcode) FROM anon — written in
--   supabase_location_confirm.sql — has no effect. Any caller
--   with the public anon key can execute:
--     GET /rest/v1/trainers?select=cc_postcode&id=eq.<uuid>
--   and retrieve a trainer's full postcode.
--
-- Solution:
--   1. Create trainer_private with cc_postcode.
--   2. Enable RLS: no anon policy (default deny),
--      authenticated trainers can SELECT their own row only.
--   3. Provide a read-only inspection query (Step 0 below) to
--      check existing trainers.cc_postcode values before running.
--   4. If existing values exist, migrate them atomically to
--      trainer_private and clear the source column (Step 2).
--   5. Create cc_confirm_location_atomic() RPC — writes to
--      both trainers and trainer_private in a single PostgreSQL
--      transaction. Only service_role may execute it.
--   6. Netlify function calls the RPC instead of two separate
--      writes — no partial state possible.
--
-- Access matrix after migration:
--   Role            trainers.cc_postcode   trainer_private.cc_postcode
--   ──────────────────────────────────────────────────────────────────
--   anon            NULL (never written)   Empty (RLS: no anon policy)
--   authenticated   NULL                   Own row only
--   service_role    NULL                   Full access (bypasses RLS)
--
-- Trigger: cc_protect_geo_columns() is SECURITY INVOKER.
--   Called from cc_confirm_location_atomic() (SECURITY DEFINER,
--   owner = postgres), current_user = postgres at trigger fire
--   time → allowed for geo-column writes. ✓
--   The RPC never sets trainers.cc_postcode to a non-NULL value,
--   so the retired-column check (Part A) never fires during
--   normal location confirmation. ✓
--
-- Ranking: get_trainer_ranks() queries cc_country, cc_local_area,
--   location_confirmed — none of which are in trainer_private.
--   No changes needed.
--
-- SAFE TO RE-RUN: CREATE TABLE IF NOT EXISTS; policies and
--   functions use CREATE OR REPLACE / IF NOT EXISTS guards.
-- DO NOT EXECUTE IN PRODUCTION without explicit approval.
-- ============================================================


-- ══════════════════════════════════════════════════════════════
-- STEP 0 — INSPECTION (run this SELECT before anything else)
--
-- Check whether any trainers currently have a cc_postcode value.
-- If the query returns rows you MUST run Step 2 to migrate them
-- before deploying the Netlify function update.
-- If the query returns zero rows, skip Step 2 and run Step 3+.
--
-- SELECT id, cc_postcode
-- FROM   trainers
-- WHERE  cc_postcode IS NOT NULL
--   AND  cc_postcode <> '';
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
-- STEP 1 — Create trainer_private table and RLS
-- ══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS trainer_private (
  trainer_id  UUID        PRIMARY KEY
                          REFERENCES trainers(id) ON DELETE CASCADE,
  cc_postcode TEXT        NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE trainer_private IS
  'Sensitive trainer location data. cc_postcode is stored here
   instead of on the public trainers table so it cannot be
   retrieved by anonymous PostgREST queries. Only the owning
   trainer (SELECT own row) and service_role (all operations)
   may access this table.';

COMMENT ON COLUMN trainer_private.cc_postcode IS
  'Full UK postcode validated and written by confirm-location.js
   (Netlify, service_role via cc_confirm_location_atomic RPC).
   Never stored on trainers table once this migration is applied.';

ALTER TABLE trainer_private ENABLE ROW LEVEL SECURITY;

-- Supabase default privileges include GRANT SELECT on public schema
-- tables to anon and authenticated. State them explicitly here so
-- the access matrix is self-documenting and survives privilege resets.
GRANT SELECT ON trainer_private TO authenticated;
GRANT SELECT ON trainer_private TO anon;
GRANT ALL    ON trainer_private TO service_role;

-- anon: SELECT grant exists (Supabase default) but NO policy below →
--       PostgREST returns an empty array; postcode is never visible.
-- authenticated: SELECT grant + own-row policy below.
-- service_role: bypasses RLS entirely.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename  = 'trainer_private'
      AND policyname = 'trainer_private_select_own'
  ) THEN
    EXECUTE $p$
      CREATE POLICY trainer_private_select_own
        ON trainer_private
        FOR SELECT
        TO authenticated
        USING (
          trainer_id = (
            SELECT id FROM trainers
            WHERE  user_id = auth.uid()
            LIMIT  1
          )
        )
    $p$;
    RAISE NOTICE 'Created trainer_private_select_own policy';
  ELSE
    RAISE NOTICE 'trainer_private_select_own already exists — skipped';
  END IF;
END $$;


-- ══════════════════════════════════════════════════════════════
-- STEP 2 — Migrate existing cc_postcode data (conditional)
--
-- Run ONLY if Step 0 returned rows.
-- This block is safe to run even if no rows exist (the IF guard
-- prevents any writes in that case).
--
-- Both the INSERT and the UPDATE run inside one DO block, which
-- PostgreSQL wraps in a single transaction. If either statement
-- fails, both roll back — no partial migration.
-- ══════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*)
  INTO   v_count
  FROM   trainers
  WHERE  cc_postcode IS NOT NULL
    AND  cc_postcode <> '';

  IF v_count = 0 THEN
    RAISE NOTICE 'Step 2: no existing postcodes found — nothing to migrate';
    RETURN;
  END IF;

  -- Copy every non-null postcode into trainer_private.
  -- COALESCE uses location_confirmed_at as the timestamp when available,
  -- falling back to NOW() for rows confirmed before that column existed.
  INSERT INTO trainer_private (trainer_id, cc_postcode, updated_at)
  SELECT
    id,
    cc_postcode,
    COALESCE(location_confirmed_at, NOW())
  FROM trainers
  WHERE cc_postcode IS NOT NULL
    AND cc_postcode <> ''
  ON CONFLICT (trainer_id) DO UPDATE
    SET cc_postcode = EXCLUDED.cc_postcode,
        updated_at  = EXCLUDED.updated_at
  WHERE trainer_private.cc_postcode IS DISTINCT FROM EXCLUDED.cc_postcode;

  -- Clear the now-migrated values from the public table.
  UPDATE trainers
  SET    cc_postcode = NULL
  WHERE  cc_postcode IS NOT NULL;

  RAISE NOTICE 'Step 2: migrated % postcode(s) to trainer_private', v_count;
END $$;


-- ══════════════════════════════════════════════════════════════
-- STEP 3 — Atomic confirmation RPC
--
-- cc_confirm_location_atomic() wraps the trainers UPDATE and the
-- trainer_private INSERT in one PostgreSQL transaction. If either
-- write fails, both roll back — the trainer cannot end up confirmed
-- without their postcode being stored, or vice versa.
--
-- Security:
--   • SECURITY DEFINER: runs as the function owner (postgres).
--     current_user = postgres → cc_protect_geo_columns trigger
--     (SECURITY INVOKER) sees 'postgres' → in the allow-list. ✓
--   • SET search_path: prevents search_path injection for a
--     SECURITY DEFINER function.
--   • REVOKE EXECUTE FROM PUBLIC then GRANT TO service_role only:
--     anon and authenticated cannot call this RPC directly via
--     PostgREST, even with a valid JWT.
--   • p_trainer_id is NEVER supplied by the client. The Netlify
--     function derives it server-side from the verified JWT:
--       db.auth.getUser(jwt) → user.id
--       SELECT id FROM trainers WHERE user_id = user.id
--     Only after this server-side lookup does the function call
--     this RPC with the resolved trainer_id.
--
-- Cooldown enforcement:
--   The UPDATE WHERE clause includes the cooldown condition, so
--   PostgreSQL's row lock prevents two concurrent requests from
--   both writing. The second request matches 0 rows and receives
--   success=false with the active cooldown_until timestamp.
--
-- Response: JSONB — does NOT include cc_postcode.
--   Success:  { "success": true }
--   Cooldown: { "success": false, "error": "cooldown_active",
--               "cooldown_until": "<ISO timestamp>" }
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION cc_confirm_location_atomic(
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
  -- ── Atomic cooldown-guarded update on trainers ──────────────────
  -- Row lock is acquired before WHERE evaluation. Two concurrent
  -- requests cannot both pass: the second finds the cooldown set
  -- by the first and matches 0 rows.
  UPDATE trainers
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
    -- Cooldown still active or trainer not found.
    SELECT location_cooldown_until
    INTO   v_cooldown_end
    FROM   trainers
    WHERE  id = p_trainer_id;

    RETURN jsonb_build_object(
      'success',        FALSE,
      'error',          'cooldown_active',
      'cooldown_until', v_cooldown_end
    );
  END IF;

  -- ── Store postcode in private table (same transaction) ──────────
  -- trainer_private has no anon SELECT policy, so this value
  -- cannot be retrieved via PostgREST by anonymous callers.
  INSERT INTO trainer_private (trainer_id, cc_postcode, updated_at)
  VALUES (p_trainer_id, p_postcode, p_confirmed_at)
  ON CONFLICT (trainer_id) DO UPDATE
    SET cc_postcode = EXCLUDED.cc_postcode,
        updated_at  = EXCLUDED.updated_at;

  RETURN jsonb_build_object('success', TRUE);
END;
$$;

COMMENT ON FUNCTION cc_confirm_location_atomic(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT) IS
  'Atomically updates trainers geo columns and stores the validated
   postcode in trainer_private. Called only by the Netlify
   confirm-location function (service_role). anon and authenticated
   roles are explicitly denied EXECUTE.';

-- Only service_role may execute this function.
-- REVOKE FROM PUBLIC removes the privilege from the base role that all
-- other roles inherit from. The explicit REVOKEs from anon and
-- authenticated are belt-and-suspenders: they survive any future
-- GRANT TO PUBLIC and make the access intent self-documenting.
REVOKE EXECUTE ON FUNCTION cc_confirm_location_atomic(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION cc_confirm_location_atomic(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION cc_confirm_location_atomic(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT) FROM authenticated;
GRANT  EXECUTE ON FUNCTION cc_confirm_location_atomic(UUID,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,TEXT) TO service_role;


-- ══════════════════════════════════════════════════════════════
-- STEP 4 — Refresh PostgREST schema cache
-- ══════════════════════════════════════════════════════════════

NOTIFY pgrst, 'reload schema';


-- ══════════════════════════════════════════════════════════════
-- VERIFICATION QUERIES (read-only — run after executing this file)
--
-- 1. Confirm trainer_private table and RLS exist:
-- SELECT tablename, rowsecurity
-- FROM   pg_tables
-- WHERE  tablename = 'trainer_private';
--
-- 2. Confirm the own-row SELECT policy exists:
-- SELECT policyname, roles, cmd, qual
-- FROM   pg_policies
-- WHERE  tablename = 'trainer_private';
--
-- 3. Confirm RPC execute permissions — expected result:
--   grantee=service_role, privilege_type=EXECUTE; no rows for anon or authenticated:
-- SELECT grantee, privilege_type, is_grantable
-- FROM   information_schema.routine_privileges
-- WHERE  routine_name = 'cc_confirm_location_atomic'
-- ORDER  BY grantee;
--
-- 4. Confirm no trainers have a stored postcode (should return 0 rows):
-- SELECT id, cc_postcode
-- FROM   trainers
-- WHERE  cc_postcode IS NOT NULL AND cc_postcode <> '';
--
-- 5. Confirm trainer_private is empty (no postcodes yet):
-- SELECT COUNT(*) FROM trainer_private;
-- ══════════════════════════════════════════════════════════════
