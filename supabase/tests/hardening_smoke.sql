\set ON_ERROR_STOP on

begin;

insert into public.tiers (name, weekly_credits)
values ('basic', 2), ('temp', 0)
on conflict (name) do update
set weekly_credits = excluded.weekly_credits;

insert into public.users (
  id, email, name, tier, credits_balance, is_admin, paid_dues
)
values
  ('00000000-0000-0000-0000-000000000001', 'admin@example.test', 'Admin', 'basic', 2, true, true),
  ('00000000-0000-0000-0000-000000000002', 'member@example.test', 'Member', 'basic', 2, false, true),
  ('00000000-0000-0000-0000-000000000003', 'temp@example.test', 'Temp', 'temp', 0, false, false);

insert into public.sessions (
  id, start_time, end_time, release_at, capacity, notes
)
values
  ('TEST-NORMAL', now() + interval '2 hours', now() + interval '3 hours', now() - interval '1 hour', 1, 'Normal'),
  ('TEST-GRACE', now() + interval '45 minutes', now() + interval '90 minutes', now() - interval '1 hour', 5, 'Grace'),
  ('TEST-TEMP', now() + interval '2 hours', now() + interval '3 hours', now() - interval '1 hour', 5, 'Temp approval'),
  ('TEST-LOCKED', now() + interval '3 hours', now() + interval '4 hours', now() + interval '1 hour', 5, 'Not released');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000002","email":"member@example.test","role":"authenticated"}',
  true
);

do $$
begin
  begin
    perform public.book_sessions(array['TEST-NORMAL', 'TEST-GRACE', 'TEST-LOCKED']);
    raise exception 'Expected the two-session server limit to reject three sessions';
  exception
    when others then
      if sqlerrm not like '%at most two%' then
        raise;
      end if;
  end;
end;
$$;

select public.book_sessions(array['TEST-NORMAL', 'TEST-GRACE']);

do $$
begin
  if (select credits_balance from public.users where email = 'member@example.test') <> 1 then
    raise exception 'Exactly one credit should have been charged';
  end if;
  if (select credit_charged from public.bookings where session_id = 'TEST-NORMAL') is not true then
    raise exception 'Normal booking should record a charged credit';
  end if;
  if (select credit_charged from public.bookings where session_id = 'TEST-GRACE') is not false then
    raise exception 'Grace booking should record no charged credit';
  end if;
end;
$$;

select public.cancel_booking(
  (select id from public.bookings where session_id = 'TEST-GRACE')
);

do $$
begin
  if (select credits_balance from public.users where email = 'member@example.test') <> 1 then
    raise exception 'Cancelling a free grace booking must not create a credit';
  end if;
end;
$$;

do $$
declare
  result jsonb;
begin
  result := public.book_sessions(array['TEST-LOCKED']);
  if result #>> '{0,message}' <> 'Session is not open yet' then
    raise exception 'Release time must be enforced by the RPC';
  end if;
end;
$$;

do $$
begin
  begin
    perform public.admin_list_users();
    raise exception 'Non-admin unexpectedly called admin_list_users';
  exception
    when others then
      if sqlerrm not like '%Not authorized%' then
        raise;
      end if;
  end;
  begin
    perform public.admin_reset_non_admin_accounts_to_temp();
    raise exception 'Non-admin unexpectedly reset member accounts';
  exception
    when others then
      if sqlerrm not like '%Not authorized%' then
        raise;
      end if;
  end;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000003","email":"temp@example.test","role":"authenticated"}',
  true
);
select public.book_sessions(array['TEST-TEMP']);

do $$
begin
  if not exists (
    select 1
    from public.approval_requests
    where user_id = '00000000-0000-0000-0000-000000000003'
      and session_id = 'TEST-TEMP'
      and type = 'SESSION'
      and status = 'OPEN'
  ) then
    raise exception 'A zero-credit temp booking should create an approval request';
  end if;
  if exists (
    select 1
    from public.bookings
    where user_id = '00000000-0000-0000-0000-000000000003'
      and session_id = 'TEST-TEMP'
  ) then
    raise exception 'A temp request must not create a booking before approval';
  end if;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000001","email":"admin@example.test","role":"authenticated"}',
  true
);

select public.admin_approve_request(
  (
    select id
    from public.approval_requests
    where user_id = '00000000-0000-0000-0000-000000000003'
      and session_id = 'TEST-TEMP'
      and status = 'OPEN'
  )
);

do $$
begin
  if (
    select credit_charged
    from public.bookings
    where user_id = '00000000-0000-0000-0000-000000000003'
      and session_id = 'TEST-TEMP'
      and status = 'active'
  ) is not false then
    raise exception 'Admin-approved temp booking must not charge a credit';
  end if;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000003","email":"temp@example.test","role":"authenticated"}',
  true
);
select public.cancel_booking(
  (
    select id
    from public.bookings
    where user_id = '00000000-0000-0000-0000-000000000003'
      and session_id = 'TEST-TEMP'
      and status = 'active'
  )
);

