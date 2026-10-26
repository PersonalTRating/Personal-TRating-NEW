-- ══════════════════════════════════════════════════════════════════════════════
-- CoachCards — BMP v3 Pre-flight Backup
-- Run BEFORE supabase_bmp_v3_migration.sql in the same database.
--
-- What this does:
--   1. Creates a persistent backup table (once; safe to re-run).
--   2. Inserts a timestamped snapshot of every trainer's current BMP
--      state into that table.
--   3. Prints a verification summary.
--
-- Safety properties:
--   • Each run inserts a NEW backup_run row — previous backups are
--     NEVER overwritten or deleted.
--   • PRIMARY KEY (backup_run, trainer_id) prevents silent duplicate
--     insertion on re-runs within the same second.
--   • If the table already exists with a previous backup it is kept.
--
-- IMPORTANT: This script captures a score snapshot only.
-- It does NOT replace a full database backup.
-- For a complete backup, use Supabase Dashboard →
-- Project Settings → Database → Backups (daily) or
-- Dashboard → Branching (instant branch-level snapshot).
-- ══════════════════════════════════════════════════════════════════════════════


-- ── 1. Create persistent backup table (idempotent) ───────────────────────────
CREATE TABLE IF NOT EXISTS public.bmp_v3_migration_backup (
  backup_run                  TIMESTAMPTZ  NOT NULL,
  trainer_id                  UUID         NOT NULL,
  bmp_score                   NUMERIC,
  is_trending                 BOOLEAN,
  recent_review_count         INTEGER,
  distinct_reviewer_count_pre INTEGER,     -- NULL before migration; column absent pre-v3
  star_rating                 NUMERIC,
  review_count                INTEGER,
  PRIMARY KEY (backup_run, trainer_id)
);

COMMENT ON TABLE public.bmp_v3_migration_backup IS
  'Pre-migration score snapshot for BMP v3. Each run appends a new '
  'backup_run batch. Never modify or delete rows; the rollback script '
  'depends on the latest backup_run.';


-- ── 2. Insert snapshot ───────────────────────────────────────────────────────
DO $$
DECLARE
  v_run          TIMESTAMPTZ := clock_timestamp();
  v_trainer_count INTEGER;
  v_backup_count  INTEGER;
BEGIN
  -- Confirm trainer table is accessible
  SELECT COUNT(*) INTO v_trainer_count FROM public.trainers;
  RAISE NOTICE 'Found % trainer rows total', v_trainer_count;

  -- Insert snapshot (distinct_reviewer_count may not exist yet; stored as NULL)
  INSERT INTO public.bmp_v3_migration_backup
    (backup_run, trainer_id, bmp_score, is_trending, recent_review_count,
     distinct_reviewer_count_pre, star_rating, review_count)
  SELECT
    v_run,
    t.id,
    t.bmp_score,
    t.is_trending,
    t.recent_review_count,
    NULL,           -- column absent pre-migration
    t.star_rating,
    t.review_count
  FROM public.trainers t;

  GET DIAGNOSTICS v_backup_count = ROW_COUNT;

  IF v_backup_count <> v_trainer_count THEN
    RAISE WARNING 'Row count mismatch: % trainers found but % backed up',
      v_trainer_count, v_backup_count;
  ELSE
    RAISE NOTICE 'Backup complete. backup_run = % — % rows saved.', v_run, v_backup_count;
    RAISE NOTICE 'Store this timestamp for rollback reference: %', v_run;
  END IF;
END;
$$;


-- ── 3. Verification query — run after the DO block ───────────────────────────
-- Expected: latest row matches SELECT COUNT(*) FROM trainers.
-- Re-run this query at any time to confirm all backup runs.
SELECT
  backup_run,
  COUNT(*)                                         AS rows_backed_up,
  COUNT(*) FILTER (WHERE bmp_score > 0)            AS trainers_with_score,
  COUNT(*) FILTER (WHERE bmp_score = 0
                     OR bmp_score IS NULL)          AS trainers_unscored,
  ROUND(MIN(bmp_score)::NUMERIC, 1)                AS min_bmp,
  ROUND(MAX(bmp_score)::NUMERIC, 1)                AS max_bmp,
  ROUND(AVG(bmp_score)::NUMERIC, 1)                AS avg_bmp,
  COUNT(*) FILTER (WHERE is_trending = TRUE)        AS trending_count
FROM public.bmp_v3_migration_backup
GROUP BY backup_run
ORDER BY backup_run DESC;


-- ── 4. Cross-check: confirm count matches live trainers table ────────────────
-- Expected: backup_rows = live_rows (0 difference).
WITH latest AS (
  SELECT backup_run, COUNT(*) AS backup_rows
  FROM public.bmp_v3_migration_backup
  GROUP BY backup_run
  ORDER BY backup_run DESC
  LIMIT 1
),
live AS (
  SELECT COUNT(*) AS live_rows FROM public.trainers
)
SELECT
  l.backup_run,
  lv.live_rows,
  l.backup_rows,
  (lv.live_rows - l.backup_rows) AS difference,
  CASE WHEN lv.live_rows = l.backup_rows
    THEN '✓ Counts match — backup complete'
    ELSE '✗ COUNT MISMATCH — recheck before running migration'
  END AS status
FROM latest l, live lv;


-- ══════════════════════════════════════════════════════════════════════════════
-- IMPORTANT: A full database backup is your primary safety net.
--
-- This script only backs up: bmp_score, is_trending, recent_review_count,
-- star_rating, review_count.
--
-- It does NOT back up: reviews table, function bodies, triggers,
-- schema definitions, or any other trainer fields.
--
-- Before running the production migration, ensure Supabase has a
-- recent automatic backup (Dashboard → Project Settings → Backups)
-- or create a branch (Dashboard → Branching → New branch) as a
-- point-in-time restore target.
-- ══════════════════════════════════════════════════════════════════════════════
