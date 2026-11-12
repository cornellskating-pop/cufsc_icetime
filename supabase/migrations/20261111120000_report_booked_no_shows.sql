begin;

alter table private.skating_infractions
  add column reason text not null default 'unregistered' check (reason in ('unregistered', 'no_show')),
  add column booking_id uuid references public.bookings(id) on delete set null,
  add column session_id text references public.sessions(id) on update cascade on delete set null,
  add column session_start timestamptz,
  add column session_end timestamptz,
  add column reportable_at timestamptz,
  add constraint no_show_snapshot_check check (reason <> 'no_show' or
    (session_start is not null and session_end is not null and reportable_at is not null));
create index skating_infractions_booking on private.skating_infractions(booking_id) where voided_at is null;

create function private.no_show_cutoff(p_start timestamptz, p_end timestamptz)
returns timestamptz language sql immutable set search_path = public, pg_temp as $$
  select p_start + case when p_end - p_start < interval '35 minutes'
    then interval '5 minutes' else interval '8 minutes' end;
$$;
revoke all on function private.no_show_cutoff(timestamptz, timestamptz) from public, anon, authenticated;

create function public.admin_no_show_sessions(p_date date)
returns table (id text, start_time timestamptz, end_time timestamptz, label text, reportable_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if p_date is null then raise exception 'Choose a date'; end if;
  return query select s.id, s.start_time, s.end_time, s.notes, private.no_show_cutoff(s.start_time, s.end_time)
    from public.sessions s
    where (s.start_time at time zone 'America/New_York')::date = p_date
      and s.start_time <= now() and s.cancelled_at is null and s.capacity > 0
    order by s.start_time, s.id;
end; $$;
revoke all on function public.admin_no_show_sessions(date) from public, anon;
grant execute on function public.admin_no_show_sessions(date) to authenticated;

create function public.admin_no_show_roster(p_session_id text)
returns table (booking_id uuid, name text, email text, present boolean, booking_status text,
  already_marked boolean, no_show_mark_id uuid)
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_session public.sessions%rowtype;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select * into v_session from public.sessions where id = p_session_id;
  if not found or v_session.cancelled_at is not null or v_session.capacity <= 0 or v_session.start_time > now() then
    raise exception 'Choose an ongoing or past bookable session';
  end if;
  return query select b.id, u.name, u.email, b.present, b.status,
    i.id is not null,
    case when i.reason = 'no_show' and i.booking_id = b.id then i.id else null end
    from public.bookings b join public.users u on u.id = b.user_id
    left join private.skating_infractions i on i.user_id = b.user_id
      and i.marked_date = (v_session.start_time at time zone 'America/New_York')::date and i.voided_at is null
    where b.session_id = p_session_id and (b.status = 'active' or (i.reason = 'no_show' and i.booking_id = b.id))
    order by b.created_at, b.id;
end; $$;
revoke all on function public.admin_no_show_roster(text) from public, anon;
grant execute on function public.admin_no_show_roster(text) to authenticated;

create function public.admin_report_no_shows(p_session_id text, p_booking_ids uuid[])
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
revoke all on function public.admin_report_no_shows(text, uuid[]) from public, anon;
grant execute on function public.admin_report_no_shows(text, uuid[]) to authenticated;

commit;
