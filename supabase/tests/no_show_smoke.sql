\set ON_ERROR_STOP on
begin;
insert into public.tiers(name,weekly_credits) values ('basic',2) on conflict do nothing;
insert into public.users(id,email,name,tier,credits_balance,is_admin) values
 ('20000000-0000-0000-0000-000000000001','no-show-admin@example.test','No Show Admin','basic',2,true),
 ('20000000-0000-0000-0000-000000000002','no-show-member@example.test','No Show Member','basic',2,false),
 ('20000000-0000-0000-0000-000000000003','no-show-present@example.test','Present Member','basic',2,false),
 ('20000000-0000-0000-0000-000000000004','no-show-cancelled@example.test','Cancelled Member','basic',2,false),
 ('20000000-0000-0000-0000-000000000005','no-show-other@example.test','Other Member','basic',2,false),
 ('20000000-0000-0000-0000-000000000006','no-show-daily@example.test','Daily Member','basic',2,false);
insert into public.sessions(id,start_time,end_time,release_at,capacity,cancelled_at) values
 ('NS-SHORT',now()-interval '5 minutes',now()+interval '29 minutes',now()-interval '1 day',20,null),
 ('NS-35',now()-interval '8 minutes',now()+interval '27 minutes',now()-interval '1 day',20,null),
 ('NS-LONG',now()-interval '8 minutes',now()+interval '52 minutes',now()-interval '1 day',20,null),
 ('NS-SHORT-EARLY',now()-interval '4 minutes 59.999 seconds',now()+interval '29 minutes',now()-interval '1 day',20,null),
 ('NS-LONG-EARLY',now()-interval '7 minutes 59.999 seconds',now()+interval '52 minutes',now()-interval '1 day',20,null),
 ('NS-PAST',now()-interval '3 days',now()-interval '3 days'+interval '60 minutes',now()-interval '4 days',20,null),
 ('NS-CANCELLED',now()-interval '1 hour',now()+interval '1 hour',now()-interval '1 day',0,now()),
 ('NS-PRACTICE',now()-interval '1 hour',now()+interval '1 hour',now()-interval '1 day',0,null),
 ('NS-FUTURE',now()+interval '1 hour',now()+interval '2 hours',now()-interval '1 day',20,null);
insert into public.bookings(user_id,session_id,status,present,credit_charged)
select u.id,s.id,'active',u.email='no-show-present@example.test',false
from public.users u cross join public.sessions s
where u.id in ('20000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000005','20000000-0000-0000-0000-000000000006')
 and s.id like 'NS-%';
update public.bookings set status='cancelled' where user_id='20000000-0000-0000-0000-000000000004';
do $$ begin
 if private.no_show_cutoff('2001-01-01 20:00Z','2001-01-01 20:34:59Z') <> '2001-01-01 20:05Z'::timestamptz then raise exception 'Short threshold incorrect'; end if;
 if private.no_show_cutoff('2001-01-01 20:00Z','2001-01-01 20:35Z') <> '2001-01-01 20:08Z'::timestamptz then raise exception 'Exactly 35 minutes must use 8'; end if;
 if private.no_show_cutoff('2001-01-01 20:00Z','2001-01-01 21:00Z') <> '2001-01-01 20:08Z'::timestamptz then raise exception 'Long threshold incorrect'; end if;
 if exists(select 1 from private.skating_infractions where user_id::text like '20000000-%') then raise exception 'Unchecked attendance created automatic strikes'; end if;
end; $$;
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.admin_no_show_sessions(current_date); raise exception 'Member read sessions';
 exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 begin perform public.admin_no_show_roster('NS-SHORT'); raise exception 'Member read roster';
 exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 begin perform public.admin_report_no_shows('NS-SHORT',array[gen_random_uuid()]); raise exception 'Member submitted report';
 exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
