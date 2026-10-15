-- Deleting an account removes the email from the invite list and the waitlist ----------

-- private.signup_invites has no foreign key to auth.users and the waitlist is keyed
-- by email, so both rows outlived the account. Rows go by the invite the account
-- claimed and by the account's email. Coming back means joining the waitlist again
-- and being invited again. A signup the deleted person referred keeps its row; only
-- its referred_by link clears (on delete set null).
create function private.forget_account_invite(account_id uuid, account_email text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  addr text := lower(btrim(account_email));
begin
  delete from private.waitlist_signups s
  where s.email = addr
    or s.email in (select i.email from private.signup_invites i where i.claimed_by = account_id);
  delete from private.signup_invites i
  where i.claimed_by = account_id
    or (i.email = addr and i.claimed_by is null);
end
$$;
revoke all on function private.forget_account_invite(uuid, text)
  from public, anon, authenticated, service_role;

-- Runs in the same transaction as the Auth delete (privacy-delete-account's
-- auth.admin.deleteUser, or a delete in the dashboard), so if it fails the account
-- stays and the deletion can be retried.
create function private.handle_deleted_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform private.forget_account_invite(old.id, old.email);
  return old;
end
$$;
revoke all on function private.handle_deleted_auth_user()
  from public, anon, authenticated, service_role;

create trigger auth_user_forget_invite
after delete on auth.users
for each row execute function private.handle_deleted_auth_user();

-- Accounts deleted earlier ------------------------------------------------------------

-- An invite claimed by an account that no longer exists. When the same email
-- signed up again, the trigger's coalesce kept the old claimer: that invite
-- now names the live account. The rest are removed with their waitlist rows.
-- Returns how many invites were removed.
create function private.forget_deleted_account_invites()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  orphan record;
  removed integer := 0;
begin
  update private.signup_invites i set claimed_by = u.id
  from auth.users u
  where lower(btrim(u.email)) = i.email
    and i.claimed_by is not null
    and i.claimed_by <> u.id
    and not exists (select 1 from auth.users claimer where claimer.id = i.claimed_by);
  for orphan in
    select i.email, i.claimed_by from private.signup_invites i
    where i.claimed_by is not null
      and not exists (select 1 from auth.users u where u.id = i.claimed_by)
  loop
    perform private.forget_account_invite(orphan.claimed_by, orphan.email);
    removed := removed + 1;
  end loop;
  return removed;
end
$$;
revoke all on function private.forget_deleted_account_invites()
  from public, anon, authenticated, service_role;

select private.forget_deleted_account_invites();
