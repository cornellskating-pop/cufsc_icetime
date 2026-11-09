\set ON_ERROR_STOP on
begin;
-- Synthetic records only. Disable delivery so approvals cannot send messages.
alter table public.approval_requests disable trigger "notify-admins-on-approval";
insert into public.tiers(name, weekly_credits) values ('basic', 2), ('temp', 0) on conflict do nothing;
insert into public.users(id,email,name,tier,credits_balance,is_admin) values
 ('10000000-0000-0000-0000-000000000001','attendance-admin@example.test','Attendance Admin','basic',2,true),
 ('10000000-0000-0000-0000-000000000002','attendance-member@example.test','Attendance Member','basic',2,false),
 ('10000000-0000-0000-0000-000000000003','attendance-temp@example.test','Attendance Temp','temp',0,false);
insert into public.sessions(id,start_time,end_time,release_at,capacity) values
 ('ATT-ONGOING',now()-interval '50 minutes',now()+interval '10 minutes',now()-interval '2 hours',10),
 ('ATT-ENDED',now()-interval '1 hour',now(),now()-interval '2 hours',10),
 ('ATT-FUTURE',now()+interval '2 hours',now()+interval '3 hours',now()-interval '2 hours',10);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ declare r jsonb; begin
  r := public.book_sessions(array['ATT-ONGOING']);
  if (r->0->>'ok')::boolean is not true then raise exception 'Ongoing session booking failed: %',r; end if;
  r := public.book_sessions(array['ATT-ENDED']);
  if (r->0->>'message') <> 'Session already ended' then raise exception 'Exact end must reject: %',r; end if;
  begin perform public.admin_submit_infractions(array['10000000-0000-0000-0000-000000000002'::uuid],current_date); raise exception 'Member submitted infractions';
  exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
  begin perform public.admin_search_skaters('Attendance',current_date); raise exception 'Member searched accounts';
  exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
  begin perform public.admin_list_infractions(current_date); raise exception 'Member read marks';
  exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
  begin perform public.admin_set_attendance(gen_random_uuid(),true); raise exception 'Member marked attendance';
  exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
end; $$;
reset role;
do $$ begin
  if (select credits_balance from public.users where email='attendance-member@example.test') <> 2 then raise exception 'Ongoing booking charged a credit'; end if;
end; $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select set_config('test.attendance_booking', (select id::text from public.bookings where session_id='ATT-ONGOING'), true);
set local role authenticated;
select public.admin_set_attendance(current_setting('test.attendance_booking')::uuid,true);
reset role;
select public.admin_set_attendance((select id from public.bookings where session_id='ATT-ONGOING'),true);
do $$ begin
  if not (select present from public.bookings where session_id='ATT-ONGOING') then raise exception 'Present was not persisted'; end if;
  if not exists(select 1 from public.admin_list_session_bookings_grouped() g, jsonb_array_elements(g.bookings) b where g.session_id='ATT-ONGOING' and (b->>'present')::boolean) then raise exception 'Roster omits attendance'; end if;
end; $$;
select public.admin_set_attendance((select id from public.bookings where session_id='ATT-ONGOING'),false);

insert into public.bookings(user_id,session_id,status,credit_charged)
values ('10000000-0000-0000-0000-000000000003','ATT-FUTURE','active',false);
do $$ begin
  begin perform public.admin_set_attendance((select id from public.bookings where session_id='ATT-FUTURE'),true); raise exception 'Future attendance accepted';
  exception when others then if sqlerrm not like '%after the session starts%' then raise; end if; end;
  begin perform public.admin_set_attendance(gen_random_uuid(),true); raise exception 'Missing booking attendance accepted';
  exception when others then if sqlerrm not like '%Active booking not found%' then raise; end if; end;
  if (select present from public.bookings where session_id='ATT-ONGOING') then raise exception 'Clearing present failed'; end if;
end; $$;
-- Batch creation, search, and date history are admin-only and coherent.
set local role authenticated;
select public.admin_submit_infractions(array['10000000-0000-0000-0000-000000000002'::uuid,'10000000-0000-0000-0000-000000000003'::uuid],date '2000-02-01');
do $$ begin
  if (select count(*) from public.admin_list_infractions(date '2000-02-01')) <> 2 then raise exception 'Batch history missing skaters'; end if;
  if (select count(*) from public.admin_search_skaters('Attendance',date '2000-02-01') where marked_on_date and marks=1) <> 2 then raise exception 'Search missing dated mark counts'; end if;
  if exists(select 1 from public.admin_search_skaters('A',date '2000-02-01')) then raise exception 'Unbounded short search'; end if;
