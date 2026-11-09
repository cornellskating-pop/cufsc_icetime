begin;

alter table public.bookings
  add column present boolean not null default false,
  add column attendance_marked_at timestamptz,
  add column attendance_marked_by uuid references public.users(id) on update cascade on delete set null;

create table private.skating_infractions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on update cascade on delete cascade,
  marked_date date not null,
  created_at timestamptz not null default now(),
  created_by uuid references public.users(id) on update cascade on delete set null,
  voided_at timestamptz,
  voided_by uuid references public.users(id) on update cascade on delete set null
);
alter table private.skating_infractions enable row level security;
revoke all on private.skating_infractions from public, anon, authenticated;
create unique index skating_infractions_active_day on private.skating_infractions(user_id, marked_date) where voided_at is null;

-- A semester is Jan-Jul or Aug-Dec. Every third non-void mark starts a
-- restriction lasting through the next four distinct Eastern bookable dates.
-- Derive dates from the schedule so breaks, cancellation, and multiple blocks
-- per day are handled without a fixed fourteen-day approximation.
create function private.booking_restriction(p_user_id uuid, p_at timestamptz default now())
returns jsonb language plpgsql stable security definer
set search_path = public, pg_temp as $$
declare
  v_today date := (p_at at time zone 'America/New_York')::date;
  v_anchor date;
  v_days integer;
  v_elapsed integer;
  v_end timestamptz;
  v_blocked boolean := false;
  v_until timestamptz;
  v_remaining integer := 0;
  v_marks integer;
begin
  select count(*) into v_marks from private.skating_infractions i
  where i.user_id = p_user_id and i.voided_at is null
    and extract(year from i.marked_date) = extract(year from v_today)
    and (extract(month from i.marked_date) >= 8) = (extract(month from v_today) >= 8);
  for v_anchor in
    select marked_date from (
      select i.marked_date, row_number() over (
        partition by extract(year from i.marked_date), (extract(month from i.marked_date) >= 8)
        order by i.marked_date, i.id) as n
      from private.skating_infractions i where i.user_id = p_user_id
        and i.voided_at is null and i.marked_date <= v_today
    ) marks where n % 3 = 0
  loop
    select count(*), count(*) filter (where day_end <= p_at), max(day_end)
      into v_days, v_elapsed, v_end from (
        select (s.start_time at time zone 'America/New_York')::date as ice_date,
          max(s.end_time) as day_end
        from public.sessions s
        where s.capacity > 0 and s.cancelled_at is null
          and (s.start_time at time zone 'America/New_York')::date > v_anchor
        group by (s.start_time at time zone 'America/New_York')::date
        order by ice_date limit 4
      ) days;
    if v_days < 4 or p_at < v_end then
      v_blocked := true;
      v_remaining := greatest(v_remaining, 4 - v_elapsed);
      v_until := greatest(v_until, v_end);
      -- An unfinished schedule has no promised end date.
      if v_days < 4 then
        return jsonb_build_object('blocked', true, 'marks', v_marks, 'ends_at', null, 'remaining_days', v_remaining);
      end if;
    end if;
  end loop;
  return jsonb_build_object('blocked', v_blocked, 'marks', v_marks,
    'ends_at', v_until, 'remaining_days', v_remaining);
end; $$;
revoke all on function private.booking_restriction(uuid, timestamptz) from public, anon, authenticated;

create function public.my_booking_restriction()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null or not exists (select 1 from public.users where id = auth.uid()) then raise exception 'Not authorized'; end if;
  return private.booking_restriction(auth.uid());
end; $$;
revoke all on function public.my_booking_restriction() from public, anon;
grant execute on function public.my_booking_restriction() to authenticated;

-- Cover every creation/re-activation path, including admin approvals and
-- restoration. The user lock serializes new bookings against marking/voiding.
create function private.enforce_booking_restriction()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if new.status = 'active' then
    perform id from public.users where id = new.user_id for update;
    if (private.booking_restriction(new.user_id)->>'blocked')::boolean then
      raise exception 'Booking restricted after three infractions; wait until four ice days have finished';
    end if;
  end if;
  return new;
end; $$;
revoke all on function private.enforce_booking_restriction() from public, anon, authenticated;
create trigger enforce_booking_restriction before insert or update of status, user_id, session_id on public.bookings
for each row execute function private.enforce_booking_restriction();

