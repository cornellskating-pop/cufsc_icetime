-- Read-only checks to run against the linked production database before
-- applying 20260726103000_harden_and_consolidate_booking_system.sql.

select 'case-insensitive duplicate user emails' as check_name, count(*) as issue_count
from (
  select lower(email)
  from public.users
  group by lower(email)
  having count(*) > 1
) duplicates;

select 'invalid session time order' as check_name, count(*) as issue_count
from public.sessions
where end_time <= start_time;

select 'release at/after session start' as check_name, count(*) as issue_count
from public.sessions
where release_at is not null
  and release_at >= start_time;

select 'unrecognized paid_dues values' as check_name, count(*) as issue_count
from public.users
where paid_dues is not null
  and lower(trim(paid_dues)) not in (
    'true', 't', '1', 'yes', 'y', 'paid',
    'false', 'f', '0', 'no', 'n', 'unpaid'
  );

select 'sessions over capacity' as check_name, count(*) as issue_count
from (
  select s.id
  from public.sessions s
  left join public.bookings b
    on b.session_id = s.id
   and b.status = 'active'
  group by s.id, s.capacity
  having count(b.id) > s.capacity
) over_capacity;

select 'duplicate open session approvals' as check_name, count(*) as issue_count
from (
  select user_id, session_id
  from public.approval_requests
  where type = 'SESSION'
    and status = 'OPEN'
  group by user_id, session_id
  having count(*) > 1
) duplicates;

select 'duplicate open new-user approvals' as check_name, count(*) as issue_count
from (
  select lower(requester_email)
  from public.approval_requests
  where type = 'NEW_USER'
    and status = 'OPEN'
  group by lower(requester_email)
  having count(*) > 1
) duplicates;

select
  tier,
  count(*) as member_count
from public.users
group by tier
order by tier;

select
  jobid,
  jobname,
  schedule,
  command,
  username,
  active
from cron.job
order by jobid;

select
  event_object_schema,
  event_object_table,
  trigger_name,
  action_statement
from information_schema.triggers
where event_object_schema = 'auth'
   or trigger_name = 'notify-admins-on-approval'
order by event_object_schema, event_object_table, trigger_name;