do $$
begin
  if (select credits_balance from public.users where email = 'temp@example.test') <> 0 then
    raise exception 'Cancelling an approved temp booking must not create a credit';
  end if;
end;
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-0000-0000-000000000001","email":"admin@example.test","role":"authenticated"}',
  true
);

do $$
begin
  if (select count(*) from public.admin_list_users()) <> 3 then
    raise exception 'Admin list RPC did not return the test users';
  end if;
  if has_function_privilege('anon', 'public.book_sessions(text[])', 'execute') then
    raise exception 'Anon must not be able to execute booking functions';
  end if;
  if has_function_privilege('anon', 'public.admin_list_session_bookings_grouped()', 'execute') then
    raise exception 'Anon must not be able to execute admin booking functions';
  end if;
  if has_table_privilege('anon', 'public.users', 'select') then
    raise exception 'Anon must not be able to select member profiles';
  end if;
  if has_table_privilege('authenticated', 'public.users', 'update') then
    raise exception 'Members must not have direct profile update privileges';
  end if;
end;
$$;

select public.admin_reset_non_admin_accounts_to_temp();

do $$
begin
  if exists (
    select 1
    from public.users
    where is_admin = false
      and (tier <> 'temp' or credits_balance <> 0)
  ) then
    raise exception 'The semester reset must convert every non-admin account to zero-credit temp';
  end if;
  if not exists (
    select 1
    from public.users
    where email = 'admin@example.test'
      and is_admin = true
      and tier = 'basic'
      and credits_balance = 2
  ) then
    raise exception 'The semester reset must leave admin accounts unchanged';
  end if;
  if has_function_privilege(
    'anon',
    'public.admin_reset_non_admin_accounts_to_temp()',
    'execute'
  ) then
    raise exception 'Anon must not be able to execute the semester account reset';
  end if;
end;
$$;

-- Member attendance: names only, active bookings, deterministic signup order.
insert into public.sessions (id, start_time, end_time, capacity, notes)
values ('TEST-ATTENDANCE', now() + interval '5 hours', now() + interval '6 hours', 30, 'Attendance'),
       ('TEST-PAST', now() - interval '2 hours', now() - interval '1 hour', 5, 'Past');
