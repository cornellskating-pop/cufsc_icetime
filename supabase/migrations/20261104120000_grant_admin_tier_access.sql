begin;

-- Keep the existing authorization flag authoritative for all consumers, including
-- browser gates, RPCs, notifications, and weekly credits. Only trusted writers
-- can change user tiers; this trigger does not grant table-write privileges.
create or replace function private.enforce_admin_tier_access()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if lower(trim(new.tier)) = 'admin' then
    new.is_admin := true;
  end if;
  return new;
end;
$$;
revoke all on function private.enforce_admin_tier_access() from public, anon, authenticated;

create trigger enforce_admin_tier_access
before insert or update on public.users
for each row execute function private.enforce_admin_tier_access();

-- Repair existing mismatches without changing credits or other admin accounts.
update public.users set is_admin = true
where lower(trim(tier)) = 'admin' and is_admin is not true;

alter table public.users add constraint users_admin_tier_access_check
check (lower(trim(tier)) <> 'admin' or is_admin is true);

create or replace function public.admin_upsert_user(
  p_id uuid,
  p_email text,
  p_name text,
  p_tier text,
  p_credits_balance integer,
  p_is_admin boolean
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_id uuid;
  v_existing_id uuid;
  v_auth_id uuid;
  v_email text := lower(trim(p_email));
  v_tier text := lower(trim(p_tier));
  v_is_admin boolean := coalesce(p_is_admin, false) or lower(trim(p_tier)) = 'admin';
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;
  if nullif(v_email, '') is null then
    raise exception 'Email is required';
  end if;
  if nullif(v_tier, '') is null then
    raise exception 'Tier is required';
  end if;
  if p_credits_balance is null or p_credits_balance < 0 then
    raise exception 'Credits cannot be negative';
  end if;

  select id into v_existing_id
  from public.users
  where lower(email) = v_email
  limit 1;

  select id into v_auth_id
  from auth.users
  where lower(email) = v_email
  limit 1;

  v_id := coalesce(p_id, v_existing_id, v_auth_id, gen_random_uuid());

  if v_id = auth.uid() and not coalesce(v_is_admin, false) then
    raise exception 'You cannot remove your own admin access';
  end if;


  if v_existing_id is not null and v_existing_id <> v_id then
    raise exception 'Another user already has this email';
  end if;

  insert into public.users (
    id, email, name, tier, credits_balance, is_admin
  )
  values (
    v_id,
    v_email,
    nullif(trim(p_name), ''),
    v_tier,
    p_credits_balance,
    coalesce(v_is_admin, false)
  )
  on conflict (id) do update
  set email = excluded.email,
      name = excluded.name,
      tier = excluded.tier,
      credits_balance = excluded.credits_balance,
      is_admin = excluded.is_admin;

  return v_id;
end;
$$;

revoke all on function public.admin_upsert_user(uuid, text, text, text, integer, boolean) from public, anon;
grant execute on function public.admin_upsert_user(uuid, text, text, text, integer, boolean) to authenticated;

commit;
