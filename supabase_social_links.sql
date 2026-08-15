ALTER TABLE trainers
  ADD COLUMN IF NOT EXISTS social_facebook  TEXT,
  ADD COLUMN IF NOT EXISTS social_instagram TEXT,
  ADD COLUMN IF NOT EXISTS social_whatsapp  TEXT,
  ADD COLUMN IF NOT EXISTS social_email     TEXT,
  ADD COLUMN IF NOT EXISTS accepts_bookings BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS booking_url      TEXT;
