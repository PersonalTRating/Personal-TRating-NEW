-- ============================================================
-- COACHCARDS: Stated-location rankings — PRE-CHECK (READ-ONLY)
-- Run in the Supabase SQL editor BEFORE the migration.
-- Makes no changes. Shows exactly what the migration and data fix will touch,
-- including inactive trainers, which the public key could not see.
-- ============================================================

-- 1. Every trainer's current location fields. Postcodes are cut to the first
--    part (outward code) so no full postcode is shown.
SELECT t.id,
       t.name,
       t.is_active,
       t.city,
       split_part(upper(trim(coalesce(t.postcode, ''))), ' ', 1) AS postcode_outward,
       (t.postcode ~* '^[A-Z]{1,2}[0-9][A-Z0-9]? ?[0-9][A-Z]{2}$')  AS legacy_postcode_is_full,
       t.coaching_type,
       t.cc_country,
       t.cc_local_area,
       t.location_confirmed,
       t.location_source,
       t.location_cooldown_until,
       (p.trainer_id IS NOT NULL)                                AS has_private_full_postcode,
       split_part(coalesce(p.cc_postcode, ''), ' ', 1)           AS private_postcode_outward
FROM   trainers t
LEFT   JOIN trainer_private p ON p.trainer_id = t.id
ORDER  BY t.is_active DESC, t.bmp_score DESC NULLS LAST;

-- 2. How many full postcodes the migration will delete (trainer_private is dropped).
SELECT COUNT(*) AS trainer_private_rows FROM trainer_private;

-- 3. Which CHECK constraint currently restricts location_source (the migration
--    drops and recreates it to allow 'city').
SELECT conname, pg_get_constraintdef(oid)
FROM   pg_constraint
WHERE  conrelid = 'public.trainers'::regclass
  AND  contype  = 'c'
  AND  pg_get_constraintdef(oid) ILIKE '%location_source%';

-- 4. The ranking areas the data fix uses must exist.
SELECT id, display_name, country
FROM   ranking_areas
WHERE  id IN ('ENG_GREATER_LONDON', 'SCO_CITY_OF_EDINBURGH');
