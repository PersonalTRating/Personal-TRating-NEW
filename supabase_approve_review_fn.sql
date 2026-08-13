-- Run this in Supabase → SQL Editor → New query
-- Creates (or replaces) the approve_review_by_token function
-- and grants the anon role permission to call it.

CREATE OR REPLACE FUNCTION approve_review_by_token(p_token text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviewer_name text;
  v_trainer_id    uuid;
BEGIN
  -- Approve the review (only if not already approved)
  UPDATE reviews
  SET    is_verified = true
  WHERE  approval_token::text = p_token
    AND  is_verified = false
  RETURNING reviewer_name, trainer_id
       INTO v_reviewer_name, v_trainer_id;

  -- Token not found or already used
  IF v_reviewer_name IS NULL THEN
    RETURN 'not_found';
  END IF;

  -- Recalculate trainer BMP score from verified reviews only
  UPDATE trainers
  SET
    star_rating  = (
      SELECT COALESCE(AVG(rating), 0)
      FROM   reviews
      WHERE  trainer_id  = v_trainer_id
        AND  is_verified = true
    ),
    review_count = (
      SELECT COUNT(*)
      FROM   reviews
      WHERE  trainer_id  = v_trainer_id
        AND  is_verified = true
    )
  WHERE id = v_trainer_id;

  RETURN v_reviewer_name;
END;
$$;

-- Allow the anon Supabase client (used in Netlify functions) to call this
GRANT EXECUTE ON FUNCTION approve_review_by_token(text) TO anon;
GRANT EXECUTE ON FUNCTION approve_review_by_token(text) TO authenticated;
