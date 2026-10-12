-- ══════════════════════════════════════════════════════════════════════════
-- SUPERSEDED — DO NOT RUN
-- Use supabase_notification_v2.sql instead.
-- This file has a security vulnerability (GRANT EXECUTE to anon/authenticated)
-- and a reliability issue (sets notification_sent_at before email confirms).
-- ══════════════════════════════════════════════════════════════════════════
-- CoachCards — Review Approval Notification  (supabase_notification_v1.sql)
-- ══════════════════════════════════════════════════════════════════════════

-- ── 1. Idempotency guard column ─────────────────────────────────────────────
-- Tracks whether the approval notification email has been sent for a review.
-- NULL  = not yet sent (or review not yet approved)
-- value = timestamp it was sent — prevents duplicate emails from any path.
ALTER TABLE reviews
  ADD COLUMN IF NOT EXISTS notification_sent_at TIMESTAMPTZ;

-- ── 2. claim_approval_notification (by review UUID) ─────────────────────────
-- Called by the admin-dashboard approval path, which has the review's UUID.
-- Atomically:
--   a) checks the review is approved (is_verified = TRUE) and not yet notified
--   b) marks notification_sent_at = NOW()  (preventing duplicates)
--   c) returns {reviewer_email, reviewer_name, trainer_name, trainer_id}
-- Returns empty set when:
--   • notification already sent for this review
--   • review is not yet approved
--   • review not found
--   • reviewer is a guest (client_id IS NULL → no account → no email)
--   • no auth user found for the client
-- SECURITY DEFINER is required to read auth.users (not accessible via anon key).
CREATE OR REPLACE FUNCTION claim_approval_notification(p_review_id UUID)
RETURNS TABLE(
  reviewer_email TEXT,
  reviewer_name  TEXT,
  trainer_name   TEXT,
  trainer_id     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_client_id UUID;
  v_user_id   UUID;
BEGIN
  -- Atomically claim the notification slot.
  -- Only one caller can win the UPDATE (others see NOT FOUND).
  UPDATE reviews
  SET    notification_sent_at = NOW()
  WHERE  id                   = p_review_id
    AND  is_verified          = TRUE
    AND  notification_sent_at IS NULL
  RETURNING client_id INTO v_client_id;

  IF NOT FOUND THEN
    RETURN;  -- already notified, not yet approved, or review not found
  END IF;

  IF v_client_id IS NULL THEN
    RETURN;  -- guest reviewer — no account, no email to send
  END IF;

  -- Resolve client → Supabase Auth user
  SELECT c.user_id INTO v_user_id
  FROM   clients c
  WHERE  c.id = v_client_id;

  IF v_user_id IS NULL THEN RETURN; END IF;

  -- Return email and context for the notification
  -- (SECURITY DEFINER allows accessing auth.users)
  RETURN QUERY
  SELECT
    u.email::TEXT    AS reviewer_email,
    rv.reviewer_name,
    t.name::TEXT     AS trainer_name,
    t.id::TEXT       AS trainer_id
  FROM   reviews   rv
  JOIN   trainers  t  ON t.id  = rv.trainer_id
  JOIN   auth.users u ON u.id  = v_user_id
  WHERE  rv.id = p_review_id;
END;
$$;

GRANT EXECUTE ON FUNCTION claim_approval_notification(UUID) TO anon, authenticated;


-- ── 3. claim_approval_notification_by_token (by approval token) ─────────────
-- Called by the email-link approval path (approve-review.js), which only
-- has the approval token — not the review UUID.
-- Same atomicity guarantee as above: the UPDATE is the idempotency gate.
CREATE OR REPLACE FUNCTION claim_approval_notification_by_token(p_token TEXT)
RETURNS TABLE(
  reviewer_email TEXT,
  reviewer_name  TEXT,
  trainer_name   TEXT,
  trainer_id     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_review_id UUID;
  v_client_id UUID;
  v_user_id   UUID;
BEGIN
  -- Cast the token string to UUID; malformed tokens will raise an exception
  -- caught by the caller — let it propagate as a 500 rather than silently skip.

  -- Atomically find and claim
  UPDATE reviews
  SET    notification_sent_at = NOW()
  WHERE  approval_token       = p_token::UUID
    AND  is_verified          = TRUE
    AND  notification_sent_at IS NULL
  RETURNING id, client_id INTO v_review_id, v_client_id;

  IF NOT FOUND THEN
    RETURN;  -- already notified, not yet approved, invalid token, or guest
  END IF;

  IF v_client_id IS NULL THEN
    RETURN;  -- guest reviewer
  END IF;

  SELECT c.user_id INTO v_user_id
  FROM   clients c
  WHERE  c.id = v_client_id;

  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    u.email::TEXT    AS reviewer_email,
    rv.reviewer_name,
    t.name::TEXT     AS trainer_name,
    t.id::TEXT       AS trainer_id
  FROM   reviews   rv
  JOIN   trainers  t  ON t.id  = rv.trainer_id
  JOIN   auth.users u ON u.id  = v_user_id
  WHERE  rv.id = v_review_id;
END;
$$;

GRANT EXECUTE ON FUNCTION claim_approval_notification_by_token(TEXT) TO anon, authenticated;
