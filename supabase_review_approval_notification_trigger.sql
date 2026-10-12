-- ══════════════════════════════════════════════════════════════════════════
-- CoachCards — Review Approval In-App Notification Trigger
-- File: supabase_review_approval_notification_trigger.sql
-- Run in Supabase Dashboard → SQL Editor
-- Safe to re-run (CREATE OR REPLACE + DROP IF EXISTS)
-- ══════════════════════════════════════════════════════════════════════════
--
-- Inserts a row into `notifications` whenever a review is approved.
-- Covers BOTH approval paths automatically:
--   • Admin dashboard (direct UPDATE via admin.astro)
--   • Email-link approval (approve_review_by_token RPC)
--
-- Idempotent: the trigger condition only fires when is_verified transitions
-- FALSE → TRUE. A repeated approval or any other UPDATE to the row does not
-- fire the trigger again, so no duplicate notifications are possible.
--
-- Guest reviews (client_id IS NULL) are silently skipped.
-- No approval tokens or private moderation data are included in the
-- notification body or link.
-- ══════════════════════════════════════════════════════════════════════════

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

DROP TRIGGER IF EXISTS on_review_approved ON reviews;

CREATE TRIGGER on_review_approved
  AFTER UPDATE ON reviews
  FOR EACH ROW
  EXECUTE FUNCTION notify_reviewer_on_approval();


-- ── Tighten the notifications INSERT policy ───────────────────────────────
-- The original "Service can insert notifications" policy uses WITH CHECK (true),
-- which allows any authenticated (or anon) session to INSERT a notification
-- for ANY user_id — including other users' IDs. This is unnecessary because
-- SECURITY DEFINER functions and triggers bypass RLS entirely (they run as
-- the function definer, not the calling role). Dropping this policy means only
-- SECURITY DEFINER code paths can insert notifications; direct client inserts
-- are denied by the absence of a permissive INSERT policy.
DROP POLICY IF EXISTS "Service can insert notifications" ON notifications;
