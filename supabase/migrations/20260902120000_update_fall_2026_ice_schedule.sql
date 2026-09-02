begin;

create temporary table desired_fall_2026_sessions (
  id text primary key,
  legacy_id text unique,
  label text,
  start_time timestamptz not null,
  end_time timestamptz not null,
  release_at timestamptz,
  capacity integer not null
) on commit drop;

with ice_dates as (
  select day::date as day
  from generate_series(date '2026-09-09', date '2026-12-07', interval '1 day') as calendar(day)
  where extract(isodow from day) in (1, 3)
    and day::date not between date '2026-10-10' and date '2026-10-13'
    and day::date not between date '2026-11-25' and date '2026-11-29'
),
session_parts as (
  select *
  from (values
    ('2000', '1945', time '20:00:00', time '20:53:00'),
    ('2053', '2045', time '20:53:00', time '21:45:00')
  ) as parts(id_suffix, legacy_suffix, start_at, end_at)
)
insert into desired_fall_2026_sessions (
  id, legacy_id, label, start_time, end_time, release_at, capacity
)
select
  format('CUFSC-%s-%s', to_char(ice_dates.day, 'YYYY-MM-DD'), session_parts.id_suffix),
  case
    when session_parts.legacy_suffix is null then null
    else format('CUFSC-%s-%s', to_char(ice_dates.day, 'YYYY-MM-DD'), session_parts.legacy_suffix)
  end,
  case when ice_dates.day = date '2026-09-16' then 'Tryouts' else 'Club Ice Time' end,
  (ice_dates.day + session_parts.start_at) at time zone 'America/New_York',
  (ice_dates.day + session_parts.end_at) at time zone 'America/New_York',
  (
    ice_dates.day - extract(dow from ice_dates.day)::integer + time '09:00:00'
  ) at time zone 'America/New_York',
  25
from ice_dates
cross join session_parts;

insert into desired_fall_2026_sessions (
  id, legacy_id, label, start_time, end_time, release_at, capacity
)
values
  (
    'CUFSC-2026-09-16-2145',
    null,
    'Tryouts',
    timestamptz '2026-09-16 21:45:00 America/New_York',
    timestamptz '2026-09-16 22:45:00 America/New_York',
    timestamptz '2026-09-13 09:00:00 America/New_York',
    25
  ),
  (
    'CUFSC-2026-12-06-1345',
    'CUFSC-2026-12-06-1400',
    'CUFSC Show',
    timestamptz '2026-12-06 13:45:00 America/New_York',
    timestamptz '2026-12-06 16:45:00 America/New_York',
    timestamptz '2026-11-29 09:00:00 America/New_York',
    0
  );

do $$
declare
  session_count integer;
  total_duration interval;
begin
  select count(*), sum(end_time - start_time)
  into session_count, total_duration
  from desired_fall_2026_sessions;

  if session_count <> 50 or total_duration <> interval '46 hours' then
    raise exception 'Unexpected Fall 2026 schedule: % sessions totaling %', session_count, total_duration;
  end if;
end;
$$;

insert into public.sessions (id, notes, start_time, end_time, release_at, capacity)
select id, label, start_time, end_time, release_at, capacity
from desired_fall_2026_sessions
on conflict (id) do update
set notes = excluded.notes,
    start_time = excluded.start_time,
    end_time = excluded.end_time,
    release_at = excluded.release_at,
    capacity = excluded.capacity;

update public.bookings as bookings
set session_id = desired.id
from desired_fall_2026_sessions as desired
where desired.legacy_id = bookings.session_id
  and desired.legacy_id <> desired.id;

update public.approval_requests as requests
set session_id = desired.id
from desired_fall_2026_sessions as desired
where desired.legacy_id = requests.session_id
  and desired.legacy_id <> desired.id;

delete from public.sessions as sessions
using desired_fall_2026_sessions as desired
where sessions.id = desired.legacy_id
  and desired.legacy_id <> desired.id;

commit;
