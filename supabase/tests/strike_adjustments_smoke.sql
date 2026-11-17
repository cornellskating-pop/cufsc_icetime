\set ON_ERROR_STOP on
begin;
insert into public.tiers(name,weekly_credits) values('basic',2) on conflict do nothing;
insert into public.users(id,email,name,tier,credits_balance,is_admin) values
('40000000-0000-0000-0000-000000000001','strike-admin@example.test','Strike Admin','basic',2,true),
('40000000-0000-0000-0000-000000000002','strike-member@example.test','Strike Member','basic',2,false),
('40000000-0000-0000-0000-000000000003','strike-other@example.test','Strike Other','basic',2,false);
select set_config('request.jwt.claims','{"sub":"40000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$ begin
 begin perform public.admin_add_strike('40000000-0000-0000-0000-000000000002',current_date,'A synthetic explanation',gen_random_uuid()); raise exception 'Member added strike'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 begin perform public.admin_void_infraction(gen_random_uuid(),'A synthetic correction'); raise exception 'Member removed strike'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
 begin perform public.admin_user_infractions('40000000-0000-0000-0000-000000000001'); raise exception 'Member read admin history'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
end; $$;
reset role;
select set_config('request.jwt.claims','{"sub":"40000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$ declare v_id uuid; v_request uuid := gen_random_uuid(); v_day date := (now() at time zone 'America/New_York')::date; v_note text; r jsonb; begin
 foreach v_note in array array[null,'', '   ', E'\t\n\t\n', 'ab', repeat('x',1001)] loop
  begin perform public.admin_add_strike('40000000-0000-0000-0000-000000000002',v_day,v_note,gen_random_uuid()); raise exception 'Invalid note accepted'; exception when others then if sqlerrm not like '%Written justification%' then raise; end if; end;
 end loop;
 begin perform public.admin_add_strike('40000000-0000-0000-0000-000000000002',v_day+1,'Valid future note',gen_random_uuid()); raise exception 'Future date accepted'; exception when others then if sqlerrm not like '%not in the future%' then raise; end if; end;
 begin perform public.admin_add_strike(gen_random_uuid(),v_day,'Valid note',gen_random_uuid()); raise exception 'Missing user accepted'; exception when others then if sqlerrm not like '%User not found%' then raise; end if; end;
 begin perform public.admin_submit_infractions(array['40000000-0000-0000-0000-000000000002'::uuid],v_day); raise exception 'Legacy batch bypassed justification'; exception when others then if sqlerrm not like '%Written justification is required%' then raise; end if; end;
 v_id := public.admin_add_strike('40000000-0000-0000-0000-000000000002',v_day,'  Synthetic misconduct explanation  ',v_request);
 if public.admin_add_strike('40000000-0000-0000-0000-000000000002',v_day,'Synthetic misconduct explanation',v_request) <> v_id then raise exception 'Retry not idempotent'; end if;
 begin perform public.admin_add_strike('40000000-0000-0000-0000-000000000002',v_day,'Different explanation',v_request); raise exception 'Request reused for another adjustment'; exception when others then if sqlerrm not like '%different adjustment%' then raise; end if; end;
 begin perform public.admin_add_strike('40000000-0000-0000-0000-000000000002',v_day,'New request same date',gen_random_uuid()); raise exception 'Duplicate daily strike accepted'; exception when others then if sqlerrm not like '%already has an active strike%' then raise; end if; end;
 begin perform public.admin_void_infraction(v_id); raise exception 'Legacy undo bypassed justification'; exception when others then if sqlerrm not like '%Written justification is required%' then raise; end if; end;
 begin perform public.admin_void_infraction(v_id,'   '); raise exception 'Blank removal accepted'; exception when others then if sqlerrm not like '%Written justification%' then raise; end if; end;
 perform public.admin_add_strike('40000000-0000-0000-0000-000000000002',v_day-1,'Second synthetic incident',gen_random_uuid());
 perform public.admin_add_strike('40000000-0000-0000-0000-000000000002',v_day-2,'Third synthetic incident',gen_random_uuid());
 r := public.admin_user_infractions('40000000-0000-0000-0000-000000000002');
 if not (r->'restriction'->>'blocked')::boolean or jsonb_array_length(r->'strikes')<>3 then raise exception 'Manual strikes did not trigger existing penalty'; end if;
 if not exists(select 1 from jsonb_array_elements(r->'history') s where s->>'id'=v_id::text and s->>'justification'='Synthetic misconduct explanation' and s->>'created_by_name'='Strike Admin') then raise exception 'Profile grant explanation or actor missing'; end if;
 perform public.admin_void_infraction(v_id,'Synthetic correction after review');
 perform public.admin_void_infraction(v_id,'Repeated request must not rewrite original correction');
 if public.admin_add_strike('40000000-0000-0000-0000-000000000002',v_day,'Synthetic misconduct explanation',v_request)<>v_id then raise exception 'Retry after void changed original grant'; end if;
 r := public.admin_user_infractions('40000000-0000-0000-0000-000000000002');
 if (r->'restriction'->>'blocked')::boolean or jsonb_array_length(r->'strikes')<>2 or jsonb_array_length(r->'history')<>3 then raise exception 'Removal did not preserve history/recalculate'; end if;
 if not exists(select 1 from jsonb_array_elements(r->'history') s where s->>'id'=v_id::text and s->>'void_justification'='Synthetic correction after review' and s->>'justification'='Synthetic misconduct explanation' and s->>'voided_by_name'='Strike Admin') then raise exception 'Original/removal notes not retained'; end if;
 if not exists(select 1 from public.admin_list_infractions(v_day-1) where user_id='40000000-0000-0000-0000-000000000002' and justification='Second synthetic incident' and reason='manual') then raise exception 'Dated admin explanation missing'; end if;
 -- Batch awards also require a written reason and skip daily duplicates.
 r := public.admin_submit_infractions(array['40000000-0000-0000-0000-000000000003'::uuid],v_day,'Synthetic skating without signup observation');
 if (r->>'added')::int<>1 then raise exception 'Justified batch failed'; end if;
 r := public.admin_submit_infractions(array['40000000-0000-0000-0000-000000000003'::uuid],v_day,'Synthetic skating without signup observation');
 if (r->>'added')::int<>0 then raise exception 'Batch retry duplicated strike'; end if;
end; $$;
reset role;
do $$ begin
 if (select count(*) from private.strike_adjustments where user_id='40000000-0000-0000-0000-000000000002' and action='ADD')<>3 then raise exception 'Add audit count incorrect'; end if;
 if (select count(*) from private.strike_adjustments where user_id='40000000-0000-0000-0000-000000000002' and action='REMOVE')<>1 then raise exception 'Removal audit not exactly once'; end if;
 if not exists(select 1 from private.strike_adjustments where user_id='40000000-0000-0000-0000-000000000003' and reason='unregistered' and justification='Synthetic skating without signup observation' and actor_id='40000000-0000-0000-0000-000000000001') then raise exception 'Batch audit explanation missing'; end if;
 if exists(select 1 from public.users where id::text like '40000000-%' and credits_balance<>2) then raise exception 'Strike adjustment changed credits'; end if;
 if has_table_privilege('authenticated','private.strike_adjustments','select') or has_function_privilege('anon','public.admin_add_strike(uuid,date,text,uuid)','execute') then raise exception 'Audit/adjustment privileges too broad'; end if;
end; $$;
select set_config('request.jwt.claims','{"sub":"40000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
set local role authenticated;
do $$ declare r jsonb; begin
 r := public.my_infractions();
 if jsonb_array_length(r->'strikes')<>1 then raise exception 'Own-profile privacy changed'; end if;
 if r->'strikes'->0->>'justification' is distinct from 'Synthetic skating without signup observation' then raise exception 'Own recorded explanation missing'; end if;
 if (r->'strikes'->0) - array['id','marked_date','reason','justification'] <> '{}'::jsonb then raise exception 'Private correction/audit metadata exposed'; end if;
 begin perform public.admin_list_infractions((now() at time zone 'America/New_York')::date); raise exception 'Member read dated admin notes'; exception when others then if sqlerrm not like '%Not authorized%' then raise; end if; end;
end; $$;
reset role;
rollback;
