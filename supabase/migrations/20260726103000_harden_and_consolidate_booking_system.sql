begin;

-- Keep database-only workers outside the API-exposed public schema. Scheduled
-- jobs have no end-user JWT, so they must not call admin RPCs that depend on
-- auth.uid().
create schema if not exists private;
revoke all on schema private from public;

-- Stop granting every future public object to browser roles by default.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke all on functions from public, anon, authenticated;

-- Remove superseded database entry points and duplicate admin views before
-- changing columns that those views depend on.
drop function if exists public.book_session(text);
drop function if exists public.approve_temp_request(text, text);
drop function if exists public.deny_temp_request(text, text);
drop function if exists public.admin_list_session_bookings();
drop view if exists public.admin_session_bookings;
drop view if exists public.admin_session_bookings_grouped;
drop view if exists public.me;

-- Normalize legacy values and align column types with their actual meaning.
update public.users
set tier = lower(trim(tier));

alter table public.users
  alter column tier set default 'basic';

alter table public.users
  alter column paid_dues type boolean
  using (
    case
      when paid_dues is null then false
      when lower(trim(paid_dues)) in ('true', 't', '1', 'yes', 'y', 'paid') then true
      else false
    end
  ),
  alter column paid_dues set default false,
  alter column paid_dues set not null;

alter table public.users
  drop constraint if exists users_tier_lowercase_check;
alter table public.users
  add constraint users_tier_lowercase_check
  check (tier = lower(tier));

create index if not exists users_email_lower_idx
  on public.users (lower(email));

alter table public.sessions
  alter column release_at drop not null;

alter table public.sessions
  drop constraint if exists sessions_time_order_check;
alter table public.sessions
  add constraint sessions_time_order_check
  check (end_time > start_time) not valid;

alter table public.sessions
  drop constraint if exists sessions_release_before_start_check;
alter table public.sessions
  add constraint sessions_release_before_start_check
  check (release_at is null or release_at < start_time) not valid;

-- Track whether a booking consumed a credit so grace-period and approved
-- bookings can never create credits when they are cancelled.
alter table public.bookings
  add column if not exists credit_charged boolean not null default true;

update public.bookings b
set credit_charged = false
where exists (
  select 1
  from public.sessions s
  where s.id = b.session_id
    and b.created_at >= s.start_time - interval '60 minutes'
)
or exists (
  select 1
  from public.approval_requests ar
  where ar.user_id = b.user_id
    and ar.session_id = b.session_id
    and ar.type = 'SESSION'
    and ar.status = 'APPROVED'
);

-- Make profile-id synchronization and deletion behavior predictable.
alter table public.bookings
  drop constraint if exists bookings_user_id_fkey;
alter table public.bookings
  add constraint bookings_user_id_fkey
  foreign key (user_id) references public.users(id)
  on update cascade on delete cascade;

alter table public.approval_requests
  drop constraint if exists approval_requests_approver_user_id_fkey;
alter table public.approval_requests
  add constraint approval_requests_approver_user_id_fkey
  foreign key (approver_user_id) references public.users(id)
  on update cascade on delete set null;

alter table public.credit_audit
  drop constraint if exists credit_audit_user_id_fkey;
alter table public.credit_audit
  add constraint credit_audit_user_id_fkey
  foreign key (user_id) references public.users(id)
  on update cascade on delete set null;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.users
    where id = auth.uid()
      and is_admin = true
  );
$$;

