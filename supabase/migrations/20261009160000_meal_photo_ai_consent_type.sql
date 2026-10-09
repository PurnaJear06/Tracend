-- A meal photo is sent to an AI provider only after the athlete grants its own
-- notice. The new consent type is added alone: an enum value cannot be used in
-- the transaction that adds it.
alter type public.consent_type add value if not exists 'meal_photo_ai';
