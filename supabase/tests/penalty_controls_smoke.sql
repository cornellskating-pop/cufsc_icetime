\set ON_ERROR_STOP on
begin;
insert into public.tiers(name,weekly_credits) values ('basic',2) on conflict do nothing;
insert into public.users(id,email,name,tier,credits_balance,is_admin) values
 ('30000000-0000-0000-0000-000000000001','rules-admin@example.test','Rules Admin','basic',2,true),
 ('30000000-0000-0000-0000-000000000002','rules-member@example.test','Rules Member','basic',2,false);
insert into public.sessions(id,start_time,end_time,release_at,capacity) values
 ('RULES-SHORT',now()-interval '3 minutes',now()+interval '17 minutes',now()-interval '1 day',10),
 ('RULES-LONG',now()-interval '6 minutes',now()+interval '26 minutes',now()-interval '1 day',10);
insert into public.bookings(user_id,session_id,status,credit_charged) values
 ('30000000-0000-0000-0000-000000000002','RULES-SHORT','active',false),
 ('30000000-0000-0000-0000-000000000002','RULES-LONG','active',false);
select set_config('request.jwt.claims','{"sub":"30000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.admin_get_no_show_rules(); raise exception 'Member read settings'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 begin perform public.admin_set_no_show_rules(30,2,9,1); raise exception 'Member changed settings'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 begin perform public.admin_no_show_context(current_date); raise exception 'Member read context'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 begin perform public.admin_user_infractions('30000000-0000-0000-0000-000000000001'); raise exception 'Member read someone else strikes'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 begin perform public.admin_void_infraction(gen_random_uuid()); raise exception 'Member removed strike'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
end; $$;
reset role;
select set_config('request.jwt.claims','{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare v bigint; r jsonb; begin
 v := (public.admin_get_no_show_rules()->>'version')::bigint;
 r := public.admin_set_no_show_rules(30,2,9,v);
 if (r->>'version')::bigint <> v+1 then raise exception 'Settings version not advanced'; end if;
 if (r->>'long_delay_minutes')::integer <> 9 then raise exception 'Saved settings not returned'; end if;
 begin perform public.admin_set_no_show_rules(35,5,8,v); raise exception 'Stale overwrite accepted'; exception when others then if sqlerrm not like '%Another admin changed%' then raise; end if; end;
 begin perform public.admin_set_no_show_rules(0,2,9,v+1); raise exception 'Invalid boundary accepted'; exception when others then if sqlerrm not like '%1–240%' then raise; end if; end;
 begin perform public.admin_set_no_show_rules(30,-1,9,v+1); raise exception 'Negative delay accepted'; exception when others then if sqlerrm not like '%0–120%' then raise; end if; end;
 begin perform public.admin_set_no_show_rules(30,2,121,v+1); raise exception 'Excessive delay accepted'; exception when others then if sqlerrm not like '%0–120%' then raise; end if; end;
 begin perform public.admin_set_no_show_rules(30,null,9,v+1); raise exception 'Null delay accepted'; exception when others then if sqlerrm not like '%0–120%' then raise; end if; end;
 r := public.admin_no_show_context((now() at time zone 'America/New_York')::date);
 if (r->'rules'->>'duration_boundary_minutes')::integer <> 30 then raise exception 'Context rules stale'; end if;
 if not exists(select 1 from jsonb_array_elements(r->'sessions') s where s->>'id'='RULES-LONG' and (s->>'reportable_at')::timestamptz=now()+interval '3 minutes') then raise exception 'Context cutoff and description rules differ'; end if;
 begin perform public.admin_report_no_shows('RULES-LONG',array[(select id from public.bookings where session_id='RULES-LONG')]); raise exception 'Report ignored changed delay/boundary'; exception when others then if sqlerrm not like '%cutoff has not been reached%' then raise; end if; end;
end; $$;
reset role;
do $$ begin
 if not exists(select 1 from private.no_show_rule_changes where changed_by='30000000-0000-0000-0000-000000000001' and previous_rules->>'duration_boundary_minutes'='35' and new_rules->>'duration_boundary_minutes'='30') then raise exception 'Rule change audit missing'; end if;
 if private.no_show_cutoff('2001-01-01 20:00Z','2001-01-01 20:30Z') <> '2001-01-01 20:09Z'::timestamptz then raise exception 'Exact custom boundary must use long delay'; end if;
end; $$;
-- Profile includes both reasons and historical semesters; undo recalculates the
-- same underlying ledger rather than maintaining a separate counter.
insert into private.skating_infractions(user_id,marked_date) values ('30000000-0000-0000-0000-000000000002','2001-01-01');
insert into private.skating_infractions(user_id,marked_date)
select '30000000-0000-0000-0000-000000000002',((now()-interval '3 minutes') at time zone 'America/New_York')::date-n from generate_series(1,2) n;
set local role authenticated;
select public.admin_report_no_shows('RULES-SHORT',array[(select id from public.bookings where session_id='RULES-SHORT')]);
do $$ declare r jsonb; v_id uuid; begin
 r := public.admin_user_infractions('30000000-0000-0000-0000-000000000002');
 if jsonb_array_length(r->'strikes') <> 4 then raise exception 'Profile omits old/active strikes'; end if;
 if not (r->'restriction'->>'blocked')::boolean then raise exception 'Profile restriction missing'; end if;
 select (s->>'id')::uuid into v_id from jsonb_array_elements(r->'strikes') s where s->>'reason'='no_show';
 if v_id is null then raise exception 'Profile omitted no-show strike'; end if;
 perform public.admin_void_infraction(v_id);
 perform public.admin_void_infraction(v_id);
 r := public.admin_user_infractions('30000000-0000-0000-0000-000000000002');
 if jsonb_array_length(r->'strikes') <> 3 or (r->'restriction'->>'blocked')::boolean then raise exception 'Profile removal failed to recalculate'; end if;
 begin perform public.admin_user_infractions(gen_random_uuid()); raise exception 'Missing user accepted'; exception when others then if sqlerrm not like '%User not found%' then raise; end if; end;
end; $$;
reset role;
do $$ declare r jsonb; begin
 if not exists(select 1 from private.skating_infractions where user_id='30000000-0000-0000-0000-000000000002' and reason='no_show' and voided_at is not null and voided_by='30000000-0000-0000-0000-000000000001') then raise exception 'Removal audit missing'; end if;
 if (select credits_balance from public.users where id='30000000-0000-0000-0000-000000000002') <> 2 then raise exception 'Settings/removal changed credits'; end if;
 -- Boundary minimum and zero delay are valid; do not mutate old snapshots.
 r := public.admin_get_no_show_rules();
 perform public.admin_set_no_show_rules(1,0,0,(r->>'version')::bigint);
 if private.no_show_cutoff('2001-01-01 20:00Z','2001-01-01 20:35Z') <> '2001-01-01 20:00Z'::timestamptz then raise exception 'Zero delay ignored'; end if;
 if not exists(select 1 from private.skating_infractions where user_id='30000000-0000-0000-0000-000000000002' and reason='no_show' and reportable_at=session_start+interval '2 minutes') then raise exception 'Old cutoff snapshot changed'; end if;
 if has_function_privilege('anon','public.admin_get_no_show_rules()','execute') or has_function_privilege('anon','public.admin_user_infractions(uuid)','execute') or has_table_privilege('authenticated','private.no_show_rules','update') then raise exception 'Settings/profile permissions too broad'; end if;
end; $$;
rollback;
