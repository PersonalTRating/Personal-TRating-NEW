-- Run this in Supabase → SQL Editor → New query
-- Creates the reject_review_by_token function

CREATE OR REPLACE FUNCTION reject_review_by_token(p_token text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviewer_name text;
BEGIN
  DELETE FROM reviews
  WHERE  approval_token::text = p_token
    AND  is_verified = false
  RETURNING reviewer_name INTO v_reviewer_name;

  IF v_reviewer_name IS NULL THEN
    RETURN 'not_found';
  END IF;

  RETURN v_reviewer_name;
END;
$$;

GRANT EXECUTE ON FUNCTION reject_review_by_token(text) TO anon;
GRANT EXECUTE ON FUNCTION reject_review_by_token(text) TO authenticated;