end; $$;
reset role;
-- Every third mark, semester reset, breaks, multiple sessions per date,
-- cancelled/zero-capacity dates, exact end of fourth date, and DST.
insert into private.skating_infractions(user_id,marked_date,created_by)
select '10000000-0000-0000-0000-000000000002',d::date,'10000000-0000-0000-0000-000000000001'
from unnest(array['2001-07-28','2001-07-29','2001-08-01','2001-08-02']) d;
do $$ begin
  if (private.booking_restriction('10000000-0000-0000-0000-000000000002','2001-08-03 12:00-04')->>'blocked')::boolean then raise exception 'Marks crossed semester boundary'; end if;
end; $$;
insert into private.skating_infractions(user_id,marked_date) values ('10000000-0000-0000-0000-000000000002','2001-08-03');
insert into public.sessions(id,start_time,end_time,release_at,capacity,cancelled_at) values
 ('ATT-DAY1','2001-08-04 20:00-04','2001-08-04 21:00-04','2001-08-01',10,null),
 ('ATT-DAY1B','2001-08-04 21:00-04','2001-08-04 22:00-04','2001-08-01',10,null),
 ('ATT-PRACTICE','2001-08-05 20:00-04','2001-08-05 21:00-04','2001-08-01',0,null),
 ('ATT-CANCELLED','2001-08-06 20:00-04','2001-08-06 21:00-04','2001-08-01',0,now()),
 ('ATT-DAY2','2001-08-08 20:00-04','2001-08-08 21:00-04','2001-08-01',10,null),
 ('ATT-DAY3','2001-10-27 20:00-04','2001-10-27 21:00-04','2001-08-01',10,null),
 ('ATT-DAY4','2001-10-29 20:00-05','2001-10-29 21:00-05','2001-08-01',10,null);
do $$ declare r jsonb; begin
  r := private.booking_restriction('10000000-0000-0000-0000-000000000002','2001-08-07 12:00-04');
  if (r->>'remaining_days')::integer <> 3 then raise exception 'Multiple blocks/zero capacity/cancelled dates counted incorrectly: %',r; end if;
  if not (private.booking_restriction('10000000-0000-0000-0000-000000000002','2001-10-29 20:59:59-05')->>'blocked')::boolean then raise exception 'Restriction ended early'; end if;
  if (private.booking_restriction('10000000-0000-0000-0000-000000000002','2001-10-29 21:00-05')->>'blocked')::boolean then raise exception 'Restriction did not end exactly'; end if;
end; $$;

-- Actual submissions are atomic/idempotent and a third mark blocks all new
-- booking paths while keeping existing attendance/bookings/credits intact.
select public.admin_submit_infractions(array['10000000-0000-0000-0000-000000000002'::uuid],(now() at time zone 'America/New_York')::date-2);
select public.admin_submit_infractions(array['10000000-0000-0000-0000-000000000002'::uuid],(now() at time zone 'America/New_York')::date-1);
select public.admin_submit_infractions(array['10000000-0000-0000-0000-000000000002'::uuid],(now() at time zone 'America/New_York')::date);
do $$ declare r jsonb; begin
  r := public.admin_submit_infractions(array['10000000-0000-0000-0000-000000000002'::uuid],(now() at time zone 'America/New_York')::date);
  if (r->>'added')::integer <> 0 then raise exception 'Retry duplicated a mark'; end if;
  begin perform public.admin_submit_infractions(array['10000000-0000-0000-0000-000000000002'::uuid,'10000000-0000-0000-0000-999999999999'::uuid],(now() at time zone 'America/New_York')::date-3); raise exception 'Invalid batch succeeded';
  exception when others then if sqlerrm not like '%Skater account not found%' then raise; end if; end;
  if exists(select 1 from private.skating_infractions where marked_date=(now() at time zone 'America/New_York')::date-3) then raise exception 'Batch was not atomic'; end if;
end; $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
  if not (public.my_booking_restriction()->>'blocked')::boolean then raise exception 'Member restriction not visible'; end if;
  begin perform public.book_sessions(array['ATT-FUTURE']); raise exception 'Restricted member booked';
  exception when others then if sqlerrm not like '%Booking restricted%' then raise; end if; end;