end; $$;
reset role;
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare ids uuid[]; r jsonb; begin
 if exists(select 1 from public.admin_no_show_sessions((now() at time zone 'America/New_York')::date) where id in ('NS-FUTURE','NS-CANCELLED','NS-PRACTICE')) then raise exception 'Unavailable sessions listed'; end if;
 if not exists(select 1 from public.admin_no_show_sessions(((now()-interval '3 days') at time zone 'America/New_York')::date) where id='NS-PAST') then raise exception 'Past session missing'; end if;
 if (select count(*) from public.admin_no_show_roster('NS-SHORT')) <> 4 then raise exception 'Cancelled booking in roster'; end if;
 select array_agg(id) into ids from public.bookings where session_id='NS-SHORT-EARLY' and user_id='20000000-0000-0000-0000-000000000002';
 begin perform public.admin_report_no_shows('NS-SHORT-EARLY',ids); raise exception 'Early short report accepted';
 exception when others then if sqlerrm not like '%cutoff has not been reached%' then raise; end if; end;
 select array_agg(id) into ids from public.bookings where session_id='NS-LONG-EARLY' and user_id='20000000-0000-0000-0000-000000000002';
 begin perform public.admin_report_no_shows('NS-LONG-EARLY',ids); raise exception 'Early long report accepted';
 exception when others then if sqlerrm not like '%cutoff has not been reached%' then raise; end if; end;
 select array_agg(id) into ids from public.bookings where session_id='NS-SHORT' and user_id in ('20000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000005');
 begin perform public.admin_report_no_shows('NS-SHORT',ids); raise exception 'Present skater report accepted';
 exception when others then if sqlerrm not like '%marked present%' then raise; end if; end;
 select array_agg(id) into ids from public.bookings where session_id='NS-SHORT' and user_id='20000000-0000-0000-0000-000000000004';
 begin perform public.admin_report_no_shows('NS-SHORT',ids); raise exception 'Cancelled booking reported';
 exception when others then if sqlerrm not like '%cancelled their booking%' then raise; end if; end;
 select array_agg(id) into ids from public.bookings where session_id='NS-LONG' and user_id='20000000-0000-0000-0000-000000000002';
 begin perform public.admin_report_no_shows('NS-SHORT',ids); raise exception 'Wrong session accepted';
 exception when others then if sqlerrm not like '%does not belong%' then raise; end if; end;
 begin perform public.admin_report_no_shows('NS-SHORT',array[gen_random_uuid()]); raise exception 'Missing booking accepted';
 exception when others then if sqlerrm not like '%does not belong%' then raise; end if; end;
 select array_agg(id) into ids from public.bookings where session_id='NS-CANCELLED' and user_id='20000000-0000-0000-0000-000000000002';
 begin perform public.admin_report_no_shows('NS-CANCELLED',ids); raise exception 'Cancelled session reported';
 exception when others then if sqlerrm not like '%unavailable for reporting%' then raise; end if; end;
 select array_agg(id) into ids from public.bookings where session_id='NS-PRACTICE' and user_id='20000000-0000-0000-0000-000000000002';
 begin perform public.admin_report_no_shows('NS-PRACTICE',ids); raise exception 'Zero-capacity practice reported';
 exception when others then if sqlerrm not like '%unavailable for reporting%' then raise; end if; end;
 select array_agg(id) into ids from public.bookings where session_id='NS-SHORT' and user_id='20000000-0000-0000-0000-000000000002';
 begin perform public.admin_report_no_shows('NS-SHORT',ids || ids); raise exception 'Duplicate booking IDs accepted';
 exception when others then if sqlerrm not like '%distinct bookings%' then raise; end if; end;
 begin perform public.admin_report_no_shows('NS-SHORT',array[]::uuid[]); raise exception 'Empty report accepted';
 exception when others then if sqlerrm not like '%distinct bookings%' then raise; end if; end;
end; $$;
reset role;
do $$ begin
 if exists(select 1 from private.skating_infractions where user_id='20000000-0000-0000-0000-000000000005') then raise exception 'Failed batch partially wrote strikes'; end if;
