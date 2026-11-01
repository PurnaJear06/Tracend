-- Explicit consent to health-data processing (Apple Health data, check-ins,
-- pain reports, body measurements and photos) is recorded as its own type,
-- separate from the terms and the privacy notice. The app records it at
-- onboarding and asks again when the privacy notice version changes. The
-- value is added alone: an enum value cannot be used in the transaction that
-- adds it.
alter type public.consent_type add value if not exists 'health_data';
