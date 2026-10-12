-- ══════════════════════════════════════════════════════════════════════════
-- CoachCards — Review Approval In-App Notification Trigger
-- File: supabase_review_approval_notification_trigger.sql
-- Run in Supabase Dashboard → SQL Editor
-- Safe to re-run (CREATE OR REPLACE + DROP IF EXISTS on the NEW trigger only)
-- ══════════════════════════════════════════════════════════════════════════
--
-- Inserts a row into `notifications` whenever a review is approved.
-- Covers BOTH approval paths automatically:
--   • Admin dashboard (direct UPDATE via admin.astro)
--   • Email-link approval (approve_review_by_token RPC)
--
-- Trigger name: on_review_approved_notify_client
-- This is intentionally different from the existing on_review_approved
-- trigger, which calls update_trainer_stats() and must be preserved.
-- PostgreSQL allows multiple AFTER UPDATE triggers on the same table;
-- both fire independently on every qualifying UPDATE.
--
-- Idempotent: the trigger condition only fires when is_verified transitions
-- FALSE → TRUE. A repeated approval or any other UPDATE to the row does not
-- fire the trigger again, so no duplicate notifications are possible.
--
-- Guest reviews (client_id IS NULL) are silently skipped.
-- No approval tokens or private moderation data are included in the
-- notification body or link.
-- ══════════════════════════════════════════════════════════════════════════


-- ── Safety check: confirm the existing trainer-stats trigger is intact ────
-- This query will return one row if the trigger is safe. If it returns zero
-- rows, do NOT proceed — the existing trigger is missing and needs investigation.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM   information_schema.triggers
    WHERE  trigger_schema = 'public'
      AND  event_object_table = 'reviews'
      AND  trigger_name = 'on_review_approved'
  ) THEN
    RAISE EXCEPTION
      'Safety check failed: on_review_approved trigger not found. '
      'This migration expects the existing trainer-stats trigger to be present. '
      'Inspect triggers on the reviews table before continuing.';
  END IF;
END;
$$;


-- ── 1. Create the notification trigger function ───────────────────────────
CREATE OR REPLACE FUNCTION notify_reviewer_on_approval()
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
    RETURN NEW;  -- guest review — no-op, no account to notify
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


-- ── 2. Install the notification trigger (unique name) ─────────────────────
-- DROP only the notification trigger — never the trainer-stats trigger.
DROP TRIGGER IF EXISTS on_review_approved_notify_client ON reviews;

CREATE TRIGGER on_review_approved_notify_client
  AFTER UPDATE ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION notify_reviewer_on_approval();


-- ── 3. Tighten the notifications INSERT policy ────────────────────────────
-- The "Service can insert notifications" policy uses WITH CHECK (true),
-- which allows any authenticated session to INSERT a notification for ANY
-- user_id. SECURITY DEFINER triggers bypass RLS entirely, so this policy
-- is unnecessary and a security risk. Dropping it means only SECURITY
-- DEFINER code paths can insert notifications.
DROP POLICY IF EXISTS "Service can insert notifications" ON notifications;


-- ── 4. Verify both triggers exist ────────────────────────────────────────
-- Run this after the migration to confirm both triggers are present.
-- Expected output: two rows — on_review_approved and on_review_approved_notify_client.
SELECT trigger_name, event_manipulation, action_statement
FROM   information_schema.triggers
WHERE  trigger_schema     = 'public'
  AND  event_object_table = 'reviews'
  AND  trigger_name IN ('on_review_approved', 'on_review_approved_notify_client')
ORDER BY trigger_name;
