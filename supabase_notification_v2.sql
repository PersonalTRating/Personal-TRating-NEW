-- ══════════════════════════════════════════════════════════════════════════
-- CoachCards — Review Approval Notification v2  (supabase_notification_v2.sql)
-- Run in Supabase Dashboard → SQL Editor
-- REPLACES supabase_notification_v1.sql — do NOT run v1 after running this
-- Safe to re-run: uses IF NOT EXISTS / CREATE OR REPLACE
-- ══════════════════════════════════════════════════════════════════════════
--
-- Security vs v1
--   • GRANT EXECUTE to anon/authenticated REMOVED
--   • Functions only callable via service_role key (Netlify functions)
--   • Admin JWT verified server-side before notification is triggered
--
-- Reliability vs v1
--   • notification_claimed_at: temporary processing lock (expires 5 min)
--   • notification_sent_at: set ONLY after Resend confirms 2xx
--   • notification_attempt_count: retry limit guard (max 5 attempts)
--   • Resend idempotency key prevents duplicate emails on retry
--   • Guest reviews (client_id IS NULL) skipped atomically in SQL
--
-- ══════════════════════════════════════════════════════════════════════════


-- ── 1. Notification state columns ─────────────────────────────────────────
--
-- notification_claimed_at  (temporary processing lock)
--   NULL          = never attempted
--   recent value  = being processed right now — skip
--   expired value = previous attempt timed out or failed — retryable
--
-- notification_sent_at  (permanent success flag)
--   NULL  = not yet confirmed sent by Resend
--   value = email confirmed — never retry again
--
-- notification_attempt_count  (retry budget)
--   Incremented on every claim. Stops at MAX_RETRIES (5) in retry batch.

ALTER TABLE reviews
  ADD COLUMN IF NOT EXISTS notification_claimed_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS notification_sent_at       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS notification_attempt_count INTEGER NOT NULL DEFAULT 0;


-- ── 2. claim_approval_notification(UUID) ────────────────────────────────
-- Admin-dashboard path: caller has the review UUID.
-- Atomically claims the slot, increments attempt_count, returns context.
-- Guest reviews (client_id IS NULL) are skipped in the WHERE clause —
-- no attempt_count increment, no spurious claimed_at set.
-- No GRANT to anon/authenticated — callable only via service_role.
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
  UPDATE reviews
  SET    notification_claimed_at    = NOW(),
         notification_attempt_count = notification_attempt_count + 1
  WHERE  id                         = p_review_id
    AND  is_verified                = TRUE
    AND  client_id                  IS NOT NULL   -- guests silently skipped
    AND  notification_sent_at       IS NULL
    AND  (notification_claimed_at   IS NULL
          OR notification_claimed_at < NOW() - INTERVAL '5 minutes')
  RETURNING client_id INTO v_client_id;

  IF NOT FOUND THEN RETURN; END IF;  -- already sent, guest, claim active, or not found

  SELECT c.user_id INTO v_user_id
  FROM   clients c
  WHERE  c.id = v_client_id;

  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    u.email::TEXT  AS reviewer_email,
    rv.reviewer_name,
    t.name::TEXT   AS trainer_name,
    t.id::TEXT     AS trainer_id
  FROM   reviews   rv
  JOIN   trainers  t  ON t.id = rv.trainer_id
  JOIN   auth.users u ON u.id = v_user_id
  WHERE  rv.id = p_review_id;
END;
$$;


