\set ON_ERROR_STOP on
begin;
alter table public.booking_removal_notifications disable trigger booking_removal_notification;
insert into public.tiers(name,weekly_credits) values('basic',2) on conflict do nothing;
insert into public.users(id,email,name,tier,credits_balance,is_admin) values
('20000000-0000-0000-0000-000000000001','absence-admin@example.test','Admin','basic',2,true),
('20000000-0000-0000-0000-000000000002','absence-member@example.test','Member','basic',2,false),
('20000000-0000-0000-0000-000000000003','absence-present@example.test','Present','basic',2,false);
update private.no_show_rules set delay_minutes=8;
insert into public.sessions(id,start_time,end_time,release_at,capacity) values
('ABS-OPEN',now()-interval '8 minutes',now()+interval '27 minutes',now()-interval '1 day',10),
('ABS-EARLY',now()-interval '7 minutes 59 seconds',now()+interval '12 minutes',now()-interval '1 day',10),
('ABS-ENDED',now()-interval '40 minutes',now(),now()-interval '1 day',10);
insert into public.bookings(user_id,session_id,status,credit_charged,present)
select u.id,s.id,'active',u.name='Member',u.name='Present' from public.users u cross join public.sessions s
where u.id in('20000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000003') and s.id like 'ABS-%';
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.admin_remove_absent_bookings('ABS-OPEN',array[gen_random_uuid()]); raise exception 'Member removed a booking'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 if jsonb_array_length(public.my_infractions()->'strikes')<>0 then raise exception 'Unexpected own strikes'; end if;
end; $$;
reset role;
select set_config('request.jwt.claims','{"sub":"20000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare ids uuid[]; r jsonb; begin
 select array_agg(booking_id) into ids from public.admin_no_show_roster('ABS-EARLY') where not present;
 begin perform public.admin_remove_absent_bookings('ABS-EARLY',ids); raise exception 'Early removal accepted'; exception when others then if sqlerrm not like '%cutoff has not been reached%' then raise; end if; end;
 select array_agg(booking_id) into ids from public.admin_no_show_roster('ABS-OPEN');
 begin perform public.admin_remove_absent_bookings('ABS-OPEN',ids); raise exception 'Present skater removed'; exception when others then if sqlerrm not like '%marked present%' then raise; end if; end;
 if exists(select 1 from public.admin_no_show_roster('ABS-OPEN') where booking_status<>'active') then raise exception 'Batch did not roll back'; end if;
 select array_agg(booking_id) into ids from public.admin_no_show_roster('ABS-ENDED') where not present;
 begin perform public.admin_remove_absent_bookings('ABS-ENDED',ids); raise exception 'Ended removal accepted'; exception when others then if sqlerrm not like '%ended session%' then raise; end if; end;
 select array_agg(booking_id) into ids from public.admin_no_show_roster('ABS-OPEN') where not present;
 begin perform public.admin_remove_absent_bookings('ABS-ENDED',ids); raise exception 'Wrong session accepted'; exception when others then if sqlerrm not like '%does not belong%' then raise; end if; end;
 begin perform public.admin_report_no_shows('ABS-OPEN',ids); raise exception 'Legacy strike endpoint accepted'; exception when others then if sqlerrm not like '%strikes are disabled%' then raise; end if; end;
 begin perform public.admin_remove_absent_bookings('ABS-OPEN',array[]::uuid[]); raise exception 'Empty selection accepted'; exception when others then if sqlerrm not like '%distinct bookings%' then raise; end if; end;
 begin perform public.admin_remove_absent_bookings('ABS-OPEN',array[ids[1],ids[1]]); raise exception 'Duplicate selection accepted'; exception when others then if sqlerrm not like '%distinct bookings%' then raise; end if; end;
 r:=public.admin_remove_absent_bookings('ABS-OPEN',ids);
 if (r->>'removed')::int<>1 then raise exception 'Removal failed at exact cutoff'; end if;
 r:=public.admin_remove_absent_bookings('ABS-OPEN',ids);
 if (r->>'already_removed')::int<>1 then raise exception 'Retry failed'; end if;
 if not exists(select 1 from public.admin_no_show_roster('ABS-OPEN') where booking_status='cancelled') then raise exception 'Removed roster history missing'; end if;
 -- A genuinely absent free-booking member can be removed after attendance correction.
 select array_agg(booking_id) into ids from public.admin_no_show_roster('ABS-OPEN') where present;
 perform public.admin_set_attendance(ids[1],false);
 perform public.admin_remove_absent_bookings('ABS-OPEN',ids);
end; $$;
reset role;
do $$ begin
 if exists(select 1 from private.skating_infractions where user_id::text like '20000000-%') then raise exception 'Absence created a strike'; end if;
 if (select credits_balance from public.users where id='20000000-0000-0000-0000-000000000002')<>3 then raise exception 'Refund not exactly once'; end if;
 if (select count(*) from public.booking_removal_notifications where recipient_email='absence-member@example.test')<>1 then raise exception 'Email not queued exactly once'; end if;
 if (select credits_balance from public.users where id='20000000-0000-0000-0000-000000000003')<>2 then raise exception 'Free removal minted credit'; end if;
 if (select count(*) from private.absent_booking_removals where session_start=now()-interval '8 minutes')<>2 then raise exception 'Removal audit missing'; end if;
 if private.no_show_cutoff('2001-01-01 20:00Z','2001-01-01 20:20Z')<>'2001-01-01 20:08Z'::timestamptz or private.no_show_cutoff('2001-01-01 20:00Z','2001-01-01 21:00Z')<>'2001-01-01 20:08Z'::timestamptz then raise exception 'Session lengths differ'; end if;
 if has_function_privilege('anon','public.admin_remove_absent_bookings(text,uuid[])','execute') or has_table_privilege('authenticated','private.absent_booking_removals','select') then raise exception 'Removal permissions too broad'; end if;
end; $$;
rollback;
