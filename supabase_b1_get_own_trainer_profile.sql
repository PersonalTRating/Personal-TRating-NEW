-- ════════════════════════════════════════════════════════════════
-- B1: get_own_trainer_profile()
--
-- Run this BEFORE deploying the B2 application code changes.
-- Do NOT run B3 column grants until B2 is live in production.
--
-- Security properties:
--   SECURITY DEFINER — runs as function owner (postgres), so the
--     SELECT inside sees all columns regardless of the calling
--     role's column-level grants (needed for postcode and
--     location_cooldown_until after B3 is applied).
--   SET search_path = '' — empty search path; no schema can be injected
--     to shadow public.trainers or auth.uid(). All names are explicit.
--   auth.uid() — identity derived from the caller's JWT claim only.
--     No caller-supplied trainer_id parameter; no BOLA risk.
--   RETURNS JSONB scalar — PostgREST applies no column-grant
--     filtering to scalar return values, so the restricted columns
--     (postcode, location_cooldown_until) reach the dashboard intact.
--   REVOKE from PUBLIC and anon — no unauthenticated call path.
--   LIMIT 1 / WHERE user_id = auth.uid() — only the caller's own
--     row is ever returned. Returns NULL if unauthenticated or if no
--     trainer record exists for this user_id.
--
-- Columns returned: all fields required by dashboard.astro.
-- Excluded: user_id, email, cc_postcode, location_confirmed_at,
--           location_source, location_mapping_version, is_active,
--           recent_review_count (none are accessed by dashboard JS).
-- ════════════════════════════════════════════════════════════════

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
    'location_cooldown_until', t.location_cooldown_until
  )
  FROM   public.trainers t
  WHERE  t.user_id = auth.uid()
  LIMIT  1;
$$;

COMMENT ON FUNCTION get_own_trainer_profile() IS
  'Returns the authenticated trainer''s own row as JSONB containing only the
   fields required by dashboard.astro. SECURITY DEFINER ensures postcode and
   location_cooldown_until are accessible even after B3 column grants restrict
   those columns from the authenticated role. Identity derived from auth.uid()
   only — no caller-supplied parameter. Returns NULL when unauthenticated or
   when no trainer record exists for the calling user.';

REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM anon;
GRANT  EXECUTE ON FUNCTION get_own_trainer_profile() TO authenticated;

NOTIFY pgrst, 'reload schema';
