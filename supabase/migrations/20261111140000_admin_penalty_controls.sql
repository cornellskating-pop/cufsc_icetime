begin;

create table private.no_show_rules (
  singleton boolean primary key default true check (singleton),
  duration_boundary_minutes integer not null check (duration_boundary_minutes between 1 and 240),
  short_delay_minutes integer not null check (short_delay_minutes between 0 and 120),
  long_delay_minutes integer not null check (long_delay_minutes between 0 and 120),
  version bigint not null default 1,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.users(id) on update cascade on delete set null
);
insert into private.no_show_rules(duration_boundary_minutes, short_delay_minutes, long_delay_minutes) values (35, 5, 8);
alter table private.no_show_rules enable row level security;
revoke all on private.no_show_rules from public, anon, authenticated;

create table private.no_show_rule_changes (
  id uuid primary key default gen_random_uuid(),
  changed_at timestamptz not null default now(),
  changed_by uuid references public.users(id) on update cascade on delete set null,
  previous_rules jsonb not null,
  new_rules jsonb not null
);
alter table private.no_show_rule_changes enable row level security;
revoke all on private.no_show_rule_changes from public, anon, authenticated;

create function public.admin_get_no_show_rules()
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_rules jsonb;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select to_jsonb(r) - 'singleton' - 'updated_by' into v_rules from private.no_show_rules r;
  if v_rules is null then raise exception 'No-show timing rules are unavailable'; end if;
  return v_rules;
end; $$;
revoke all on function public.admin_get_no_show_rules() from public, anon;
grant execute on function public.admin_get_no_show_rules() to authenticated;

