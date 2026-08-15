-- Run this in Supabase → SQL Editor → New query
-- Updates appeal system: fixes token generation, adds notes, adds trainer notifications

-- Step 1: Add resolution_notes column (for upheld reviews)
ALTER TABLE reviews
  ADD COLUMN IF NOT EXISTS resolution_notes text;

-- Step 2: Fix submit_review_appeal to always regenerate the token
-- (existing rows added before the appeal_token column may have NULL tokens)
CREATE OR REPLACE FUNCTION submit_review_appeal(p_review_id uuid, p_reason text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_review      reviews%ROWTYPE;
  v_trainer_id  uuid;
  v_token       uuid;
BEGIN
  SELECT * INTO v_review FROM reviews WHERE id = p_review_id AND is_verified = true;
  IF NOT FOUND THEN RETURN json_build_object('error', 'not_found'); END IF;

  SELECT id INTO v_trainer_id FROM trainers WHERE id = v_review.trainer_id AND user_id = auth.uid();
  IF NOT FOUND THEN RETURN json_build_object('error', 'unauthorized'); END IF;

  IF v_review.appeal_status IS NOT NULL THEN RETURN json_build_object('error', 'already_appealed'); END IF;

  -- Always generate a fresh token so NULL tokens on old rows are fixed
  v_token := gen_random_uuid();

  UPDATE reviews
  SET appeal_reason = p_reason,
      appeal_status = 'pending',
      appeal_token  = v_token
  WHERE id = p_review_id;

  RETURN json_build_object(
    'token',         v_token,
    'reviewer_name', v_review.reviewer_name,
    'review_text',   v_review.review_text,
    'rating',        v_review.rating
  );
END;
$$;

GRANT EXECUTE ON FUNCTION submit_review_appeal(uuid, text) TO authenticated;

-- Step 3: Update remove_appealed_review to accept notes and notify trainer
CREATE OR REPLACE FUNCTION remove_appealed_review(p_token uuid, p_notes text DEFAULT '')
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_trainer_id      uuid;
  v_reviewer_name   text;
  v_trainer_user_id uuid;
BEGIN
  SELECT trainer_id, reviewer_name INTO v_trainer_id, v_reviewer_name
  FROM reviews WHERE appeal_token = p_token AND appeal_status = 'pending';
  IF NOT FOUND THEN RETURN 'not_found'; END IF;

  SELECT user_id INTO v_trainer_user_id FROM trainers WHERE id = v_trainer_id;

  DELETE FROM reviews WHERE appeal_token = p_token;

  UPDATE trainers SET
    star_rating  = (SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE trainer_id = v_trainer_id AND is_verified = true),
    review_count = (SELECT COUNT(*)                  FROM reviews WHERE trainer_id = v_trainer_id AND is_verified = true)
  WHERE id = v_trainer_id;

  IF v_trainer_user_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, link)
    VALUES (
      v_trainer_user_id,
      'appeal_approved',
      'Appeal successful — review removed ✅',
      CASE WHEN p_notes != ''
           THEN 'The review has been removed from your profile. Admin note: ' || p_notes
           ELSE 'The review has been removed from your profile and your BMP score has been updated.'
      END,
      '/dashboard'
    );
  END IF;

  RETURN v_reviewer_name;
END;
$$;

GRANT EXECUTE ON FUNCTION remove_appealed_review(uuid, text) TO anon;
GRANT EXECUTE ON FUNCTION remove_appealed_review(uuid, text) TO authenticated;

-- Step 4: Update uphold_appealed_review to accept notes and notify trainer
CREATE OR REPLACE FUNCTION uphold_appealed_review(p_token uuid, p_notes text DEFAULT '')
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviewer_name   text;
  v_trainer_id      uuid;
  v_trainer_user_id uuid;
BEGIN
  UPDATE reviews
  SET appeal_status     = 'upheld',
      resolution_notes  = p_notes
  WHERE appeal_token = p_token AND appeal_status = 'pending'
  RETURNING reviewer_name, trainer_id INTO v_reviewer_name, v_trainer_id;

  IF NOT FOUND THEN RETURN 'not_found'; END IF;

  SELECT user_id INTO v_trainer_user_id FROM trainers WHERE id = v_trainer_id;

  IF v_trainer_user_id IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, link)
    VALUES (
      v_trainer_user_id,
      'appeal_declined',
      'Appeal outcome — review remains live',
      CASE WHEN p_notes != ''
           THEN 'After review, your appeal was not upheld. Admin note: ' || p_notes
           ELSE 'After review, your appeal was not upheld. The review will remain on your profile.'
      END,
      '/dashboard'
    );
  END IF;

  RETURN v_reviewer_name;
END;
$$;

GRANT EXECUTE ON FUNCTION uphold_appealed_review(uuid, text) TO anon;
GRANT EXECUTE ON FUNCTION uphold_appealed_review(uuid, text) TO authenticated;

-- Step 5: Drop the old 1-param versions to avoid overload ambiguity
DROP FUNCTION IF EXISTS remove_appealed_review(uuid);
DROP FUNCTION IF EXISTS uphold_appealed_review(uuid);