-- ── 3. claim_approval_notification_by_token(TEXT) ────────────────────────
-- Email-link path: caller has the approval token, not the review UUID.
-- Returns review_id so the caller can confirm via confirm_approval_notification.
-- Guest reviews excluded in WHERE clause (same as above).
CREATE OR REPLACE FUNCTION claim_approval_notification_by_token(p_token TEXT)
RETURNS TABLE(
  reviewer_email TEXT,
  reviewer_name  TEXT,
  trainer_name   TEXT,
  trainer_id     TEXT,
  review_id      TEXT
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
  UPDATE reviews
  SET    notification_claimed_at    = NOW(),
         notification_attempt_count = notification_attempt_count + 1
  WHERE  approval_token             = p_token::UUID
    AND  is_verified                = TRUE
    AND  client_id                  IS NOT NULL   -- guests silently skipped
    AND  notification_sent_at       IS NULL
    AND  (notification_claimed_at   IS NULL
          OR notification_claimed_at < NOW() - INTERVAL '5 minutes')
  RETURNING id, client_id INTO v_review_id, v_client_id;

  IF NOT FOUND THEN RETURN; END IF;

  SELECT c.user_id INTO v_user_id
  FROM   clients c
  WHERE  c.id = v_client_id;

  IF v_user_id IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    u.email::TEXT     AS reviewer_email,
    rv.reviewer_name,
    t.name::TEXT      AS trainer_name,
    t.id::TEXT        AS trainer_id,
    v_review_id::TEXT AS review_id
  FROM   reviews   rv
  JOIN   trainers  t  ON t.id = rv.trainer_id
  JOIN   auth.users u ON u.id = v_user_id
  WHERE  rv.id = v_review_id;
END;
$$;


-- ── 4. confirm_approval_notification(UUID) ───────────────────────────────
-- Called after Resend returns 2xx to permanently seal the notification slot.
-- Until this is called, notification_claimed_at will expire and allow retry.
CREATE OR REPLACE FUNCTION confirm_approval_notification(p_review_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE reviews
  SET    notification_sent_at    = NOW(),
         notification_claimed_at = NOW()  -- keep fresh so expiry check is never true again
  WHERE  id = p_review_id;
END;
$$;


-- ── 5. claim_notification_retry_batch(max_retries, batch_size) ───────────
-- Called by the retry scheduler (Netlify scheduled function).
-- Atomically selects and claims up to p_batch_size reviews that:
--   • Have been attempted at least once (notification_claimed_at IS NOT NULL)
--   • Are not yet confirmed sent (notification_sent_at IS NULL)
--   • Have an expired claim lock (> 5 min old — previous attempt failed/timed out)
--   • Are under the retry budget (notification_attempt_count < p_max_retries)
--   • Are not guest reviews (client_id IS NOT NULL)
-- FOR UPDATE SKIP LOCKED prevents concurrent retry runs from double-claiming.
-- Historical reviews (approved before this system) have claimed_at = NULL
-- and are never touched by this function.
CREATE OR REPLACE FUNCTION claim_notification_retry_batch(
  p_max_retries INT DEFAULT 5,
  p_batch_size  INT DEFAULT 10
)
RETURNS TABLE(
  review_id      TEXT,
  reviewer_email TEXT,
  reviewer_name  TEXT,
  trainer_name   TEXT,
  trainer_id     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  WITH claimed AS (
    UPDATE reviews
    SET    notification_claimed_at    = NOW(),
           notification_attempt_count = notification_attempt_count + 1
    WHERE  id IN (
      SELECT id
      FROM   reviews
      WHERE  is_verified             = TRUE
        AND  client_id               IS NOT NULL
        AND  notification_sent_at    IS NULL
        AND  notification_claimed_at IS NOT NULL
        AND  notification_claimed_at < NOW() - INTERVAL '5 minutes'
        AND  notification_attempt_count < p_max_retries
      ORDER BY notification_claimed_at
      LIMIT  p_batch_size
      FOR UPDATE SKIP LOCKED
    )
    RETURNING id, client_id
  ),
  with_users AS (
    SELECT cl.id, c.user_id
    FROM   claimed cl
    JOIN   clients c ON c.id = cl.client_id
  )
  SELECT
    cl.id::TEXT      AS review_id,
    u.email::TEXT    AS reviewer_email,
    rv.reviewer_name,
    t.name::TEXT     AS trainer_name,
    t.id::TEXT       AS trainer_id
  FROM   claimed     cl
  JOIN   reviews     rv ON rv.id = cl.id
  JOIN   trainers    t  ON t.id  = rv.trainer_id
  JOIN   with_users  wu ON wu.id = cl.id
  JOIN   auth.users  u  ON u.id  = wu.user_id;
END;
$$;


-- No GRANT to anon or authenticated.
-- All four functions are callable only by postgres / service_role.
