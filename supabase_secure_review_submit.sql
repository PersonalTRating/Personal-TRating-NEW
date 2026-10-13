-- ═══════════════════════════════════════════════════════════════════════════════
-- CoachCards: Secure Review Submission — V2 Migration
-- Run in Supabase → SQL Editor → New query
-- ─────────────────────────────────────────────────────────────────────────────
-- SECURITY ISSUES FIXED:
--   V1  Impersonation: p_client_id was browser-supplied — any authenticated user
--       could pass any client UUID and submit reviews as that person.
--   V2  30-day bypass: passing p_client_id: null skipped all rate-limit checks,
--       allowing unlimited review spam from authenticated accounts.
--   V3  Anon access: GRANT EXECUTE TO anon allowed unauthenticated callers to
--       invoke the submission endpoint directly via PostgREST.
--   V4  Missing search_path: SECURITY DEFINER without SET search_path is
--       vulnerable to search_path injection (a malicious schema could shadow
--       pg_catalog functions or the clients/reviews tables).
--
-- WHAT CHANGES:
--   • check_review_eligibility loses p_client_id — derives identity from auth.uid()
--   • submit_review_for_client loses p_client_id — derives identity from auth.uid()
--   • Both functions gain SET search_path = public, auth
--   • Anon execute grants removed from both functions
--   • submit_review_for_client now hard-rejects unauthenticated callers and
--     authenticated users with no activated client record — no bypass path exists
--
-- WHAT IS PRESERVED (zero data changes):
--   • All existing reviews, including historical records with client_id = NULL
--   • uq_one_pending_per_client_trainer partial unique index — unchanged
--   • calculate_bmp_for_trainer — unchanged
--   • All notification, BMP, and trending functions — unchanged
--
-- DEPLOYMENT ORDER:
--   Step 1: Run this SQL migration in Supabase SQL Editor.
--           After this point the old function signatures no longer exist.
--           New review submissions will fail until the frontend is deployed.
--   Step 2: Deploy the updated frontend to Netlify immediately after (~30-60 s gap).
--           Once deployed, review submissions are fully restored and secured.
-- ═══════════════════════════════════════════════════════════════════════════════


-- ────────────────────────────────────────────────────────────────────────────
-- Part 1: check_review_eligibility
-- ────────────────────────────────────────────────────────────────────────────
-- Old signature: check_review_eligibility(p_client_id UUID, p_trainer_id UUID)
-- New signature: check_review_eligibility(p_trainer_id UUID)
--   — client identity is derived from auth.uid() internally.
--   — anon grant removed (unauthenticated users never reach this call anyway;
--     the review page hard-guards against !user before the eligibility check).
--   — SET search_path added to close the search_path injection vector.
-- ────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS check_review_eligibility(UUID, UUID);

