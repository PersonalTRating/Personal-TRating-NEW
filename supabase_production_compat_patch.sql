-- ══════════════════════════════════════════════════════════════════════════════
-- CoachCards — Production Trigger Compatibility Patch
-- File: supabase_production_compat_patch.sql
--
-- PURPOSE
--   Reproduces the ORIGINAL production trigger configuration in CoachCards-Test
--   so that BMP v3 migration testing covers the actual production trigger stack.
--
-- RUN ORDER (CoachCards-Test only):
--   1. supabase_test_environment_setup.sql           — base schema
--   2. THIS FILE                                     — add 3 production triggers
--   3. supabase_notification_trigger_compat.sql      — add 5th trigger (notify)
--   4. supabase_v3_preflight_backup.sql              — snapshot pre-migration BMP state
--   5. supabase_bmp_v3_migration.sql                 — v3 migration (now includes Step 8)
--   6. supabase_compat_trigger_tests.sql             — 10 compatibility tests
--
-- DO NOT RUN ON PRODUCTION — production already has these triggers.
--
-- WHAT THIS FILE DOES
--   Installs the three additional triggers present in production but absent from
--   the reconstructed test schema:
--     • on_review_approved    AFTER UPDATE OF is_verified (FALSE→TRUE)
--     • on_review_created     AFTER INSERT
--     • trg_update_star_rating AFTER INSERT OR UPDATE OR DELETE
--
--   These are installed with their ORIGINAL production bodies — intentionally
--   including the bmp_score writes that Step 8 of the migration will fix.
--   This allows the test suite to confirm that Step 8 eliminates the conflict.
--
-- RECONSTRUCTION NOTE
--   update_trainer_stats() and update_trainer_star_rating() bodies are
--   reconstructed from the extracted production definitions (2026-10-26):
--     • update_trainer_stats()       formula: LEAST(100, ROUND((_avg/5)*70 + LEAST(_count*3,30)))
--     • update_trainer_star_rating() formula: AVG(rating) * 20
--   Trigger events reconstructed from names, comments, and alphabetical-ordering
--   notes across the migration files. Mark any discrepancy if the live definition
--   differs from what is shown here.
--
-- DO NOT EXECUTE SQL ON PRODUCTION. DO NOT PUSH OR DEPLOY.
-- ══════════════════════════════════════════════════════════════════════════════


-- ── 1. update_trainer_stats() — original production body ─────────────────────
-- Called by: on_review_approved (UPDATE, FALSE→TRUE) and on_review_created (INSERT).
-- BUG (intentionally preserved for testing):
--   • Queries reviews WITHOUT is_verified = TRUE — includes pending reviews.
--   • Writes bmp_score using an outdated formula.
-- Both bugs are fixed by Step 8 of supabase_bmp_v3_migration.sql.

CREATE OR REPLACE FUNCTION public.update_trainer_stats()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _avg   NUMERIC;
  _count INTEGER;
BEGIN
  SELECT COALESCE(AVG(rating), 0), COUNT(*)
  INTO   _avg, _count
  FROM   reviews
  WHERE  trainer_id = NEW.trainer_id;
  -- NOTE: intentionally no is_verified filter — production bug reproduced for testing

  UPDATE trainers
  SET star_rating  = _avg,
      review_count = _count,
      bmp_score    = LEAST(100, ROUND((_avg / 5.0) * 70 + LEAST(_count * 3, 30)))
  WHERE id = NEW.trainer_id;

  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_trainer_stats() TO service_role;

DO $$ BEGIN
  RAISE NOTICE 'update_trainer_stats() installed (original production body with bmp_score write).';
END; $$;


-- ── 2. on_review_approved trigger ────────────────────────────────────────────
-- Fires AFTER UPDATE OF is_verified when a review transitions FALSE → TRUE.
-- Alphabetically before zzz_on_review_bmp_update, so it fires first on approval.

