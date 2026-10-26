-- ══════════════════════════════════════════════════════════════════════════════
-- CoachCards — BMP Trigger Comprehensive Fix
--
-- Forward-only patch: apply to CoachCards-Test (already has BMP v3 applied).
-- This same block is also appended to supabase_bmp_v3_migration.sql so that
-- production receives it as part of the standard migration rollout.
--
-- Problem fixed:
--   zzz_on_review_bmp_update previously only fired AFTER UPDATE OF is_verified
--   with WHEN (NEW.is_verified = TRUE AND OLD.is_verified IS DISTINCT FROM TRUE).
--   That covers the basic admin approval path but misses six lifecycle events
--   that all affect the BMP score, trending state or distinct_reviewer_count:
--
--   1. ✓ Pending → verified                   (was covered)
--   2. ✗ Verified → unverified (un-approval)  — BMP must drop
--   3. ✗ Verified review deleted              — BMP must drop
--   4. ✗ Rating change on verified review     — affects quality, momentum, trending
--   5. ✗ INSERT already verified              — BMP stays 0 after direct insert
--   6. ✗ trainer_id change                   — both old and new trainer affected
--   7. ✗ client_id or created_at change       — affect dedup, anon cap, time windows
--
-- What this preserves:
--   • Trigger name zzz_on_review_bmp_update (fires after on_review_approved)
--   • All RLS policies, grants, and moderation functions
--   • The BMP v3 formula in calculate_bmp_for_trainer (unchanged)
--   • Notification triggers (this only replaces the BMP recalculation trigger)
--   • Authenticated-client deduplication and the 5-anonymous-review cap
--
-- Scoring-relevant fields watched (all others are ignored to avoid extra work):
--   is_verified  — approval state changes (cases 1 and 2)
--   rating       — quality pts, ≥3.5 momentum/trending filter (case 4)
--   client_id    — DISTINCT ON dedup identity, distinct_reviewer_count, anon cap (case 7)
--   created_at   — trending (7d, 7–28d) and momentum (7d, 8–30d, 31–90d) windows (case 7)
--
-- is_anonymous is NOT in the scoring-relevant set: the BMP function determines
-- anonymous reviews by client_id IS NULL, not by the is_anonymous flag.
-- Changes to is_anonymous affect display only and do not require BMP recalculation.
--
-- Safe to run multiple times (CREATE OR REPLACE + DROP IF EXISTS).
-- DO NOT execute on production until approved.
-- ══════════════════════════════════════════════════════════════════════════════


-- ── 1. Create the comprehensive trigger function ──────────────────────────────

CREATE OR REPLACE FUNCTION public.trigger_recalculate_bmp()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN

  -- ── INSERT ─────────────────────────────────────────────────────────────────
  -- Case 5: review inserted already verified (imported, seeded, or direct insert)
  IF TG_OP = 'INSERT' THEN
    IF NEW.is_verified = TRUE THEN
      PERFORM public.calculate_bmp_for_trainer(NEW.trainer_id);
    END IF;
    RETURN NEW;
  END IF;

  -- ── DELETE ─────────────────────────────────────────────────────────────────
  -- Case 3: a verified review is removed — recalculate from the smaller set
  IF TG_OP = 'DELETE' THEN
    IF OLD.is_verified = TRUE THEN
      PERFORM public.calculate_bmp_for_trainer(OLD.trainer_id);
    END IF;
    RETURN OLD;
  END IF;

  -- ── UPDATE ─────────────────────────────────────────────────────────────────
  IF TG_OP = 'UPDATE' THEN

    -- Case 6: review moved to a different trainer — recalculate both sides
    IF NEW.trainer_id IS DISTINCT FROM OLD.trainer_id THEN
      IF OLD.is_verified = TRUE THEN
        PERFORM public.calculate_bmp_for_trainer(OLD.trainer_id);
      END IF;
      IF NEW.is_verified = TRUE THEN
        PERFORM public.calculate_bmp_for_trainer(NEW.trainer_id);
      END IF;
      RETURN NEW;
    END IF;

    -- Skip entirely when the review is unverified in both old and new states.
    -- Unverified reviews are excluded from all BMP inputs, so no scoring field
    -- change on an unverified review can affect the score.
    IF OLD.is_verified = FALSE AND NEW.is_verified = FALSE THEN
      RETURN NEW;
    END IF;

    -- Cases 1, 2, 4, 7: recalculate when at least one scoring-relevant field
    -- changed and the review is (or was) verified.
    IF NEW.is_verified  IS DISTINCT FROM OLD.is_verified  OR  -- approval / un-approval
       NEW.rating        IS DISTINCT FROM OLD.rating       OR  -- quality pts + trending filter
       NEW.client_id     IS DISTINCT FROM OLD.client_id    OR  -- dedup identity + anon cap
       NEW.created_at    IS DISTINCT FROM OLD.created_at       -- trending + momentum windows
    THEN
      PERFORM public.calculate_bmp_for_trainer(NEW.trainer_id);
    END IF;

  END IF;

  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.trigger_recalculate_bmp() TO service_role;


-- ── 2. Replace the trigger ────────────────────────────────────────────────────
-- Drop the old AFTER UPDATE OF is_verified trigger and replace with a
-- comprehensive AFTER INSERT OR UPDATE OR DELETE trigger.
-- The zzz_ prefix is preserved so this fires after on_review_approved (if present).

DROP TRIGGER IF EXISTS zzz_on_review_bmp_update ON public.reviews;

CREATE TRIGGER zzz_on_review_bmp_update
  AFTER INSERT OR UPDATE OR DELETE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_recalculate_bmp();


-- ── 3. Verify ────────────────────────────────────────────────────────────────
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.triggers
    WHERE  event_object_schema = 'public'
      AND  event_object_table  = 'reviews'
      AND  trigger_name        = 'zzz_on_review_bmp_update'
  ) THEN
    RAISE NOTICE 'PASS: zzz_on_review_bmp_update trigger installed on public.reviews';
  ELSE
    RAISE WARNING 'FAIL: trigger was not created — check for errors above';
  END IF;
END; $$;

SELECT
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table  = 'reviews'
ORDER BY trigger_name;