insert into public.bookings (id, session_id, user_id, created_at, status, credit_charged)
values
  ('10000000-0000-0000-0000-000000000002', 'TEST-ATTENDANCE', '00000000-0000-0000-0000-000000000002', now(), 'active', false),
  ('10000000-0000-0000-0000-000000000001', 'TEST-ATTENDANCE', '00000000-0000-0000-0000-000000000001', now(), 'active', false),
  ('10000000-0000-0000-0000-000000000003', 'TEST-ATTENDANCE', '00000000-0000-0000-0000-000000000003', now() - interval '1 hour', 'cancelled', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  if (select names from public.list_upcoming_session_attendees() where session_id = 'TEST-ATTENDANCE')
      is distinct from array['Admin', 'Member']::text[] then
    raise exception 'Attendance must return active names in stable signup order';
  end if;
  if exists (select 1 from public.list_upcoming_session_attendees() where session_id = 'TEST-PAST') then
    raise exception 'Past sessions must not be exposed';
  end if;
  if (select names from public.list_upcoming_session_attendees() where session_id = 'TEST-LOCKED')
      is distinct from array[]::text[] then
    raise exception 'Empty upcoming sessions must be included';
  end if;
  if has_function_privilege('anon', 'public.list_upcoming_session_attendees()', 'execute') then
    raise exception 'Anonymous attendance access must be denied';
  end if;
  begin
    perform public.admin_list_session_bookings_grouped();
    raise exception 'Member unexpectedly accessed admin attendance';
  exception when others then
    if sqlerrm not like '%Not authorized%' then raise; end if;
  end;
end;
$$;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000099","role":"authenticated"}', true);
do $$
begin
  begin
    perform public.list_upcoming_session_attendees();
    raise exception 'Non-member unexpectedly accessed attendance';
  exception when others then
    if sqlerrm not like '%Not authorized%' then raise; end if;
  end;
end;
$$;
reset role;

-- Admin removal and contingency authorization under the actual browser role.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$
begin
  begin
    perform public.admin_one_credit_contingency();
    raise exception 'Member unexpectedly reset credits';
  exception when others then
    if sqlerrm not like '%Not authorized%' then raise; end if;
  end;
  begin
    perform public.admin_remove_booking('10000000-0000-0000-0000-000000000002');
    raise exception 'Member unexpectedly removed a booking';
  exception when others then
    if sqlerrm not like '%Not authorized%' then raise; end if;
  end;
  if has_table_privilege('authenticated', 'public.booking_removal_notifications', 'select') then
    raise exception 'Browser must not read notification records';
  end if;
  if has_function_privilege('anon', 'public.admin_one_credit_contingency()', 'execute')
     or has_function_privilege('anon', 'public.admin_remove_booking(uuid)', 'execute') then
    raise exception 'Anonymous admin RPC access';
  end if;
end;
$$;
reset role;
update public.users set tier = 'basic', credits_balance = 4 where id = '00000000-0000-0000-0000-000000000002';
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select public.admin_one_credit_contingency();
reset role;
do $$
begin
  if exists (select 1 from public.users where credits_balance <> case when lower(tier) = 'temp' then 0 else 1 end) then
    raise exception 'Contingency balances incorrect';
  end if;
  if (select count(*) from public.credit_audit where action = 'CONTINGENCY_RESET') <> 3 then
    raise exception 'Contingency must be audited for every account';
  end if;
  if (select tier from public.users where id = '00000000-0000-0000-0000-000000000002') <> 'basic' then
    raise exception 'Contingency changed a tier';
  end if;
end;
$$;
select public.admin_remove_booking((select id from public.bookings where session_id = 'TEST-NORMAL'));
select public.admin_remove_booking((select id from public.bookings where session_id = 'TEST-NORMAL'));
select public.admin_remove_booking('10000000-0000-0000-0000-000000000002');
do $$
begin
  if (select credits_balance from public.users where id = '00000000-0000-0000-0000-000000000002') <> 2 then
    raise exception 'Charged booking should refund exactly once and free booking never refund';
  end if;
  if (select count(*) from public.booking_removal_notifications) <> 2 then
    raise exception 'One removal notification required per removed booking';
  end if;
  if (select count(*) from public.booking_removal_notifications where refunded) <> 1 then
    raise exception 'Notification refund details incorrect';
  end if;
  if exists (select 1 from public.bookings where session_id = 'TEST-NORMAL' and status = 'active') then
    raise exception 'Removed booking still occupies a spot';
  end if;
end;
$$;
select public.admin_weekly_reset_credits();
do $$
begin
  if exists (select 1 from public.users u join public.tiers t on lower(t.name) = lower(u.tier)
    where u.credits_balance <> t.weekly_credits) then
    raise exception 'Normal tier resets must resume after contingency';
  end if;
end;
$$;

-- Entire-session cancellation keeps history, closes booking, refunds once.
insert into public.sessions (id, start_time, end_time, capacity)
values ('TEST-CANCEL-SESSION', now() + interval '4 hours', now() + interval '5 hours', 10);
insert into public.bookings (id, session_id, user_id, credit_charged) values
('20000000-0000-0000-0000-000000000001', 'TEST-CANCEL-SESSION', '00000000-0000-0000-0000-000000000001', true),
('20000000-0000-0000-0000-000000000002', 'TEST-CANCEL-SESSION', '00000000-0000-0000-0000-000000000002', false);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
do $$ begin
  begin
    perform public.admin_cancel_session('TEST-CANCEL-SESSION');
    raise exception 'Non-admin cancelled session';
  exception when others then
    if sqlerrm not like '%Not authorized%' then raise; end if;
  end;
end; $$;
reset role;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select public.admin_cancel_session('TEST-CANCEL-SESSION');
select public.admin_cancel_session('TEST-CANCEL-SESSION');
do $$ begin
  if not exists (select 1 from public.sessions where id = 'TEST-CANCEL-SESSION' and capacity = 0 and cancelled_at is not null) then
    raise exception 'Cancelled session must remain closed in history';
  end if;
  if exists (select 1 from public.bookings where session_id = 'TEST-CANCEL-SESSION' and status = 'active') then
    raise exception 'Cancelled session retains active bookings';
  end if;
  if (select count(*) from public.booking_removal_notifications where reason = 'session_cancelled') <> 2 then
    raise exception 'Expected one notification per active member';
  end if;
  if (select credits_balance from public.users where id = '00000000-0000-0000-0000-000000000001') <> 3
    or (select credits_balance from public.users where id = '00000000-0000-0000-0000-000000000002') <> 2 then
    raise exception 'Incorrect or repeated session cancellation refund';
  end if;
  if public.book_sessions(array['TEST-CANCEL-SESSION']) #>> '{0,ok}' <> 'false' then
    raise exception 'Cancelled session accepted a booking';
  end if;
  begin
    update public.sessions set capacity = 10 where id = 'TEST-CANCEL-SESSION';
    raise exception 'Cancelled session reopened';
  exception when others then
    if sqlerrm not like '%cannot be edited%' then raise; end if;
  end;
  if has_function_privilege('anon', 'public.admin_cancel_session(text)', 'execute') then
    raise exception 'Anonymous session cancellation access';
  end if;
end; $$;

rollback;
