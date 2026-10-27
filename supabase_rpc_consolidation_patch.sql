-- ════════════════════════════════════════════════════════════════════════════
-- CoachCards — Consolidate get_own_trainer_profile() with all required fields
--
-- Problem:
--   supabase_bmp_v3_migration.sql Step 6 introduced distinct_reviewer_count
--   but dropped ranking_visibility (which supabase_ranking_visibility_rpc_patch.sql
--   had added). The live production function therefore returns
--   distinct_reviewer_count but NOT ranking_visibility.
--
--   Missing ranking_visibility causes the dashboard to initialise the
--   ranking-visibility-select at 'all', and any profile save by a trainer
--   with location_confirmed = true silently overwrites their stored preference.
--
-- Fix:
--   Add 'ranking_visibility', t.ranking_visibility to the jsonb_build_object.
--   All other fields, SECURITY DEFINER, SET search_path, permissions and
--   NOTIFY pgrst are preserved exactly.
--
-- Safe to re-run (CREATE OR REPLACE).
-- Requires both columns to exist on public.trainers:
--   • distinct_reviewer_count — added by supabase_bmp_v3_migration.sql
--   • ranking_visibility      — added by supabase_ranking_visibility.sql
-- ════════════════════════════════════════════════════════════════════════════

-- READ-ONLY INSPECTION (run this first to confirm live function state):
-- SELECT pg_get_functiondef(oid)
-- FROM pg_proc
-- WHERE proname = 'get_own_trainer_profile'
--   AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

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
    'distinct_reviewer_count', t.distinct_reviewer_count,
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
   location_cooldown_until, ranking_visibility and distinct_reviewer_count are
   accessible even after B3 column grants restrict those columns from the
   authenticated role. Identity derived from auth.uid() only — no caller-supplied
   parameter. Returns NULL when unauthenticated or when no trainer record exists.';

REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_own_trainer_profile() FROM anon;
GRANT  EXECUTE ON FUNCTION get_own_trainer_profile() TO authenticated;

NOTIFY pgrst, 'reload schema';
