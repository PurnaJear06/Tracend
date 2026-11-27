-- Explicit consent to cycle data (the period days an athlete logs or allows from Apple Health, and
-- her cycle answers) is recorded as its own type, separate from health data. The app asks for it
-- only when she turns cycle tracking on. The value is added alone: an enum value cannot be used in
-- the transaction that adds it.
alter type public.consent_type add value if not exists 'cycle_data';
