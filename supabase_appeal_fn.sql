-- Run this in Supabase → SQL Editor → New query
-- Adds review appeal system

-- Step 1: Add appeal columns to reviews table
ALTER TABLE reviews
  ADD COLUMN IF NOT EXISTS appeal_token  uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS appeal_reason text,
  ADD COLUMN IF NOT EXISTS appeal_status text; -- NULL = no appeal, 'pending', 'upheld', 'removed'

-- Step 2: RPC trainers call to submit an appeal
CREATE OR REPLACE FUNCTION submit_review_appeal(p_review_id uuid, p_reason text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_trainer_id    uuid;
  v_review        reviews%ROWTYPE;
  v_trainer_name  text;
  v_token         uuid;
BEGIN
  -- Fetch the review
  SELECT * INTO v_review FROM reviews WHERE id = p_review_id AND is_verified = true;
  IF NOT FOUND THEN RETURN json_build_object('error', 'not_found'); END IF;

  -- Confirm the calling user owns the trainer profile this review belongs to
  SELECT id INTO v_trainer_id FROM trainers WHERE id = v_review.trainer_id AND user_id = auth.uid();
  IF NOT FOUND THEN RETURN json_build_object('error', 'unauthorized'); END IF;

  -- Prevent re-appealing
  IF v_review.appeal_status IS NOT NULL THEN RETURN json_build_object('error', 'already_appealed'); END IF;

  -- Store the appeal
  UPDATE reviews
  SET appeal_reason = p_reason,
      appeal_status = 'pending'
  WHERE id = p_review_id
  RETURNING appeal_token INTO v_token;

  SELECT name INTO v_trainer_name FROM trainers WHERE id = v_trainer_id;

  RETURN json_build_object(
    'token',         v_token,
    'reviewer_name', v_review.reviewer_name,
    'review_text',   v_review.review_text,
    'rating',        v_review.rating,
    'trainer_name',  v_trainer_name
  );
END;
$$;

GRANT EXECUTE ON FUNCTION submit_review_appeal(uuid, text) TO authenticated;

-- Step 3: RPC admin uses to remove the review (uphold the appeal)
CREATE OR REPLACE FUNCTION remove_appealed_review(p_token uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_trainer_id    uuid;
  v_reviewer_name text;
BEGIN
  SELECT trainer_id, reviewer_name INTO v_trainer_id, v_reviewer_name
  FROM reviews WHERE appeal_token = p_token AND appeal_status = 'pending';
  IF NOT FOUND THEN RETURN 'not_found'; END IF;

  DELETE FROM reviews WHERE appeal_token = p_token;

  -- Recalculate trainer BMP
  UPDATE trainers SET
    star_rating  = (SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE trainer_id = v_trainer_id AND is_verified = true),
    review_count = (SELECT COUNT(*)                  FROM reviews WHERE trainer_id = v_trainer_id AND is_verified = true)
  WHERE id = v_trainer_id;

  RETURN v_reviewer_name;
END;
$$;

GRANT EXECUTE ON FUNCTION remove_appealed_review(uuid) TO anon;
GRANT EXECUTE ON FUNCTION remove_appealed_review(uuid) TO authenticated;

-- Step 4: RPC admin uses to uphold the review (reject the appeal)
CREATE OR REPLACE FUNCTION uphold_appealed_review(p_token uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviewer_name text;
BEGIN
  UPDATE reviews SET appeal_status = 'upheld'
  WHERE appeal_token = p_token AND appeal_status = 'pending'
  RETURNING reviewer_name INTO v_reviewer_name;

  IF NOT FOUND THEN RETURN 'not_found'; END IF;
  RETURN v_reviewer_name;
END;
$$;

GRANT EXECUTE ON FUNCTION uphold_appealed_review(uuid) TO anon;
GRANT EXECUTE ON FUNCTION uphold_appealed_review(uuid) TO authenticated;