CREATE OR REPLACE FUNCTION check_review_eligibility(
  p_trainer_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_client_id     UUID;
  v_review_at     TIMESTAMPTZ;
  v_next_eligible TIMESTAMPTZ;
BEGIN
  -- Derive client identity from the authenticated session
  SELECT id INTO v_client_id
  FROM clients
  WHERE user_id = auth.uid();

  -- No client record (or unauthenticated): report eligible.
  -- The submit function is the authoritative enforcement point; this function
  -- is UX-only — it lets the page show a "try again on <date>" message early.
  IF v_client_id IS NULL THEN
    RETURN jsonb_build_object('status', 'eligible');
  END IF;

  -- Block if a pending review already exists
  SELECT created_at INTO v_review_at
  FROM reviews
  WHERE client_id  = v_client_id
    AND trainer_id = p_trainer_id
    AND is_verified = FALSE
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object('status', 'pending_review');
  END IF;

  -- Block if within 30 rolling days of the most recent verified review
  SELECT created_at INTO v_review_at
  FROM reviews
  WHERE client_id  = v_client_id
    AND trainer_id = p_trainer_id
    AND is_verified = TRUE
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    v_next_eligible := v_review_at + INTERVAL '30 days';
    IF NOW() < v_next_eligible THEN
      RETURN jsonb_build_object(
        'status',           'blocked',
        'next_eligible_at', v_next_eligible
      );
    END IF;
  END IF;

  RETURN jsonb_build_object('status', 'eligible');
END;
$$;

GRANT  EXECUTE ON FUNCTION check_review_eligibility(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION check_review_eligibility(UUID) FROM anon;


-- ────────────────────────────────────────────────────────────────────────────
-- Part 2: submit_review_for_client
-- ────────────────────────────────────────────────────────────────────────────
-- Old signature: submit_review_for_client(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT8, TEXT, BOOLEAN, UUID)
-- New signature: submit_review_for_client(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT8, TEXT, BOOLEAN, UUID)
--   — p_client_id parameter removed.
--   — client identity derived from auth.uid() + clients table lookup internally.
--   — rejects unauthenticated callers (auth.uid() IS NULL → not_authenticated).
--   — rejects authenticated users with no activated client record → not_a_client.
--   — 30-day rule and advisory lock always enforce — no NULL-bypass path.
--   — anon grant removed.
--   — SET search_path added.
-- ────────────────────────────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS submit_review_for_client(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT8, TEXT, BOOLEAN, UUID);

CREATE OR REPLACE FUNCTION submit_review_for_client(
  p_trainer_id            UUID,
  p_reviewer_name         TEXT,
  p_reviewer_initials     TEXT,
  p_reviewer_avatar_bg    TEXT,
  p_reviewer_avatar_color TEXT,
  p_reviewer_location     TEXT,
  p_rating                FLOAT8,
  p_review_text           TEXT,
  p_is_anonymous          BOOLEAN,
  p_approval_token        UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_client_id     UUID;
  v_review_at     TIMESTAMPTZ;
  v_next_eligible TIMESTAMPTZ;
  v_review_id     UUID;
BEGIN

  -- Hard reject: unauthenticated callers cannot submit reviews
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('status', 'not_authenticated');
  END IF;

  -- Derive client identity from the authenticated session — never trust browser-supplied values
  SELECT id INTO v_client_id
  FROM clients
  WHERE user_id = auth.uid();

  -- Hard reject: authenticated user has no activated client record
  IF v_client_id IS NULL THEN
    RETURN jsonb_build_object('status', 'not_a_client');
  END IF;

  -- Advisory lock: serialise concurrent submissions for the same (client, trainer) pair.
  -- Transaction-level — auto-releases on commit or rollback.
  PERFORM pg_advisory_xact_lock(
    hashtext(v_client_id::text),
    hashtext(p_trainer_id::text)
  );

  -- Guard: block if a pending review already exists
  SELECT created_at INTO v_review_at
  FROM reviews
  WHERE client_id  = v_client_id
    AND trainer_id = p_trainer_id
    AND is_verified = FALSE
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object('status', 'pending_review');
  END IF;

  -- Guard: block if within 30 rolling days of the last verified review
  SELECT created_at INTO v_review_at
  FROM reviews
  WHERE client_id  = v_client_id
    AND trainer_id = p_trainer_id
    AND is_verified = TRUE
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    v_next_eligible := v_review_at + INTERVAL '30 days';
    IF NOW() < v_next_eligible THEN
      RETURN jsonb_build_object(
        'status',           'blocked',
        'next_eligible_at', v_next_eligible
      );
    END IF;
  END IF;

  -- All checks passed — insert the review
  INSERT INTO reviews (
    trainer_id,            client_id,
    reviewer_name,         reviewer_initials,
    reviewer_avatar_bg,    reviewer_avatar_color,
    reviewer_location,
    rating,                review_text,
    is_verified,           is_anonymous,
    approval_token
  )
  VALUES (
    p_trainer_id,          v_client_id,
    p_reviewer_name,       p_reviewer_initials,
    p_reviewer_avatar_bg,  p_reviewer_avatar_color,
    p_reviewer_location,
    p_rating,              p_review_text,
    FALSE,                 p_is_anonymous,
    p_approval_token
  )
  RETURNING id INTO v_review_id;

  RETURN jsonb_build_object('status', 'ok', 'review_id', v_review_id);
END;
$$;

GRANT  EXECUTE ON FUNCTION submit_review_for_client(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT8, TEXT, BOOLEAN, UUID)
  TO authenticated;
REVOKE EXECUTE ON FUNCTION submit_review_for_client(UUID, TEXT, TEXT, TEXT, TEXT, TEXT, FLOAT8, TEXT, BOOLEAN, UUID)
  FROM anon;