create function public.admin_set_no_show_rules(p_duration_boundary_minutes integer, p_short_delay_minutes integer,
  p_long_delay_minutes integer, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_before private.no_show_rules%rowtype; v_after private.no_show_rules%rowtype;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if p_duration_boundary_minutes is null or p_duration_boundary_minutes not between 1 and 240
    or p_short_delay_minutes is null or p_short_delay_minutes not between 0 and 120
    or p_long_delay_minutes is null or p_long_delay_minutes not between 0 and 120 then
    raise exception 'Use a session-length boundary of 1–240 minutes and delays of 0–120 minutes';
  end if;
  select * into v_before from private.no_show_rules where singleton for update;
  if not found then raise exception 'No-show timing rules are unavailable'; end if;
  if p_expected_version is null or v_before.version <> p_expected_version then
    raise exception 'Another admin changed these rules. Reload saved rules before saving';
  end if;
  if (v_before.duration_boundary_minutes, v_before.short_delay_minutes, v_before.long_delay_minutes)
    = (p_duration_boundary_minutes, p_short_delay_minutes, p_long_delay_minutes) then
    return public.admin_get_no_show_rules();
  end if;
  update private.no_show_rules set duration_boundary_minutes = p_duration_boundary_minutes,
    short_delay_minutes = p_short_delay_minutes, long_delay_minutes = p_long_delay_minutes,
    version = version + 1, updated_at = now(), updated_by = auth.uid()
    where singleton returning * into v_after;
  insert into private.no_show_rule_changes(changed_by, previous_rules, new_rules)
    values(auth.uid(), to_jsonb(v_before), to_jsonb(v_after));
  return to_jsonb(v_after) - 'singleton' - 'updated_by';
end; $$;
revoke all on function public.admin_set_no_show_rules(integer, integer, integer, bigint) from public, anon;
grant execute on function public.admin_set_no_show_rules(integer, integer, integer, bigint) to authenticated;

-- Invoker helper runs inside the already-authorized reporting/list RPCs.
-- STABLE, rather than IMMUTABLE, because settings can change between calls.
create or replace function private.no_show_cutoff(p_start timestamptz, p_end timestamptz)
returns timestamptz language sql stable set search_path = public, pg_temp as $$
  select p_start + make_interval(mins => case
    when p_end - p_start < make_interval(mins => r.duration_boundary_minutes)
    then r.short_delay_minutes else r.long_delay_minutes end)
  from private.no_show_rules r where r.singleton;
$$;
revoke all on function private.no_show_cutoff(timestamptz, timestamptz) from public, anon, authenticated;

-- One statement snapshot supplies matching explanatory text and cutoffs.
create function public.admin_no_show_context(p_date date)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  return jsonb_build_object('rules', public.admin_get_no_show_rules(), 'sessions',
    (select coalesce(jsonb_agg(s order by s.start_time, s.id), '[]'::jsonb) from public.admin_no_show_sessions(p_date) s));
end; $$;
revoke all on function public.admin_no_show_context(date) from public, anon;
grant execute on function public.admin_no_show_context(date) to authenticated;

create or replace function public.admin_report_no_shows(p_session_id text, p_booking_ids uuid[])
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_session public.sessions%rowtype;
  v_booking public.bookings%rowtype;
  v_added integer := 0;
  v_existing integer := 0;
  v_date date;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if p_booking_ids is null or cardinality(p_booking_ids) = 0 or cardinality(p_booking_ids) > 100
    or exists (select 1 from unnest(p_booking_ids) x where x is null)
    or (select count(distinct x) from unnest(p_booking_ids) x) <> cardinality(p_booking_ids) then
    raise exception 'Choose 1 to 100 distinct bookings';
  end if;

  -- Serialize a report against rule changes so validation and the saved
  -- cutoff snapshot cannot use different versions of the timing policy.
  perform singleton from private.no_show_rules where singleton for share;
  if not found then raise exception 'No-show timing rules are unavailable'; end if;

  -- Same ordered user locks as booking/marking. NOWAIT on sessions/bookings
  -- avoids reverse-lock waits with member cancellation and session operations.
  perform u.id from public.users u where u.id in
    (select b.user_id from public.bookings b where b.id = any(p_booking_ids))
    order by u.id for update;
  select * into v_session from public.sessions where id = p_session_id for update nowait;
  if not found or v_session.cancelled_at is not null or v_session.capacity <= 0 then
    raise exception 'Session is unavailable for reporting';
  end if;
  if now() < private.no_show_cutoff(v_session.start_time, v_session.end_time) then
    raise exception 'The no-show reporting cutoff has not been reached';
  end if;
  perform b.id from public.bookings b where b.id = any(p_booking_ids) order by b.id for update nowait;
  if (select count(*) from public.bookings b where b.id = any(p_booking_ids) and b.session_id = p_session_id) <> cardinality(p_booking_ids) then
    raise exception 'A selected booking does not belong to this session';
  end if;
  v_date := (v_session.start_time at time zone 'America/New_York')::date;
  for v_booking in select b.* from public.bookings b where b.id = any(p_booking_ids) order by b.id loop
    -- Retries of an existing report are harmless, even if attendance/status
    -- subsequently changes. Corrections use the existing audited undo RPC.
    if exists (select 1 from private.skating_infractions i where i.user_id = v_booking.user_id
      and i.marked_date = v_date and i.voided_at is null and i.reason = 'no_show' and i.booking_id = v_booking.id) then
      v_existing := v_existing + 1;
      continue;
    end if;
    if v_booking.status <> 'active' then raise exception 'A selected skater has cancelled their booking; refresh the roster'; end if;
    if v_booking.present then raise exception 'A selected skater is marked present; refresh the roster'; end if;
    if exists (select 1 from private.skating_infractions i where i.user_id = v_booking.user_id
      and i.marked_date = v_date and i.voided_at is null) then
      v_existing := v_existing + 1;
      continue;
    end if;
    insert into private.skating_infractions(user_id, marked_date, created_by, reason,
      booking_id, session_id, session_start, session_end, reportable_at)
    values (v_booking.user_id, v_date, auth.uid(), 'no_show', v_booking.id, v_session.id,
      v_session.start_time, v_session.end_time, private.no_show_cutoff(v_session.start_time, v_session.end_time));
    v_added := v_added + 1;
  end loop;
  return jsonb_build_object('added', v_added, 'already_marked', v_existing);
exception when lock_not_available then
  raise exception 'Attendance or bookings are being updated. Refresh and retry the entire report';
end; $$;

create function public.admin_user_infractions(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if not exists(select 1 from public.users where id = p_user_id) then raise exception 'User not found'; end if;
  return jsonb_build_object('restriction', private.booking_restriction(p_user_id), 'strikes',
    (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'marked_date', i.marked_date,
      'reason', i.reason, 'session_start', i.session_start, 'created_at', i.created_at)
      order by i.marked_date desc, i.id), '[]'::jsonb)
     from private.skating_infractions i where i.user_id = p_user_id and i.voided_at is null));
end; $$;
revoke all on function public.admin_user_infractions(uuid) from public, anon;
grant execute on function public.admin_user_infractions(uuid) to authenticated;

commit;
