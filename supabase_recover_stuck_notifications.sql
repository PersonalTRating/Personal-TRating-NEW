-- ══════════════════════════════════════════════════════════════════════════
-- CoachCards — Recover notifications stuck with NULL notification_claimed_at
-- File: supabase_recover_stuck_notifications.sql
-- Run ONCE in Supabase Dashboard → SQL Editor
-- ══════════════════════════════════════════════════════════════════════════
--
-- Root cause: approve-review.js called sendNotification() without await.
-- Netlify killed the execution context before the UPDATE inside
-- claim_approval_notification_by_token could run, leaving
-- notification_claimed_at = NULL on all affected reviews.
--
-- The retry scheduler (claim_notification_retry_batch) requires
-- notification_claimed_at IS NOT NULL — it never touches NULL rows.
-- These reviews are permanently invisible to the scheduler without this fix.
--
-- Fix: set notification_claimed_at to a past timestamp (expired) so the
-- retry scheduler picks them up on its next run (within 15 minutes).
-- ══════════════════════════════════════════════════════════════════════════

UPDATE reviews
SET    notification_claimed_at = NOW() - INTERVAL '10 minutes'
WHERE  is_verified              = TRUE
  AND  client_id                IS NOT NULL   -- skip guest reviews
  AND  notification_sent_at     IS NULL        -- not already confirmed sent
  AND  notification_claimed_at  IS NULL;       -- stuck: never claimed

-- Verify: how many reviews are now eligible for the retry scheduler
-- (claimed_at is expired, not yet confirmed sent)
SELECT COUNT(*) AS ready_for_retry
FROM   reviews
WHERE  is_verified              = TRUE
  AND  client_id                IS NOT NULL
  AND  notification_sent_at     IS NULL
  AND  notification_claimed_at  < NOW() - INTERVAL '5 minutes';
