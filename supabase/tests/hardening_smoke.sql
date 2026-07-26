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

rollback;
