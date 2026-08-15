-- Run this in Supabase → SQL Editor → New query
-- Updates approve_review_by_token to distinguish 'already_approved' from 'not_found'

CREATE OR REPLACE FUNCTION approve_review_by_token(p_token text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviewer_name text;
  v_trainer_id    uuid;
  v_is_verified   boolean;
BEGIN
  -- Check if the review exists at all
  SELECT is_verified INTO v_is_verified
  FROM   reviews
  WHERE  approval_token::text = p_token
  LIMIT  1;

  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;

  -- Already approved
  IF v_is_verified = true THEN
    RETURN 'already_approved';
  END IF;

  -- Approve it
  UPDATE reviews
  SET    is_verified = true
  WHERE  approval_token::text = p_token
    AND  is_verified = false
  RETURNING reviewer_name, trainer_id
       INTO v_reviewer_name, v_trainer_id;

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

GRANT EXECUTE ON FUNCTION approve_review_by_token(text) TO anon;
GRANT EXECUTE ON FUNCTION approve_review_by_token(text) TO authenticated;
