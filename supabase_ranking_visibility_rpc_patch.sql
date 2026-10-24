-- ════════════════════════════════════════════════════════════════════════════
-- CoachCards — Patch get_own_trainer_profile() to return ranking_visibility
-- Requires: supabase_b1_get_own_trainer_profile.sql already applied.
--           supabase_ranking_visibility.sql already applied.
-- ════════════════════════════════════════════════════════════════════════════
--
-- Problem:
--   get_own_trainer_profile() does not include ranking_visibility in its
--   jsonb_build_object. The dashboard reads trainer.ranking_visibility which
--   is therefore always undefined, falling back to 'all'. Every profile save
--   writes ranking_visibility: 'all' to the DB regardless of the trainer's
--   actual preference, silently resetting any opt-out.
--
-- Fix:
--   Add ranking_visibility to the JSONB return. No security or permission
--   changes are required — the function is SECURITY DEFINER so it already
--   bypasses column-level grants and can read the column freely.
--
-- No destructive changes. Safe to re-run (CREATE OR REPLACE).
-- ════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION get_own_trainer_profile()
RETURNS JSONB
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT jsonb_build_object(
    'id',                      t.id,
    'name',                    t.name,
    'username',                t.username,
    'business_name',           t.business_name,
    'city',                    t.city,
    'location',                t.location,
    'bio',                     t.bio,
    'intro_message',           t.intro_message,
    'specialty',               t.specialty,
    'coaching_type',           t.coaching_type,
    'cert',                    t.cert,
    'bmp_score',               t.bmp_score,
    'star_rating',             t.star_rating,
    'review_count',            t.review_count,
    'avatar_url',              t.avatar_url,
    'avatar_initials',         t.avatar_initials,
    'avatar_bg',               t.avatar_bg,
    'avatar_color',            t.avatar_color,
    'postcode',                t.postcode,
    'is_trending',             t.is_trending,
    'gyms',                    t.gyms,
    'hero_theme',              t.hero_theme,
    'social_facebook',         t.social_facebook,
    'social_instagram',        t.social_instagram,
    'social_whatsapp',         t.social_whatsapp,
    'social_email',            t.social_email,
    'accepts_bookings',        t.accepts_bookings,
    'booking_url',             t.booking_url,
    'location_confirmed',      t.location_confirmed,
    'cc_country',              t.cc_country,
    'cc_local_area',           t.cc_local_area,
    'location_cooldown_until', t.location_cooldown_until,
    'ranking_visibility',      t.ranking_visibility
  )
  FROM   public.trainers t
  WHERE  t.user_id = auth.uid()
  LIMIT  1;
$$;

COMMENT ON FUNCTION get_own_trainer_profile() IS
  'Returns the authenticated trainer''s own row as JSONB containing only the
   fields required by dashboard.astro. SECURITY DEFINER ensures postcode,
   location_cooldown_until and ranking_visibility are accessible even after
   B3 column grants restrict those columns from the authenticated role.
   Identity derived from auth.uid() only — no caller-supplied parameter.
   Returns NULL when unauthenticated or when no trainer record exists.';

-- Permissions unchanged — authenticated only, no public/anon access.
REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM anon;
GRANT  EXECUTE ON FUNCTION get_own_trainer_profile() TO authenticated;

NOTIFY pgrst, 'reload schema';
