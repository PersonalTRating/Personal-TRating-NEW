-- ══════════════════════════════════════════════════════════════════════════════
-- CoachCards — Notification Trigger Compatibility Patch (CoachCards-Test only)
-- File: supabase_notification_trigger_compat.sql
--
-- PURPOSE
--   Installs the fifth and final production review trigger in CoachCards-Test:
--     on_review_approved_notify_client → notify_reviewer_on_approval()
--
-- This trigger and function are identical to the production source file
-- supabase_review_approval_notification_trigger.sql, with three test-only
-- clarifications added below.
--
-- EMAIL / NOTIFICATION SAFETY
--   This trigger inserts rows into the local `notifications` database table only.
--   It does NOT call Resend, make HTTP requests, or send any external emails.
--   Email delivery is handled by the separate approve-review.js Netlify function,
--   which is not triggered here. Installing this in CoachCards-Test is
--   fully isolated — no real users can receive notifications from it.
--
-- RUN ORDER (CoachCards-Test only):
--   1. supabase_test_environment_setup.sql
--   2. supabase_production_compat_patch.sql   ← on_review_approved must exist first
--   3. THIS FILE                              ← installs notification trigger
--   4. supabase_bmp_v3_migration.sql
--   5. supabase_compat_trigger_tests.sql
--
-- DEPENDENCIES (all created by the files above):
--   • reviews table
--   • trainers table (column: name, id)
--   • clients table (column: user_id, id)
--   • notifications table (columns: user_id, type, title, body, link)
--   • on_review_approved trigger (checked by safety guard below)
--
-- DO NOT RUN ON PRODUCTION — production already has this trigger.
-- DO NOT PUSH OR DEPLOY.
-- ══════════════════════════════════════════════════════════════════════════════


-- ── Safety guard: on_review_approved must already exist ──────────────────────
-- If supabase_production_compat_patch.sql has not been run, this will fail
-- before making any changes.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   information_schema.triggers
    WHERE  trigger_schema     = 'public'
      AND  event_object_table = 'reviews'
      AND  trigger_name       = 'on_review_approved'
  ) THEN
    RAISE EXCEPTION
      'Safety check failed: on_review_approved trigger not found. '
      'Run supabase_production_compat_patch.sql before this file.';
  END IF;
  RAISE NOTICE 'Safety check PASS: on_review_approved trigger present.';
END;
$$;


-- ── 1. Notification trigger function ─────────────────────────────────────────
-- Identical to supabase_review_approval_notification_trigger.sql.
-- Fires only when is_verified transitions FALSE → TRUE.
-- Guest reviews (client_id IS NULL) are skipped silently.
-- Inserts one row into the notifications table — no external calls made.

CREATE OR REPLACE FUNCTION public.notify_reviewer_on_approval()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_trainer_name   TEXT;
  v_client_user_id UUID;
BEGIN
  -- Only fire on FALSE → TRUE transition.
  -- NOT DISTINCT FROM TRUE covers the case where OLD.is_verified is NULL.
  IF OLD.is_verified IS NOT DISTINCT FROM TRUE THEN
    RETURN NEW;  -- already approved — no-op
  END IF;
  IF NEW.is_verified IS NOT TRUE THEN
    RETURN NEW;  -- not an approval event — no-op
  END IF;
  IF NEW.client_id IS NULL THEN
    RETURN NEW;  -- guest review — no account to notify
  END IF;

  SELECT name    INTO v_trainer_name   FROM trainers WHERE id = NEW.trainer_id;
  SELECT user_id INTO v_client_user_id FROM clients  WHERE id = NEW.client_id;

  IF v_client_user_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, link)
    VALUES (
      v_client_user_id,
      'review_approved',
      'Your review is now live! 🎉',
      'Your review of ' || COALESCE(v_trainer_name, 'your trainer') ||
        ' has been approved and is now visible on their profile.',
      '/trainers/' || NEW.trainer_id::TEXT
    );
  END IF;

  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_reviewer_on_approval() TO service_role;

DO $$ BEGIN
  RAISE NOTICE 'notify_reviewer_on_approval() installed.';
END; $$;


-- ── 2. Install the trigger ────────────────────────────────────────────────────
-- Alphabetically: on_review_approved < on_review_approved_notify_client < trg_ < zzz_
-- so this fires second on approval UPDATEs, after update_trainer_stats() and
-- before trg_update_star_rating and zzz_on_review_bmp_update.

DROP TRIGGER IF EXISTS on_review_approved_notify_client ON public.reviews;

CREATE TRIGGER on_review_approved_notify_client
  AFTER UPDATE ON public.reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_reviewer_on_approval();

DO $$ BEGIN
  RAISE NOTICE 'on_review_approved_notify_client trigger installed (AFTER UPDATE, guard inside function).';
END; $$;


-- ── 3. Drop the overly-permissive notifications INSERT policy (if present) ───
-- In production this policy was removed because SECURITY DEFINER triggers bypass
-- RLS entirely, making it unnecessary and a security risk.
-- In CoachCards-Test it may or may not exist depending on setup order; IF EXISTS
-- makes this safe either way.

DROP POLICY IF EXISTS "Service can insert notifications" ON public.notifications;

DO $$ BEGIN
  RAISE NOTICE 'Notifications INSERT policy drop attempted (safe if policy was absent).';
END; $$;


-- ── 4. Verify all five triggers are now present ───────────────────────────────

SELECT
  trigger_name,
  event_manipulation   AS event,
  action_timing        AS timing,
  action_statement     AS calls
FROM information_schema.triggers
WHERE event_object_schema = 'public'
  AND event_object_table  = 'reviews'
ORDER BY trigger_name, event_manipulation;

-- ── Expected output ───────────────────────────────────────────────────────────
-- Distinct trigger names should be exactly these five (some appear multiple
-- times because trg_update_star_rating and zzz_on_review_bmp_update fire on
-- three events each):
--
--   on_review_approved               UPDATE   AFTER   EXECUTE FUNCTION update_trainer_stats()
--   on_review_approved_notify_client UPDATE   AFTER   EXECUTE FUNCTION notify_reviewer_on_approval()
--   on_review_created                INSERT   AFTER   EXECUTE FUNCTION update_trainer_stats()
--   trg_update_star_rating           DELETE   AFTER   EXECUTE FUNCTION update_trainer_star_rating()
--   trg_update_star_rating           INSERT   AFTER   EXECUTE FUNCTION update_trainer_star_rating()
--   trg_update_star_rating           UPDATE   AFTER   EXECUTE FUNCTION update_trainer_star_rating()
--   zzz_on_review_bmp_update         DELETE   AFTER   EXECUTE FUNCTION trigger_recalculate_bmp()
--   zzz_on_review_bmp_update         INSERT   AFTER   EXECUTE FUNCTION trigger_recalculate_bmp()
--   zzz_on_review_bmp_update         UPDATE   AFTER   EXECUTE FUNCTION trigger_recalculate_bmp()
--
-- Total: 9 rows, 5 distinct trigger names — matching production.
