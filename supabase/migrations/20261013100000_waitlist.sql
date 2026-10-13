-- Website waitlist -----------------------------------------------------------------------

-- The website is the only way in, through three Edge Functions (waitlist-join,
-- waitlist-confirm, waitlist-unsubscribe) that call the service-role functions
-- below. No API role can read or write these tables; the owner works from the
-- SQL editor. Being on the waitlist gives no app access: the owner invites
-- confirmed signups into private.signup_invites with private.invite_from_waitlist.

create table private.waitlist_signups (
  id bigint generated always as identity primary key,
  email text not null unique
    check (email = lower(btrim(email)) and length(email) between 6 and 254
      and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'),
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'unsubscribed')),
  -- SHA-256 hex of the tokens in the emails; the tokens themselves are never stored.
  confirm_token_hash text unique check (confirm_token_hash ~ '^[0-9a-f]{64}$'),
  confirm_expires_at timestamptz,
  unsub_token_hash text not null unique check (unsub_token_hash ~ '^[0-9a-f]{64}$'),
  confirm_sends integer not null default 1 check (confirm_sends >= 0),
  last_sent_at timestamptz not null default now(),
  referral_code text not null unique check (referral_code ~ '^[0-9A-HJKMNP-TV-Z]{8}$'),
  referred_by bigint references private.waitlist_signups(id) on delete set null,
  consent_version text not null check (consent_version ~ '^[a-z0-9.-]{1,40}$'),
  consent_at timestamptz not null default now(),
  confirmed_at timestamptz,
  unsubscribed_at timestamptz,
  invited_at timestamptz,
  time_zone text check (length(time_zone) <= 64),
  utm_source text check (length(utm_source) <= 100),
  utm_medium text check (length(utm_medium) <= 100),
  utm_campaign text check (length(utm_campaign) <= 100),
  utm_content text check (length(utm_content) <= 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index waitlist_signups_referred_by on private.waitlist_signups(referred_by)
  where referred_by is not null;
revoke all on private.waitlist_signups from public, anon, authenticated, service_role;

-- Join attempts per hashed IP address, kept for one day, for the rate limit.
create table private.waitlist_attempts (
  ip_hash text not null check (ip_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz not null default now()
);
create index waitlist_attempts_ip_recent on private.waitlist_attempts(ip_hash, created_at);
create index waitlist_attempts_created on private.waitlist_attempts(created_at);
revoke all on private.waitlist_attempts from public, anon, authenticated, service_role;

-- The salt for IP hashes never leaves the database.
create table private.waitlist_secret (
  id boolean primary key default true check (id),
  salt bytea not null default extensions.gen_random_bytes(32)
);
insert into private.waitlist_secret default values;
revoke all on private.waitlist_secret from public, anon, authenticated, service_role;

-- 8 characters of Crockford base32 (no I, L, O, U).
create function private.waitlist_referral_code()
returns text language plpgsql volatile set search_path = '' as $$
declare
  alphabet constant text := '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  bytes bytea := extensions.gen_random_bytes(8);
  code text := '';
begin
  for i in 0..7 loop
    code := code || substr(alphabet, (get_byte(bytes, i) % 32) + 1, 1);
  end loop;
  return code;
end $$;
revoke all on function private.waitlist_referral_code() from public, anon, authenticated, service_role;

-- Join -----------------------------------------------------------------------------------

-- Returns {outcome, referral_code}. outcome is 'send' when a confirmation email
-- should go out now, 'none' when the address is already confirmed or is still
-- pending with an email sent in the last 10 minutes, and 'rate_limited' after
-- 5 attempts from one IP address in an hour. The website answers 'send' and
-- 'none' the same way, so it cannot be used to learn who signed up.
create function public.waitlist_join(
  join_email text,
  client_ip text,
  confirm_hash text,
  unsub_hash text,
  ref_code text,
  consent text,
  zone text,
  utm jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  addr text := lower(btrim(coalesce(join_email, '')));
  ip_key text;
  recent integer;
  referrer bigint;
  signup private.waitlist_signups;
  utm_clean jsonb := case when jsonb_typeof(utm) = 'object' then utm else '{}'::jsonb end;
begin
  if length(addr) not between 6 and 254 or addr !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'invalid email' using errcode = '22023';
  end if;
  if coalesce(confirm_hash, '') !~ '^[0-9a-f]{64}$' or coalesce(unsub_hash, '') !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid token hash' using errcode = '22023';
  end if;
  if coalesce(consent, '') !~ '^[a-z0-9.-]{1,40}$' then
    raise exception 'invalid consent version' using errcode = '22023';
  end if;

  if length(btrim(coalesce(client_ip, ''))) between 2 and 64 then
    select encode(extensions.hmac(convert_to(btrim(client_ip), 'UTF8'), s.salt, 'sha256'), 'hex')
    into ip_key from private.waitlist_secret s;
    perform pg_advisory_xact_lock(hashtextextended('tracend.waitlist_ip:' || ip_key, 0));
    delete from private.waitlist_attempts where created_at < now() - interval '1 day';
    select count(*) into recent from private.waitlist_attempts
    where ip_hash = ip_key and created_at > now() - interval '1 hour';
    if recent >= 5 then
      return jsonb_build_object('outcome', 'rate_limited');
    end if;
    insert into private.waitlist_attempts(ip_hash) values (ip_key);
  end if;

  if upper(coalesce(ref_code, '')) ~ '^[0-9A-HJKMNP-TV-Z]{8}$' then
    select s.id into referrer from private.waitlist_signups s
    where s.referral_code = upper(ref_code) and s.status <> 'unsubscribed';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('tracend.waitlist_email:' || addr, 0));
  select * into signup from private.waitlist_signups s where s.email = addr for update;

  if not found then
    for attempt in 1..5 loop
      begin
        insert into private.waitlist_signups(
          email, confirm_token_hash, confirm_expires_at, unsub_token_hash, referral_code,
          referred_by, consent_version, time_zone,
          utm_source, utm_medium, utm_campaign, utm_content)
        values (
          addr, confirm_hash, now() + interval '7 days', unsub_hash, private.waitlist_referral_code(),
          referrer, consent, nullif(left(btrim(coalesce(zone, '')), 64), ''),
          nullif(left(utm_clean ->> 'source', 100), ''), nullif(left(utm_clean ->> 'medium', 100), ''),
          nullif(left(utm_clean ->> 'campaign', 100), ''), nullif(left(utm_clean ->> 'content', 100), ''))
        returning * into signup;
        return jsonb_build_object('outcome', 'send', 'referral_code', signup.referral_code);
      exception when unique_violation then
        -- Only the random referral code can collide here; the email lock rules out a duplicate address.
        if attempt = 5 then raise; end if;
      end;
    end loop;
  end if;

  if signup.status = 'confirmed'
    or (signup.status = 'pending' and signup.last_sent_at > now() - interval '10 minutes')
    or signup.confirm_sends >= 10
  then
    return jsonb_build_object('outcome', 'none', 'referral_code', signup.referral_code);
  end if;

  -- Pending again, or back after unsubscribing: a fresh consent and fresh links.
  update private.waitlist_signups s set
    status = 'pending',
    confirm_token_hash = confirm_hash,
    confirm_expires_at = now() + interval '7 days',
    unsub_token_hash = unsub_hash,
    confirm_sends = s.confirm_sends + 1,
    last_sent_at = now(),
    consent_version = consent,
    consent_at = now(),
    unsubscribed_at = null,
    referred_by = coalesce(s.referred_by, nullif(referrer, s.id)),
    updated_at = now()
  where s.id = signup.id;
  return jsonb_build_object('outcome', 'send', 'referral_code', signup.referral_code);
end
$$;
revoke all on function public.waitlist_join(text, text, text, text, text, text, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.waitlist_join(text, text, text, text, text, text, text, jsonb)
  to service_role;

-- Confirm --------------------------------------------------------------------------------

-- Returns {status}: 'confirmed' (also for a second tap on the same link),
-- 'expired', 'unsubscribed' or 'invalid'. A confirmed signup also gets its referral code.
create function public.waitlist_confirm(token_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  signup private.waitlist_signups;
begin
  if coalesce(token_hash, '') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('status', 'invalid');
  end if;
  select * into signup from private.waitlist_signups s
  where s.confirm_token_hash = token_hash for update;
  if not found then
    return jsonb_build_object('status', 'invalid');
  end if;
  if signup.status = 'unsubscribed' then
    return jsonb_build_object('status', 'unsubscribed');
  end if;
  if signup.status = 'pending' then
    if signup.confirm_expires_at <= now() then
      return jsonb_build_object('status', 'expired');
    end if;
    update private.waitlist_signups s
    set status = 'confirmed', confirmed_at = now(), updated_at = now()
    where s.id = signup.id;
  end if;
  return jsonb_build_object('status', 'confirmed', 'referral_code', signup.referral_code);
end
$$;
revoke all on function public.waitlist_confirm(text) from public, anon, authenticated;
grant execute on function public.waitlist_confirm(text) to service_role;

-- Unsubscribe ----------------------------------------------------------------------------

-- Returns {status}: 'unsubscribed' (also when already unsubscribed) or 'invalid'.
-- The address stays, marked unsubscribed, so it is never emailed again.
create function public.waitlist_unsubscribe(token_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(token_hash, '') !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('status', 'invalid');
  end if;
  update private.waitlist_signups s
  set status = 'unsubscribed', unsubscribed_at = coalesce(s.unsubscribed_at, now()), updated_at = now()
  where s.unsub_token_hash = token_hash;
  if not found then
    return jsonb_build_object('status', 'invalid');
  end if;
  return jsonb_build_object('status', 'unsubscribed');
end
$$;
revoke all on function public.waitlist_unsubscribe(text) from public, anon, authenticated;
grant execute on function public.waitlist_unsubscribe(text) to service_role;

-- Email not sent -------------------------------------------------------------------------

-- waitlist-join calls this when the confirmation email could not be sent, so
-- the next attempt sends at once instead of waiting out the 10-minute window.
-- Matches on the token hash, so it only undoes the send it was told about.
create function public.waitlist_unsent(join_email text, confirm_hash text)
returns void
language sql
security definer
set search_path = ''
as $$
  update private.waitlist_signups s set
    last_sent_at = now() - interval '10 minutes',
    confirm_sends = greatest(s.confirm_sends - 1, 0),
    updated_at = now()
  where s.email = lower(btrim(join_email)) and s.confirm_token_hash = confirm_hash
    and s.status = 'pending';
$$;
revoke all on function public.waitlist_unsent(text, text) from public, anon, authenticated;
grant execute on function public.waitlist_unsent(text, text) to service_role;

-- Daily cleanup --------------------------------------------------------------------------

-- Signups never confirmed are deleted 30 days after their last email (the link
-- itself works for 7), and join attempts after a day.
create function private.waitlist_cleanup()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.waitlist_signups
  where status = 'pending' and last_sent_at < now() - interval '30 days';
  delete from private.waitlist_attempts where created_at < now() - interval '1 day';
$$;
revoke all on function private.waitlist_cleanup() from public, anon, authenticated, service_role;

select cron.schedule('tracend-waitlist-cleanup', '40 3 * * *', 'select private.waitlist_cleanup()');

-- Owner: invite the next confirmed signups -----------------------------------------------

-- SQL editor only. Picks confirmed, not yet invited signups, those with the most
-- confirmed referrals first, then in signup order, and adds them to the sign-up
-- invite list. Returns the invited addresses.
create function private.invite_from_waitlist(how_many integer)
returns table(email text)
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
begin
  if how_many is null or how_many not between 1 and 500 then
    raise exception 'invite between 1 and 500 at a time' using errcode = '22023';
  end if;
  return query
  with picked as (
    select s.id, s.email from private.waitlist_signups s
    where s.status = 'confirmed' and s.invited_at is null
    order by (
      select count(*) from private.waitlist_signups r
      where r.referred_by = s.id and r.status = 'confirmed'
    ) desc, s.id
    limit how_many
    for update of s
  ), invited as (
    insert into private.signup_invites(email, note)
    select p.email, 'waitlist' from picked p
    on conflict on constraint signup_invites_pkey do nothing
  )
  update private.waitlist_signups s set invited_at = now(), updated_at = now()
  from picked p where s.id = p.id
  returning s.email;
end
$$;
revoke all on function private.invite_from_waitlist(integer) from public, anon, authenticated, service_role;
