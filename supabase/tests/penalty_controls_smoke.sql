\set ON_ERROR_STOP on
begin;
insert into public.tiers(name,weekly_credits) values('basic',2) on conflict do nothing;
insert into public.users(id,email,name,tier,credits_balance,is_admin) values
('30000000-0000-0000-0000-000000000001','rules-admin@example.test','Admin','basic',2,true),
('30000000-0000-0000-0000-000000000002','rules-member@example.test','Member','basic',2,false);
insert into public.sessions(id,start_time,end_time,release_at,capacity) values
('RULES-SESSION',now()-interval '6 minutes',now()+interval '26 minutes',now()-interval '1 day',10);
select set_config('request.jwt.claims','{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare v bigint; r jsonb; begin
 v:=(public.admin_get_no_show_rules()->>'version')::bigint;
 -- Force a change regardless of a previous local settings value.
 perform public.admin_set_no_show_rules(8,v);
 v:=(public.admin_get_no_show_rules()->>'version')::bigint;
 r:=public.admin_set_no_show_rules(9,v);
 if (r->>'version')::bigint<>v+1 or (r->>'delay_minutes')::int<>9 then raise exception 'Settings not versioned'; end if;
 begin perform public.admin_set_no_show_rules(8,v); raise exception 'Stale save accepted'; exception when others then if sqlerrm not like '%Another admin changed%' then raise; end if; end;
 begin perform public.admin_set_no_show_rules(-1,v+1); raise exception 'Negative delay accepted'; exception when others then if sqlerrm not like '%0 to 120%' then raise; end if; end;
 begin perform public.admin_set_no_show_rules(121,v+1); raise exception 'Excessive delay accepted'; exception when others then if sqlerrm not like '%0 to 120%' then raise; end if; end;
 begin perform public.admin_set_no_show_rules(null,v+1); raise exception 'Null delay accepted'; exception when others then if sqlerrm not like '%0 to 120%' then raise; end if; end;
 r:=public.admin_no_show_context((now() at time zone 'America/New_York')::date);
 if (r->'rules'->>'delay_minutes')::int<>9 or not exists(select 1 from jsonb_array_elements(r->'sessions') s where s->>'id'='RULES-SESSION' and (s->>'reportable_at')::timestamptz=now()+interval '3 minutes') then raise exception 'Context snapshot inconsistent'; end if;
 perform public.admin_set_no_show_rules(0,v+1);
end; $$;
reset role;
insert into private.skating_infractions(user_id,marked_date)
select '30000000-0000-0000-0000-000000000002',(now() at time zone 'America/New_York')::date-n from generate_series(0,2) n;
select set_config('request.jwt.claims','{"sub":"30000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ declare r jsonb; begin
 if (public.get_booking_policy()->>'delay_minutes')::int<>0 then raise exception 'Member policy incorrect'; end if;
 r:=public.my_infractions();
 if jsonb_array_length(r->'strikes')<>3 or not (r->'restriction'->>'blocked')::boolean then raise exception 'Own profile/restriction missing'; end if;
 begin perform public.admin_get_no_show_rules(); raise exception 'Member read private settings'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 begin perform public.admin_set_no_show_rules(8,1); raise exception 'Member changed settings'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 begin perform public.admin_user_infractions('30000000-0000-0000-0000-000000000001'); raise exception 'Member read others strikes'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
end; $$;
reset role;
select set_config('request.jwt.claims','{"sub":"30000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare r jsonb; v_id uuid; begin
 r:=public.admin_user_infractions('30000000-0000-0000-0000-000000000002');
 v_id:=(r->'strikes'->0->>'id')::uuid;
 perform public.admin_void_infraction(v_id, 'Synthetic test justification');
 perform public.admin_void_infraction(v_id, 'Synthetic test justification');
 r:=public.admin_user_infractions('30000000-0000-0000-0000-000000000002');
 if jsonb_array_length(r->'strikes')<>2 or (r->'restriction'->>'blocked')::boolean then raise exception 'Undo did not recalculate'; end if;
end; $$;
reset role;
do $$ begin
 if not exists(select 1 from private.no_show_rule_changes where changed_by='30000000-0000-0000-0000-000000000001' and previous_rules->>'delay_minutes'='8' and new_rules->>'delay_minutes'='9') then raise exception 'Settings audit missing'; end if;
 if not exists(select 1 from private.skating_infractions where user_id='30000000-0000-0000-0000-000000000002' and voided_at is not null and voided_by='30000000-0000-0000-0000-000000000001') then raise exception 'Undo audit missing'; end if;
 if has_function_privilege('anon','public.my_infractions()','execute') or has_function_privilege('anon','public.get_booking_policy()','execute') then raise exception 'Anonymous profile access'; end if;
end; $$;
rollback;