DROP TRIGGER IF EXISTS on_review_approved ON public.reviews;

CREATE TRIGGER on_review_approved
  AFTER UPDATE OF is_verified ON public.reviews
  FOR EACH ROW
  WHEN (NEW.is_verified = TRUE AND OLD.is_verified IS DISTINCT FROM TRUE)
  EXECUTE FUNCTION public.update_trainer_stats();

DO $$ BEGIN
  RAISE NOTICE 'on_review_approved trigger installed (AFTER UPDATE OF is_verified, FALSE→TRUE).';
END; $$;


-- ── 3. on_review_created trigger ─────────────────────────────────────────────
-- Fires AFTER INSERT on every new review, including pending (is_verified = FALSE).
-- This is why unverified review INSERTs currently corrupt bmp_score (no guard).

DROP TRIGGER IF EXISTS on_review_created ON public.reviews;

CREATE TRIGGER on_review_created
  AFTER INSERT ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_trainer_stats();

DO $$ BEGIN
  RAISE NOTICE 'on_review_created trigger installed (AFTER INSERT, all reviews including pending).';
END; $$;


-- ── 4. update_trainer_star_rating() — original production body ───────────────
-- Called by: trg_update_star_rating (AFTER INSERT OR UPDATE OR DELETE).
-- BUG (intentionally preserved for testing):
--   • Queries reviews WITHOUT is_verified = TRUE — includes pending reviews.
--   • Writes bmp_score using an even simpler outdated formula (AVG * 20).
-- Both bugs are fixed by Step 8 of supabase_bmp_v3_migration.sql.

CREATE OR REPLACE FUNCTION public.update_trainer_star_rating()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _trainer_id UUID;
  _avg        NUMERIC;
BEGIN
  _trainer_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.trainer_id ELSE NEW.trainer_id END;

  SELECT COALESCE(AVG(rating), 0) INTO _avg
  FROM   reviews
  WHERE  trainer_id = _trainer_id;
  -- NOTE: intentionally no is_verified filter — production bug reproduced for testing

  UPDATE trainers
  SET star_rating  = _avg,
      review_count = (SELECT COUNT(*) FROM reviews WHERE trainer_id = _trainer_id),
      bmp_score    = _avg * 20
  WHERE id = _trainer_id;

  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_trainer_star_rating() TO service_role;

DO $$ BEGIN
  RAISE NOTICE 'update_trainer_star_rating() installed (original production body with bmp_score write).';
END; $$;


-- ── 5. trg_update_star_rating trigger ────────────────────────────────────────
-- Fires AFTER INSERT OR UPDATE OR DELETE — the broadest scope of the five triggers.
-- Alphabetically after 'on_review_*' but before 'zzz_on_review_bmp_update',
-- so it runs on every review event before the canonical BMP trigger.

DROP TRIGGER IF EXISTS trg_update_star_rating ON public.reviews;

CREATE TRIGGER trg_update_star_rating
  AFTER INSERT OR UPDATE OR DELETE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_trainer_star_rating();

DO $$ BEGIN
  RAISE NOTICE 'trg_update_star_rating trigger installed (AFTER INSERT OR UPDATE OR DELETE).';
END; $$;


-- ── 6. Verify all five review triggers are now present ───────────────────────

SELECT
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table  = 'reviews'
ORDER BY trigger_name, event_manipulation;

-- Expected 7 rows (INSERT, UPDATE, DELETE × trg_update_star_rating accounts for 3):
--   on_review_approved               UPDATE
--   on_review_approved_notify_client UPDATE (if installed)
--   on_review_created                INSERT
--   trg_update_star_rating           DELETE
--   trg_update_star_rating           INSERT
--   trg_update_star_rating           UPDATE
--   zzz_on_review_bmp_update         DELETE
--   zzz_on_review_bmp_update         INSERT
--   zzz_on_review_bmp_update         UPDATE
-- (on_review_approved_notify_client may not be in CoachCards-Test yet)