create function public.admin_set_attendance(p_booking_id uuid, p_present boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_booking public.bookings%rowtype;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if p_present is null then raise exception 'Present is required'; end if;
  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found or v_booking.status <> 'active' then raise exception 'Active booking not found'; end if;
  if not exists (select 1 from public.sessions where id = v_booking.session_id and start_time <= now() and cancelled_at is null) then
    raise exception 'Attendance can only be marked after the session starts';
  end if;
  update public.bookings set present = p_present, attendance_marked_at = now(), attendance_marked_by = auth.uid() where id = p_booking_id;
end; $$;
revoke all on function public.admin_set_attendance(uuid, boolean) from public, anon;
grant execute on function public.admin_set_attendance(uuid, boolean) to authenticated;

create function public.admin_search_skaters(p_query text, p_date date)
returns table (id uuid, name text, email text, marks integer, marked_on_date boolean, restriction jsonb)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if p_query is null or length(trim(p_query)) < 2 then return; end if;
  if p_date is null then raise exception 'Date is required'; end if;
  return query select u.id, u.name, u.email,
    (select count(*)::integer from private.skating_infractions i where i.user_id = u.id and i.voided_at is null
      and extract(year from i.marked_date) = extract(year from p_date)
      and (extract(month from i.marked_date) >= 8) = (extract(month from p_date) >= 8)),
    exists (select 1 from private.skating_infractions i where i.user_id = u.id and i.marked_date = p_date and i.voided_at is null),
    private.booking_restriction(u.id)
  from public.users u where strpos(lower(coalesce(u.name, '')), lower(trim(p_query))) > 0
    or strpos(lower(u.email), lower(trim(p_query))) > 0
  order by u.name nulls last, u.id limit 20;
end; $$;
revoke all on function public.admin_search_skaters(text, date) from public, anon;
grant execute on function public.admin_search_skaters(text, date) to authenticated;

create function public.admin_submit_infractions(p_user_ids uuid[], p_date date)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid; v_added integer := 0; v_count integer;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if p_date is null or p_date > (now() at time zone 'America/New_York')::date then raise exception 'Enter a valid date that is not in the future'; end if;
  if p_user_ids is null or cardinality(p_user_ids) = 0 or cardinality(p_user_ids) > 100
    or exists (select 1 from unnest(p_user_ids) x where x is null)
    or (select count(distinct x) from unnest(p_user_ids) x) <> cardinality(p_user_ids) then
    raise exception 'Choose 1 to 100 distinct skaters';
  end if;
  perform id from public.users where id = any(p_user_ids) order by id for update;
  if (select count(*) from public.users where id = any(p_user_ids)) <> cardinality(p_user_ids) then raise exception 'Skater account not found'; end if;
  foreach v_user in array p_user_ids loop
    insert into private.skating_infractions(user_id, marked_date, created_by)
      values (v_user, p_date, auth.uid()) on conflict (user_id, marked_date) where voided_at is null do nothing;
    get diagnostics v_count = row_count;
    v_added := v_added + v_count;
  end loop;
  return jsonb_build_object('added', v_added, 'already_marked', cardinality(p_user_ids) - v_added);
end; $$;
revoke all on function public.admin_submit_infractions(uuid[], date) from public, anon;
grant execute on function public.admin_submit_infractions(uuid[], date) to authenticated;

create function public.admin_list_infractions(p_date date)
returns table (id uuid, user_id uuid, name text, email text, marked_date date, restriction jsonb)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  return query select i.id, u.id, u.name, u.email, i.marked_date, private.booking_restriction(u.id)
    from private.skating_infractions i join public.users u on u.id = i.user_id
    where i.marked_date = p_date and i.voided_at is null order by u.name, u.id;
end; $$;
revoke all on function public.admin_list_infractions(date) from public, anon;
grant execute on function public.admin_list_infractions(date) to authenticated;

create function public.admin_void_infraction(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select user_id into v_user from private.skating_infractions where id = p_id;
  if not found then raise exception 'Infraction not found'; end if;
  perform id from public.users where id = v_user for update;
  update private.skating_infractions set voided_at = now(), voided_by = auth.uid() where id = p_id and voided_at is null;
end; $$;
revoke all on function public.admin_void_infraction(uuid) from public, anon;
grant execute on function public.admin_void_infraction(uuid) to authenticated;

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
          'status', b.status,
          'present', b.present
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

  if (private.booking_restriction(v_user_id)->>'blocked')::boolean then
    raise exception 'Booking restricted after three infractions; wait until four ice days have finished';
  end if;

  -- Acquire session locks in a consistent order for larger overlapping batches.
  perform s.id from public.sessions s where s.id = any(session_ids) order by s.id for update;

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

    if now() >= v_session.end_time then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Session already ended'
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

  perform id from public.users where id = v_request.user_id for update;
  if (private.booking_restriction(v_request.user_id)->>'blocked')::boolean then
    raise exception 'Booking restricted after three infractions; wait until four ice days have finished';
  end if;

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

  if now() >= v_session.end_time then
    update public.approval_requests
    set status = 'FAILED',
        approver_user_id = auth.uid(),
        decided_at = now(),
        notes = 'Session already ended'
    where id = p_request_id;
    return 'Session already ended; request failed';
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


commit;
