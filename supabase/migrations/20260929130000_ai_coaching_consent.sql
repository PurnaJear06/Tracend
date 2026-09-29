-- AI coaching consent: permission to send the athlete's Tracend data to the
-- Coach's AI provider for chat answers and daily decisions. It is recorded in
-- consent_records like every other purpose: append-only, versioned, and the
-- newest row per purpose is the current choice. A decline is stored as
-- 'withdrawn'.
alter type public.consent_type add value if not exists 'ai_coaching';