drop function if exists public.admin_list_sessions();
create function public.admin_list_sessions()
returns table(
  id text,
  label text,
  start_time timestamptz,
  end_time timestamptz,
  release_at timestamptz,
  capacity integer,
  spots_left integer
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  return query
  select
    s.id,
    s.notes,
    s.start_time,
    s.end_time,
    s.release_at,
    s.capacity,
    greatest(
      s.capacity - (count(b.id) filter (where b.status = 'active'))::integer,
      0
    )
  from public.sessions s
  left join public.bookings b on b.session_id = s.id
  group by s.id, s.notes, s.start_time, s.end_time, s.release_at, s.capacity
  order by s.start_time;
end;
$$;

create or replace function public.admin_list_session_bookings_grouped()
returns table(
  session_id text,
  start_time timestamptz,
  end_time timestamptz,
  label text,
  capacity integer,
  active_bookings integer,
  bookings jsonb
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  return query
  select
    s.id,
    s.start_time,
    s.end_time,
    s.notes,
    s.capacity,
    count(b.id)::integer,
    coalesce(
      jsonb_agg(
        jsonb_build_object(
          'booking_id', b.id,
          'created_at', b.created_at,
          'user_id', b.user_id,
          'email', u.email,
          'name', u.name,
          'tier', u.tier,
          'status', b.status
        )
        order by b.created_at
      ) filter (where b.id is not null),
      '[]'::jsonb
    )
  from public.sessions s
  left join public.bookings b
    on b.session_id = s.id
   and b.status = 'active'
  left join public.users u on u.id = b.user_id
  group by s.id, s.start_time, s.end_time, s.notes, s.capacity
  order by s.start_time;
end;
$$;

create or replace function public.admin_list_users()
returns table(
  id uuid,
  email text,
  name text,
  tier text,
  credits_balance integer,
  is_admin boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  return query
  select u.id, u.email, u.name, u.tier, u.credits_balance, u.is_admin
  from public.users u
  order by lower(u.email);
end;
$$;

create or replace function public.admin_list_approvals()
returns table(
  approval_id text,
  type text,
  created_at timestamptz,
  status text,
  user_id uuid,
  user_email text,
  user_name text,
  session_id text,
  start_time timestamptz,
  end_time timestamptz,
  requester_email text,
  approver_user_id uuid,
  decided_at timestamptz,
  notes text
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  return query
  select
    ar.id,
    ar.type,
    ar."timestamp",
    ar.status,
    ar.user_id,
    u.email,
    u.name,
    ar.session_id,
    s.start_time,
    s.end_time,
    ar.requester_email,
    ar.approver_user_id,
    ar.decided_at,
    ar.notes
  from public.approval_requests ar
  left join public.users u on u.id = ar.user_id
  left join public.sessions s on s.id = ar.session_id
  order by ar."timestamp" desc;
end;
$$;

create or replace function public.admin_upsert_session(
  p_id text,
  p_label text,
  p_start_time timestamptz,
  p_end_time timestamptz,
  p_release_at timestamptz,
  p_capacity integer
)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;
  if nullif(trim(p_id), '') is null then
    raise exception 'Session ID is required';
  end if;
  if p_start_time is null or p_end_time is null or p_end_time <= p_start_time then
    raise exception 'End time must be after start time';
  end if;
  if p_release_at is not null and p_release_at >= p_start_time then
    raise exception 'Release time must be before start time';
  end if;
  if p_capacity is null or p_capacity < 0 then
    raise exception 'Capacity cannot be negative';
  end if;

  insert into public.sessions (
    id, notes, start_time, end_time, release_at, capacity
  )
  values (
    trim(p_id),
    nullif(trim(p_label), ''),
    p_start_time,
    p_end_time,
    p_release_at,
    p_capacity
  )
  on conflict (id) do update
  set notes = excluded.notes,
      start_time = excluded.start_time,
      end_time = excluded.end_time,
      release_at = excluded.release_at,
      capacity = excluded.capacity;

  return trim(p_id);
end;
$$;

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
  if p_id = auth.uid() and not coalesce(p_is_admin, false) then
    raise exception 'You cannot remove your own admin access';
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
    coalesce(p_is_admin, false)
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

create or replace function public.admin_delete_session(p_id text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  delete from public.sessions where id = p_id;
  if not found then
    return 'Session not found';
  end if;
  return 'Deleted';
end;
$$;

create or replace function public.admin_delete_user(p_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;
  if p_id = auth.uid() then
    raise exception 'You cannot delete your own account';
  end if;

  delete from public.users where id = p_id;
  if not found then
    return 'User not found';
  end if;
  return 'Deleted';
end;
$$;

create or replace function private.weekly_reset_credits()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.users u
  set credits_balance = greatest(coalesce(t.weekly_credits, 0), 0)
  from public.tiers t
  where lower(u.tier) = lower(t.name);

  return 'Weekly credits reset from tiers table';
end;
$$;

revoke all on function private.weekly_reset_credits() from public;

create or replace function private.scheduled_weekly_reset_credits()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_eastern_now timestamp := clock_timestamp() at time zone 'America/New_York';
begin
  -- pg_cron schedules are UTC. The job runs at both possible UTC equivalents
  -- of 4:30 PM Eastern; only the invocation that is actually 4:30 PM in New
  -- York performs the reset. This remains correct across DST transitions.
  if extract(isodow from v_eastern_now) <> 7
     or extract(hour from v_eastern_now) <> 16
     or extract(minute from v_eastern_now) <> 30 then
    return 'Skipped: not Sunday at 4:30 PM America/New_York';
  end if;

  return private.weekly_reset_credits();
end;
$$;

revoke all on function private.scheduled_weekly_reset_credits() from public;

create or replace function public.admin_weekly_reset_credits()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  return private.weekly_reset_credits();
end;
$$;

-- Preserve the production job's existing name and schedule, but point it at
-- the database-only worker. Dynamic SQL keeps local replay compatible when
-- pg_cron is not installed.
do $$
declare
  v_updated integer := 0;
begin
  if to_regclass('cron.job') is not null then
    execute $statement$
      update cron.job
      set schedule = '30 20,21 * * 0',
          command = 'select private.scheduled_weekly_reset_credits();'
      where lower(command) like '%admin_weekly_reset_credits%'
    $statement$;
    get diagnostics v_updated = row_count;
  end if;

  if v_updated = 0 then
    raise notice 'No existing weekly credit reset cron command was updated';
  end if;
end;
$$;

create or replace function public.admin_approve_request(p_request_id text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_request public.approval_requests%rowtype;
  v_session public.sessions%rowtype;
  v_active_count integer;
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  select * into v_request
  from public.approval_requests
  where id = p_request_id
  for update;

  if not found then return 'Request not found'; end if;
  if v_request.type <> 'SESSION' then return 'Not a session request'; end if;
  if v_request.status <> 'OPEN' then return 'Request not open'; end if;
  if v_request.user_id is null then return 'Request has no user'; end if;

  select * into v_session
  from public.sessions
  where id = v_request.session_id
  for update;

  if not found then
    update public.approval_requests
    set status = 'FAILED',
        approver_user_id = auth.uid(),
        decided_at = now(),
        notes = 'Session missing'
    where id = p_request_id;
    return 'Session missing; request failed';
  end if;

  if now() >= v_session.start_time then
    update public.approval_requests
    set status = 'FAILED',
        approver_user_id = auth.uid(),
        decided_at = now(),
        notes = 'Session already started'
    where id = p_request_id;
    return 'Session already started; request failed';
  end if;

  if exists (
    select 1
    from public.bookings
    where user_id = v_request.user_id
      and session_id = v_session.id
      and status = 'active'
  ) then
    update public.approval_requests
    set status = 'APPROVED',
        approver_user_id = auth.uid(),
        decided_at = now(),
        notes = 'User was already booked'
    where id = p_request_id;
    return 'Already booked; request approved';
  end if;

  select count(*) into v_active_count
  from public.bookings
  where session_id = v_session.id
    and status = 'active';

  if v_active_count >= v_session.capacity then
    return 'Session is full';
  end if;

  insert into public.bookings (
    user_id, session_id, status, credit_charged
  )
  values (
    v_request.user_id, v_session.id, 'active', false
  );

  update public.approval_requests
  set status = 'APPROVED',
      approver_user_id = auth.uid(),
      decided_at = now()
  where id = p_request_id;

  return 'Approved + booked';
end;
$$;

create or replace function public.admin_approve_user_request(p_request_id text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_request public.approval_requests%rowtype;
  v_auth_id uuid;
  v_existing_id uuid;
  v_user_id uuid;
  v_name text;
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  select * into v_request
  from public.approval_requests
  where id = p_request_id
  for update;

  if not found then return 'Request not found'; end if;
  if v_request.type <> 'NEW_USER' then return 'Not a new-user request'; end if;
  if v_request.status <> 'OPEN' then return 'Request not open'; end if;
  if nullif(trim(v_request.requester_email), '') is null then
    return 'Request has no email';
  end if;

  select
    id,
    coalesce(raw_user_meta_data->>'full_name', raw_user_meta_data->>'name')
  into v_auth_id, v_name
  from auth.users
  where lower(email) = lower(v_request.requester_email)
  limit 1;

  select id into v_existing_id
  from public.users
  where lower(email) = lower(v_request.requester_email)
  limit 1;

  v_user_id := coalesce(v_existing_id, v_auth_id, gen_random_uuid());

  if v_existing_id is null then
    insert into public.users (
      id, email, name, tier, credits_balance, is_admin, paid_dues
    )
    values (
      v_user_id,
      lower(trim(v_request.requester_email)),
      v_name,
      'temp',
      0,
      false,
      false
    );
  else
    update public.users
    set email = lower(trim(v_request.requester_email)),
        name = coalesce(name, v_name)
    where id = v_existing_id;
  end if;

  update public.approval_requests
  set status = 'APPROVED',
      user_id = v_user_id,
      approver_user_id = auth.uid(),
      decided_at = now()
  where id = p_request_id;

  return 'Approved: user created';
end;
$$;

create or replace function public.admin_deny_request(p_request_id text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  update public.approval_requests
  set status = 'DENIED',
      approver_user_id = auth.uid(),
      decided_at = now()
  where id = p_request_id
    and status = 'OPEN';

  if not found then
    return 'Request not found or not open';
  end if;
  return 'Denied';
end;
$$;

create or replace function public.request_user_access()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_email text := lower(auth.jwt() ->> 'email');
begin
  if auth.uid() is null or nullif(v_email, '') is null then
    raise exception 'Not authenticated';
  end if;
  if exists (
    select 1 from public.users where lower(email) = v_email
  ) then
    return 'Already a member';
  end if;
  if exists (
    select 1
    from public.approval_requests
    where type = 'NEW_USER'
      and lower(requester_email) = v_email
      and status = 'OPEN'
  ) then
    return 'PENDING';
  end if;

  insert into public.approval_requests (
    id, type, requester_email, status
  )
  values (
    gen_random_uuid()::text, 'NEW_USER', v_email, 'OPEN'
  );

  return 'REQUESTED';
end;
$$;

create or replace function public.book_sessions(session_ids text[])
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_credits integer;
  v_tier text;
  v_session_id text;
  v_session public.sessions%rowtype;
  v_active_count integer;
  v_grace boolean;
  v_results jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;
  if session_ids is null or cardinality(session_ids) = 0 then
    raise exception 'Select at least one session';
  end if;
  if cardinality(session_ids) > 2 then
    raise exception 'You can book at most two sessions at a time';
  end if;
  if exists (
    select 1
    from unnest(session_ids) as item(value)
    where value is null
  ) then
    raise exception 'Session IDs cannot be null';
  end if;
  if (
    select count(distinct value)
    from unnest(session_ids) as item(value)
  ) <> cardinality(session_ids) then
    raise exception 'Duplicate session IDs are not allowed';
  end if;

  select credits_balance, lower(tier)
  into v_credits, v_tier
  from public.users
  where id = v_user_id
  for update;

  if not found then
    raise exception 'User not found';
  end if;

  foreach v_session_id in array session_ids
  loop
    select * into v_session
    from public.sessions
    where id = v_session_id
    for update;

    if not found then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Session not found'
      );
      continue;
    end if;

    if v_session.release_at is not null and now() < v_session.release_at then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Session is not open yet'
      );
      continue;
    end if;

    if now() >= v_session.start_time then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Session already started'
      );
      continue;
    end if;

    if exists (
      select 1
      from public.bookings
      where user_id = v_user_id
        and session_id = v_session_id
        and status = 'active'
    ) then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Already booked'
      );
      continue;
    end if;

    select count(*) into v_active_count
    from public.bookings
    where session_id = v_session_id
      and status = 'active';

    if v_active_count >= v_session.capacity then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Session is full'
      );
      continue;
    end if;

    if v_tier = 'temp' and v_credits <= 0 then
      if exists (
        select 1
        from public.approval_requests
        where user_id = v_user_id
          and session_id = v_session_id
          and status = 'OPEN'
          and type = 'SESSION'
      ) then
        v_results := v_results || jsonb_build_object(
          'ok', true,
          'session_id', v_session_id,
          'message', 'Approval request already pending'
        );
      else
        insert into public.approval_requests (
          id, type, user_id, session_id, status
        )
        values (
          gen_random_uuid()::text,
          'SESSION',
          v_user_id,
          v_session_id,
          'OPEN'
        );
        v_results := v_results || jsonb_build_object(
          'ok', true,
          'session_id', v_session_id,
          'message', 'Approval request submitted'
        );
      end if;
      continue;
    end if;

    v_grace := v_session.start_time - now() <= interval '60 minutes';

    if v_credits <= 0 and not v_grace then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Not enough credits'
      );
      continue;
    end if;

    insert into public.bookings (
      user_id, session_id, status, credit_charged
    )
    values (
      v_user_id, v_session_id, 'active', not v_grace
    );

    if not v_grace then
      v_credits := v_credits - 1;
      update public.users
      set credits_balance = v_credits
      where id = v_user_id;

      insert into public.credit_audit (
        action, user_id, tier, credits_after
      )
      values (
        'BOOK', v_user_id, v_tier, v_credits
      );
    end if;

    v_results := v_results || jsonb_build_object(
      'ok', true,
      'session_id', v_session_id,
      'message', 'Booked successfully'
    );
  end loop;

  return v_results;
end;
$$;

create or replace function public.cancel_booking(p_booking_id uuid)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_booking public.bookings%rowtype;
  v_session public.sessions%rowtype;
  v_user public.users%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  select * into v_booking
  from public.bookings
  where id = p_booking_id
    and user_id = auth.uid()
    and status = 'active'
  for update;

  if not found then return 'Booking not found'; end if;

  select * into v_session
  from public.sessions
  where id = v_booking.session_id;

  if not found then return 'Session not found'; end if;
  if now() > v_session.end_time then return 'Session already ended'; end if;
  if now() > v_session.start_time + interval '30 minutes' then
    return 'This booking can no longer be cancelled because the session started more than 30 minutes ago.';
  end if;

  select * into v_user
  from public.users
  where id = auth.uid()
  for update;

  if not found then return 'User not found'; end if;

  update public.bookings
  set status = 'cancelled'
  where id = p_booking_id;

  if v_booking.credit_charged
     and now() <= v_session.start_time - interval '30 minutes' then
    update public.users
    set credits_balance = credits_balance + 1
    where id = v_user.id;

    insert into public.credit_audit (
      action, user_id, tier, credits_after
    )
    values (
      'CANCEL_REFUND',
      v_user.id,
      lower(v_user.tier),
      v_user.credits_balance + 1
    );
  end if;

  return 'Cancelled';
end;
$$;

-- Let the caller's RLS policies protect the per-user booking view.
alter view public.my_bookings set (security_invoker = true);

-- Replace overlapping policies with one policy per intended capability.
drop policy if exists "admin modify sessions" on public.sessions;
drop policy if exists "read sessions" on public.sessions;
drop policy if exists "sessions_admin_write" on public.sessions;
drop policy if exists "sessions_read" on public.sessions;
drop policy if exists "sessions_read_allowlisted" on public.sessions;
create policy sessions_select_authenticated
  on public.sessions
  for select
  to authenticated
  using (auth.uid() is not null);
create policy sessions_admin_all
  on public.sessions
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "bookings_cancel_own" on public.bookings;
drop policy if exists "bookings_insert_own" on public.bookings;
drop policy if exists "bookings_select_own" on public.bookings;
drop policy if exists "bookings_update_own" on public.bookings;
create policy bookings_select_own_or_admin
  on public.bookings
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists "approvals_admin_update" on public.approval_requests;
drop policy if exists "approvals_insert" on public.approval_requests;
drop policy if exists "approvals_insert_allowlisted" on public.approval_requests;
drop policy if exists "approvals_select" on public.approval_requests;
drop policy if exists "approvals_update" on public.approval_requests;
create policy approvals_select_own_or_admin
  on public.approval_requests
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists "users_admin_all" on public.users;
drop policy if exists "users_select_own" on public.users;
drop policy if exists "users_update_own" on public.users;
create policy users_select_own_or_admin
  on public.users
  for select
  to authenticated
  using (id = auth.uid() or public.is_admin());
create policy users_admin_all
  on public.users
  for all
  to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "tiers_read_allowlisted" on public.tiers;
create policy tiers_select_authenticated
  on public.tiers
  for select
  to authenticated
  using (auth.uid() is not null);

-- Browser roles get only the direct reads needed by the UI. All writes go
-- through the reviewed SECURITY DEFINER functions above.
revoke all privileges on all tables in schema public from anon, authenticated;
grant select on public.users to authenticated;
grant select on public.sessions to authenticated;
grant select on public.bookings to authenticated;
grant select on public.tiers to authenticated;
grant select on public.my_bookings to authenticated;
grant select on public.sessions_with_spots to authenticated;

revoke all privileges on all functions in schema public from public, anon, authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.request_user_access() to authenticated;
grant execute on function public.book_sessions(text[]) to authenticated;
grant execute on function public.cancel_booking(uuid) to authenticated;
grant execute on function public.admin_list_sessions() to authenticated;
grant execute on function public.admin_list_session_bookings_grouped() to authenticated;
grant execute on function public.admin_list_users() to authenticated;
grant execute on function public.admin_list_approvals() to authenticated;
grant execute on function public.admin_upsert_session(text, text, timestamptz, timestamptz, timestamptz, integer) to authenticated;
grant execute on function public.admin_upsert_user(uuid, text, text, text, integer, boolean) to authenticated;
grant execute on function public.admin_delete_session(text) to authenticated;
grant execute on function public.admin_delete_user(uuid) to authenticated;
grant execute on function public.admin_weekly_reset_credits() to authenticated;
grant execute on function public.admin_approve_request(text) to authenticated;
grant execute on function public.admin_approve_user_request(text) to authenticated;
grant execute on function public.admin_deny_request(text) to authenticated;

-- Replace the leaked service-role header with a secret stored independently
-- in Supabase Vault and in the Edge Function environment.
drop trigger if exists "notify-admins-on-approval" on public.approval_requests;

create or replace function public.notify_admins_webhook()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_webhook_secret text;
begin
  select decrypted_secret
  into v_webhook_secret
  from vault.decrypted_secrets
  where name = 'notify_admins_webhook_secret'
  order by created_at desc
  limit 1;

  if v_webhook_secret is null then
    raise warning 'notify_admins_webhook_secret is not configured; notification skipped';
    return new;
  end if;

  perform net.http_post(
    url := 'https://dtdyvpjmavurynbccjei.supabase.co/functions/v1/notify-admins',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', v_webhook_secret
    ),
    body := jsonb_build_object(
      'type', 'INSERT',
      'schema', 'public',
      'table', 'approval_requests',
      'record', jsonb_build_object('id', new.id)
    )
  );

  return new;
end;
$$;

revoke all on function public.notify_admins_webhook() from public, anon, authenticated;

create trigger "notify-admins-on-approval"
after insert on public.approval_requests
for each row execute function public.notify_admins_webhook();

commit;
