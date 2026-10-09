-- Add coaching_type column to trainers table
-- Values: 'online', 'in_person', 'hybrid' (nullable — existing rows unaffected)
ALTER TABLE trainers ADD COLUMN IF NOT EXISTS coaching_type TEXT;
