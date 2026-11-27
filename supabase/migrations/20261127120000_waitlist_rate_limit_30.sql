-- Many phones share one IPv4 address on mobile carriers, so five join attempts per
-- hashed address per hour would block real people during an ad burst. The limit is now
-- 30 per hour. Only that number changes; the signature, security settings and grants
-- are the same as in 20261013100000_waitlist.sql.

-- Returns {outcome, referral_code}. outcome is 'send' when a confirmation email
-- should go out now, 'none' when the address is already confirmed or is still
-- pending with an email sent in the last 10 minutes, and 'rate_limited' after
-- 30 attempts from one IP address in an hour. The website answers 'send' and
-- 'none' the same way, so it cannot be used to learn who signed up.
create or replace function public.waitlist_join(
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
    if recent >= 30 then
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
