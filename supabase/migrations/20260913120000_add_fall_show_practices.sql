begin;

create temporary table affected_show_practice_dates (
  day date primary key
) on commit drop;

insert into affected_show_practice_dates (day)
select day::date
from generate_series(date '2026-10-21', date '2026-11-18', interval '7 days') as dates(day)
union all
select day::date
from generate_series(date '2026-10-26', date '2026-11-30', interval '7 days') as dates(day)
union all
select date '2026-12-02';

do $$
declare
  affected_date_count integer;
  existing_session_count integer;
begin
  perform sessions.id
  from public.sessions as sessions
  join affected_show_practice_dates as dates
    on (sessions.start_time at time zone 'America/New_York')::date = dates.day
  where sessions.id like 'CUFSC-2026-%'
  for update of sessions;

  select count(*) into affected_date_count
  from affected_show_practice_dates;

  if affected_date_count <> 12 then
    raise exception 'Expected 12 show-practice dates, found %', affected_date_count;
  end if;

  select count(*) into existing_session_count
  from public.sessions as sessions
  join affected_show_practice_dates as dates
    on (sessions.start_time at time zone 'America/New_York')::date = dates.day
  where sessions.id like 'CUFSC-2026-%';

  if existing_session_count <> 24 then
    raise exception 'Expected 24 existing sessions on show-practice dates, found %', existing_session_count;
  end if;

  if exists (
    select 1
    from public.bookings as bookings
    join public.sessions as sessions on sessions.id = bookings.session_id
    join affected_show_practice_dates as dates
      on (sessions.start_time at time zone 'America/New_York')::date = dates.day
    where sessions.id like 'CUFSC-2026-%'
  ) then
    raise exception 'Show-practice sessions already have booking history and were not changed';
  end if;

  if exists (
    select 1
    from public.approval_requests as requests
    join public.sessions as sessions on sessions.id = requests.session_id
    join affected_show_practice_dates as dates
      on (sessions.start_time at time zone 'America/New_York')::date = dates.day
    where sessions.id like 'CUFSC-2026-%'
  ) then
    raise exception 'Show-practice sessions already have approval history and were not changed';
  end if;
end;
$$;

create temporary table desired_show_practice_sessions (
  id text primary key,
  label text not null,
  start_time timestamptz not null,
  end_time timestamptz not null,
  release_at timestamptz not null,
  capacity integer not null
) on commit drop;

with monday_dates as (
  select day::date as day
  from generate_series(date '2026-10-26', date '2026-11-30', interval '7 days') as dates(day)
),
monday_parts as (
  select *
  from (values
    ('2000', 'Club Ice Time', time '20:00:00', time '20:35:00', 25),
    ('2035', 'Club Ice Time', time '20:35:00', time '21:10:00', 25),
    ('2110', 'Show practice: Grp Large', time '21:10:00', time '21:45:00', 0)
  ) as parts(id_suffix, label, start_at, end_at, capacity)
)
insert into desired_show_practice_sessions (
  id, label, start_time, end_time, release_at, capacity
)
select
  format('CUFSC-%s-%s', to_char(monday_dates.day, 'YYYY-MM-DD'), monday_parts.id_suffix),
  monday_parts.label,
  (monday_dates.day + monday_parts.start_at) at time zone 'America/New_York',
  (monday_dates.day + monday_parts.end_at) at time zone 'America/New_York',
  (
    monday_dates.day - extract(dow from monday_dates.day)::integer + time '21:00:00'
  ) at time zone 'America/New_York',
  monday_parts.capacity
from monday_dates
cross join monday_parts;

with wednesday_dates as (
  select day::date as day
  from generate_series(date '2026-10-21', date '2026-11-18', interval '7 days') as dates(day)
),
wednesday_parts as (
  select *
  from (values
    ('2000', 'Club Ice Time', time '20:00:00', time '20:33:00', 25),
    ('2033', 'Club Ice Time', time '20:33:00', time '21:05:00', 25),
    ('2105', 'Show practice: Grp 2', time '21:05:00', time '21:25:00', 0),
    ('2125', 'Show practice: Grp 1 / Ice Dance', time '21:25:00', time '21:45:00', 0)
  ) as parts(id_suffix, label, start_at, end_at, capacity)
)
insert into desired_show_practice_sessions (
  id, label, start_time, end_time, release_at, capacity
)
select
  format('CUFSC-%s-%s', to_char(wednesday_dates.day, 'YYYY-MM-DD'), wednesday_parts.id_suffix),
  wednesday_parts.label,
  (wednesday_dates.day + wednesday_parts.start_at) at time zone 'America/New_York',
  (wednesday_dates.day + wednesday_parts.end_at) at time zone 'America/New_York',
  (
    wednesday_dates.day - extract(dow from wednesday_dates.day)::integer + time '21:00:00'
  ) at time zone 'America/New_York',
  wednesday_parts.capacity
from wednesday_dates
cross join wednesday_parts;

insert into desired_show_practice_sessions (
  id, label, start_time, end_time, release_at, capacity
)
values (
  'CUFSC-2026-12-02-2000',
  'Show practice: Grp Large / Grp 2 / Grp 1 / Ice Dance (Dress rehearsal)',
  timestamptz '2026-12-02 20:00:00 America/New_York',
  timestamptz '2026-12-02 21:45:00 America/New_York',
  timestamptz '2026-11-29 21:00:00 America/New_York',
  0
);

do $$
declare
  desired_session_count integer;
  zero_capacity_count integer;
  total_duration interval;
  member_duration interval;
begin
  select
    count(*),
    count(*) filter (where capacity = 0),
    sum(end_time - start_time),
    sum(end_time - start_time) filter (where capacity > 0)
  into desired_session_count, zero_capacity_count, total_duration, member_duration
  from desired_show_practice_sessions;

  if desired_session_count <> 39
     or zero_capacity_count <> 17
     or total_duration <> interval '21 hours'
     or member_duration <> interval '12 hours 25 minutes' then
    raise exception
      'Unexpected show-practice schedule: % sessions, % closed, % total, % member time',
      desired_session_count,
      zero_capacity_count,
      total_duration,
      member_duration;
  end if;
end;
$$;

delete from public.sessions as sessions
using affected_show_practice_dates as dates
where (sessions.start_time at time zone 'America/New_York')::date = dates.day
  and sessions.id like 'CUFSC-2026-%';

insert into public.sessions (id, notes, start_time, end_time, release_at, capacity)
select id, label, start_time, end_time, release_at, capacity
from desired_show_practice_sessions;

commit;