end; $$;
reset role;
do $$ begin
  begin insert into public.bookings(user_id,session_id,status,credit_charged) values ('10000000-0000-0000-0000-000000000002','ATT-FUTURE','active',false); raise exception 'Trigger bypassed';
  exception when others then if sqlerrm not like '%Booking restricted%' then raise; end if; end;
end; $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
insert into public.approval_requests(id,type,user_id,session_id,status)
values ('ATT-BLOCKED-REQUEST','SESSION','10000000-0000-0000-0000-000000000002','ATT-FUTURE','OPEN');
set local role authenticated;
do $$ begin
  begin perform public.admin_approve_request('ATT-BLOCKED-REQUEST'); raise exception 'Approval bypassed restriction';
  exception when others then if sqlerrm not like '%Booking restricted%' then raise; end if; end;
  begin perform public.admin_submit_infractions(array['10000000-0000-0000-0000-000000000002'::uuid],(now() at time zone 'America/New_York')::date+1); raise exception 'Future infraction accepted';
  exception when others then if sqlerrm not like '%not in the future%' then raise; end if; end;
end; $$;
reset role;
select public.admin_void_infraction((select id from private.skating_infractions where user_id='10000000-0000-0000-0000-000000000002' and marked_date=(now() at time zone 'America/New_York')::date));
do $$ begin
  if (private.booking_restriction('10000000-0000-0000-0000-000000000002')->>'blocked')::boolean then raise exception 'Undo did not recalculate'; end if;
end; $$;
-- Temp requests can be submitted and approved while ice is ongoing.
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
set local role authenticated;
select public.book_sessions(array['ATT-ONGOING']);
reset role;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select public.admin_approve_request((select id from public.approval_requests where session_id='ATT-ONGOING' and user_id='10000000-0000-0000-0000-000000000003'));
do $$ begin
  if not exists(select 1 from public.bookings where session_id='ATT-ONGOING' and user_id='10000000-0000-0000-0000-000000000003' and not credit_charged) then raise exception 'Ongoing approval failed'; end if;
  if has_function_privilege('anon','public.admin_submit_infractions(uuid[],date)','execute')
     or has_function_privilege('authenticated','private.booking_restriction(uuid,timestamptz)','execute')
     or has_table_privilege('authenticated','private.skating_infractions','select') then raise exception 'Infraction access too broad'; end if;
end; $$;
-- Sixth mark starts another restriction; prior semesters can still have an
-- unexpired restriction even though the new semester's mark counter is zero.
insert into public.users(id,email,name,tier,credits_balance,is_admin) values
 ('10000000-0000-0000-0000-000000000004','attendance-boundary@example.test','Boundary','basic',2,false);
insert into private.skating_infractions(user_id,marked_date)
select '10000000-0000-0000-0000-000000000004',d::date from unnest(array['2001-07-28','2001-07-29','2001-07-30']) d;
do $$ declare r jsonb; begin
 r := private.booking_restriction('10000000-0000-0000-0000-000000000004','2001-08-01 12:00-04');
 if not (r->>'blocked')::boolean or (r->>'marks')::integer <> 0 then raise exception 'Restriction did not cross semester independently of mark count'; end if;
end; $$;
insert into private.skating_infractions(user_id,marked_date)
select '10000000-0000-0000-0000-000000000003',d::date from unnest(array['2001-08-01','2001-08-02','2001-08-03','2001-08-04','2001-08-05','2001-08-06']) d;
insert into public.sessions(id,start_time,end_time,release_at,capacity) values
 ('ATT-DAY5','2001-11-01 20:00-05','2001-11-01 21:00-05','2001-08-01',10);
do $$ begin
 if not (private.booking_restriction('10000000-0000-0000-0000-000000000003','2001-10-29 21:00-05')->>'blocked')::boolean then raise exception 'Sixth mark did not extend restriction'; end if;
 if (private.booking_restriction('10000000-0000-0000-0000-000000000003','2001-11-01 21:00-05')->>'blocked')::boolean then raise exception 'Sixth-mark restriction did not expire'; end if;
end; $$;
insert into private.skating_infractions(user_id,marked_date)
select '10000000-0000-0000-0000-000000000004',d::date from unnest(array['2099-08-01','2099-08-02','2099-08-03']) d;
do $$ declare r jsonb; begin
 r := private.booking_restriction('10000000-0000-0000-0000-000000000004','2099-08-04 12:00-04');
 if not (r->>'blocked')::boolean or r->>'ends_at' is not null or (r->>'remaining_days')::integer <> 4 then raise exception 'Incomplete schedule must remain restricted: %',r; end if;
end; $$;
rollback;