end; $$;
-- Two previous dates plus the no-show share the existing third-strike penalty.
insert into private.skating_infractions(user_id,marked_date)
select '20000000-0000-0000-0000-000000000002',((now()-interval '5 minutes') at time zone 'America/New_York')::date-n from generate_series(1,2) n;
select public.admin_report_no_shows('NS-SHORT',array[(select id from public.bookings where session_id='NS-SHORT' and user_id='20000000-0000-0000-0000-000000000002')]);
do $$ declare r jsonb; begin
 r := public.admin_report_no_shows('NS-SHORT',array[(select id from public.bookings where session_id='NS-SHORT' and user_id='20000000-0000-0000-0000-000000000002')]);
 if (r->>'added')::integer <> 0 or (r->>'already_marked')::integer <> 1 then raise exception 'Retry duplicated a strike'; end if;
 if not (private.booking_restriction('20000000-0000-0000-0000-000000000002')->>'blocked')::boolean then raise exception 'No-show did not trigger third-strike restriction'; end if;
 if not exists(select 1 from private.skating_infractions where user_id='20000000-0000-0000-0000-000000000002' and reason='no_show' and booking_id is not null and session_start is not null and reportable_at=private.no_show_cutoff(session_start,session_end)) then raise exception 'Report audit snapshot missing'; end if;
end; $$;
select public.admin_void_infraction((select id from private.skating_infractions where user_id='20000000-0000-0000-0000-000000000002' and reason='no_show' and voided_at is null));
do $$ begin
 if (private.booking_restriction('20000000-0000-0000-0000-000000000002')->>'blocked')::boolean then raise exception 'Undo did not restore eligibility'; end if;
end; $$;
-- At exactly 8 minutes, both 35-minute and longer sessions can be reported.
set local role authenticated;
select public.admin_report_no_shows('NS-35',array[(select id from public.bookings where session_id='NS-35' and user_id='20000000-0000-0000-0000-000000000005')]);
select public.admin_report_no_shows('NS-LONG',array[(select id from public.bookings where session_id='NS-LONG' and user_id='20000000-0000-0000-0000-000000000006')]);
select public.admin_report_no_shows('NS-PAST',array[(select id from public.bookings where session_id='NS-PAST' and user_id='20000000-0000-0000-0000-000000000002')]);
reset role;
do $$ begin
 if not exists(select 1 from private.skating_infractions where user_id='20000000-0000-0000-0000-000000000002' and reason='no_show' and marked_date=((now()-interval '3 days') at time zone 'America/New_York')::date) then raise exception 'Past report used reporting date instead of session date'; end if;
 if not exists(select 1 from public.admin_no_show_roster('NS-35') where no_show_mark_id is not null and already_marked) then raise exception 'Recorded report not visible for undo'; end if;
end; $$;
-- A manual strike on the same date prevents a second daily strike.
select public.admin_submit_infractions(array['20000000-0000-0000-0000-000000000002'::uuid],((now()-interval '5 minutes') at time zone 'America/New_York')::date);
do $$ declare r jsonb; begin
 r := public.admin_report_no_shows('NS-SHORT',array[(select id from public.bookings where session_id='NS-SHORT' and user_id='20000000-0000-0000-0000-000000000002')]);
 if (r->>'added')::integer <> 0 then raise exception 'Different report types double-counted one date'; end if;
 if exists(select 1 from public.users where id::text like '20000000-%' and credits_balance<>2) then raise exception 'Reports changed credits'; end if;
 if exists(select 1 from public.bookings where session_id='NS-SHORT' and user_id='20000000-0000-0000-0000-000000000002' and status<>'active') then raise exception 'Report removed booking'; end if;
 if has_function_privilege('anon','public.admin_report_no_shows(text,uuid[])','execute') or has_function_privilege('authenticated','private.no_show_cutoff(timestamptz,timestamptz)','execute') then raise exception 'Permissions too broad'; end if;
end; $$;
rollback;
