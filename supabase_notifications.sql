-- Run this in Supabase → SQL Editor → New query
-- Step 1: Create the notifications table

CREATE TABLE IF NOT EXISTS notifications (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     uuid NOT NULL,
  type        text NOT NULL DEFAULT 'review_approved',
  title       text NOT NULL,
  body        text,
  link        text,
  is_read     boolean DEFAULT false,
  created_at  timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS notifications_user_id_idx ON notifications(user_id);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Users can read their own notifications
CREATE POLICY "Users read own notifications" ON notifications
  FOR SELECT USING (auth.uid() = user_id);

-- Users can mark their own notifications as read
CREATE POLICY "Users update own notifications" ON notifications
  FOR UPDATE USING (auth.uid() = user_id);

-- The approve function (SECURITY DEFINER) can insert notifications
CREATE POLICY "Service can insert notifications" ON notifications
  FOR INSERT WITH CHECK (true);


-- Step 2: Update approve_review_by_token to insert a notification on approval

CREATE OR REPLACE FUNCTION approve_review_by_token(p_token text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_reviewer_name  text;
  v_trainer_id     uuid;
  v_client_id      uuid;
  v_trainer_name   text;
  v_client_user_id uuid;
  v_is_verified    boolean;
BEGIN
  -- Check review exists
  SELECT is_verified INTO v_is_verified
  FROM   reviews
  WHERE  approval_token::text = p_token
  LIMIT  1;

  IF NOT FOUND THEN
    RETURN 'not_found';
  END IF;

  IF v_is_verified = true THEN
    RETURN 'already_approved';
  END IF;

  -- Approve
  UPDATE reviews
  SET    is_verified = true
  WHERE  approval_token::text = p_token
    AND  is_verified = false
  RETURNING reviewer_name, trainer_id, client_id
       INTO v_reviewer_name, v_trainer_id, v_client_id;

  IF v_reviewer_name IS NULL THEN
    RETURN 'not_found';
  END IF;

  -- Recalculate trainer BMP score
  UPDATE trainers
  SET
    star_rating  = (SELECT COALESCE(AVG(rating), 0) FROM reviews WHERE trainer_id = v_trainer_id AND is_verified = true),
    review_count = (SELECT COUNT(*)                  FROM reviews WHERE trainer_id = v_trainer_id AND is_verified = true)
  WHERE id = v_trainer_id;

  -- Notify reviewer if they are a registered client
  IF v_client_id IS NOT NULL THEN
    SELECT name    INTO v_trainer_name   FROM trainers WHERE id = v_trainer_id;
    SELECT user_id INTO v_client_user_id FROM clients  WHERE id = v_client_id;

    IF v_client_user_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, link)
      VALUES (
        v_client_user_id,
        'review_approved',
        'Your review is now live! 🎉',
        'Your review of ' || COALESCE(v_trainer_name, 'your trainer') || ' has been approved and is now visible on their profile.',
        '/trainers/' || v_trainer_id::text
      );
    END IF;
  END IF;

  RETURN v_reviewer_name;
END;
$$;

GRANT EXECUTE ON FUNCTION approve_review_by_token(text) TO anon;
GRANT EXECUTE ON FUNCTION approve_review_by_token(text) TO authenticated;
