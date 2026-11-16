begin;

-- Retain historical policy/strike snapshots. Only future absence actions change.
drop function public.admin_set_no_show_rules(integer, integer, integer, bigint);
alter table private.no_show_rules add column delay_minutes integer not null default 8 check (delay_minutes between 0 and 120);
insert into private.no_show_rule_changes(changed_by, previous_rules, new_rules)
select null, to_jsonb(r) - 'delay_minutes', jsonb_build_object('delay_minutes',8,'version',r.version+1)
from private.no_show_rules r;
alter table private.no_show_rules drop column duration_boundary_minutes, drop column short_delay_minutes, drop column long_delay_minutes;
update private.no_show_rules set version=version+1, updated_at=now();

create function public.admin_set_no_show_rules(p_delay_minutes integer, p_expected_version bigint)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_before private.no_show_rules%rowtype; v_after private.no_show_rules%rowtype;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if p_delay_minutes is null or p_delay_minutes not between 0 and 120 then raise exception 'Use a whole number of minutes from 0 to 120'; end if;
  select * into v_before from private.no_show_rules where singleton for update;
  if not found then raise exception 'Absence timing rules are unavailable'; end if;
  if p_expected_version is null or p_expected_version <> v_before.version then raise exception 'Another admin changed these rules. Reload saved rules before saving'; end if;
  if p_delay_minutes = v_before.delay_minutes then return public.admin_get_no_show_rules(); end if;
  update private.no_show_rules set delay_minutes=p_delay_minutes,version=version+1,updated_at=now(),updated_by=auth.uid()
    where singleton returning * into v_after;
  insert into private.no_show_rule_changes(changed_by,previous_rules,new_rules) values(auth.uid(),to_jsonb(v_before),to_jsonb(v_after));
  return to_jsonb(v_after)-'singleton'-'updated_by';
end; $$;
revoke all on function public.admin_set_no_show_rules(integer,bigint) from public,anon;
grant execute on function public.admin_set_no_show_rules(integer,bigint) to authenticated;

create or replace function private.no_show_cutoff(p_start timestamptz,p_end timestamptz)
returns timestamptz language sql stable set search_path=public,pg_temp as $$
  select p_start+make_interval(mins=>r.delay_minutes) from private.no_show_rules r where singleton;
$$;

create function public.get_booking_policy()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null or not exists(select 1 from public.users where id=auth.uid()) then raise exception 'Not authorized'; end if;
  return (select jsonb_build_object('delay_minutes',delay_minutes) from private.no_show_rules where singleton);
end; $$;
revoke all on function public.get_booking_policy() from public,anon;
grant execute on function public.get_booking_policy() to authenticated;

create function public.my_infractions()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null or not exists(select 1 from public.users where id=auth.uid()) then raise exception 'Not authorized'; end if;
  return jsonb_build_object('restriction',private.booking_restriction(auth.uid()),'strikes',
    (select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'marked_date',i.marked_date,'reason',i.reason)
      order by i.marked_date desc,i.id),'[]'::jsonb)
     from private.skating_infractions i where user_id=auth.uid() and voided_at is null));
end; $$;
revoke all on function public.my_infractions() from public,anon;
grant execute on function public.my_infractions() to authenticated;

-- Stale clients cannot create absence strikes using the old endpoint.
create or replace function public.admin_report_no_shows(p_session_id text,p_booking_ids uuid[])
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  raise exception 'Absence strikes are disabled. Reload and use Remove selected bookings instead';
end; $$;

create table private.absent_booking_removals (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid unique references public.bookings(id) on delete set null,
  removed_by uuid references public.users(id) on update cascade on delete set null,
  removed_at timestamptz not null default now(),
  session_start timestamptz not null,
  session_end timestamptz not null,
  removable_at timestamptz not null,
  policy_version bigint not null
);
alter table private.absent_booking_removals enable row level security;
revoke all on private.absent_booking_removals from public,anon,authenticated;

create or replace function public.admin_no_show_roster(p_session_id text)
returns table(booking_id uuid,name text,email text,present boolean,booking_status text,already_marked boolean,no_show_mark_id uuid)
language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if not exists(select 1 from public.sessions where id=p_session_id and cancelled_at is null and capacity>0 and start_time<=now()) then
    raise exception 'Choose an ongoing or past bookable session'; end if;
  return query select b.id,u.name,u.email,b.present,b.status,false,null::uuid
    from public.bookings b join public.users u on u.id=b.user_id
    where b.session_id=p_session_id and (b.status='active' or exists(select 1 from private.absent_booking_removals r where r.booking_id=b.id))
    order by b.created_at,b.id;
end; $$;

create function public.admin_remove_absent_bookings(p_session_id text,p_booking_ids uuid[])
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_session public.sessions%rowtype; v_booking public.bookings%rowtype;
  v_rules private.no_show_rules%rowtype; v_cutoff timestamptz; v_removed integer:=0; v_existing integer:=0;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if p_booking_ids is null or cardinality(p_booking_ids) not between 1 and 100
    or exists(select 1 from unnest(p_booking_ids) x where x is null)
    or (select count(distinct x) from unnest(p_booking_ids) x)<>cardinality(p_booking_ids) then
    raise exception 'Choose 1 to 100 distinct bookings'; end if;
  select * into v_rules from private.no_show_rules where singleton for share;
  if not found then raise exception 'Absence timing rules are unavailable'; end if;
  perform u.id from public.users u where u.id in(select b.user_id from public.bookings b where b.id=any(p_booking_ids)) order by u.id for update;
  select * into v_session from public.sessions where id=p_session_id for update nowait;
  if not found or v_session.cancelled_at is not null or v_session.capacity<=0 then raise exception 'Session is unavailable for removal'; end if;
  v_cutoff:=v_session.start_time+make_interval(mins=>v_rules.delay_minutes);
  if now()<v_cutoff then raise exception 'The absence removal cutoff has not been reached'; end if;
  perform b.id from public.bookings b where b.id=any(p_booking_ids) order by b.id for update nowait;
  if (select count(*) from public.bookings where id=any(p_booking_ids) and session_id=p_session_id)<>cardinality(p_booking_ids) then
    raise exception 'A selected booking does not belong to this session'; end if;
  for v_booking in select * from public.bookings where id=any(p_booking_ids) order by id loop
    if v_booking.status='cancelled' and exists(select 1 from private.absent_booking_removals where booking_id=v_booking.id) then
      v_existing:=v_existing+1; continue; end if;
    if now()>=v_session.end_time then raise exception 'Cannot remove a booking from an ended session'; end if;
    if v_booking.status<>'active' then raise exception 'A selected skater has cancelled their booking; refresh the roster'; end if;
    if v_booking.present then raise exception 'A selected skater is marked present; refresh the roster'; end if;
    -- Reuse the transactional refund and durable, idempotent email queue.
    perform public.admin_remove_booking(v_booking.id);
    insert into private.absent_booking_removals(booking_id,removed_by,session_start,session_end,removable_at,policy_version)
      values(v_booking.id,auth.uid(),v_session.start_time,v_session.end_time,v_cutoff,v_rules.version);
    v_removed:=v_removed+1;
  end loop;
  return jsonb_build_object('removed',v_removed,'already_removed',v_existing);
exception when lock_not_available then raise exception 'Attendance or bookings are being updated. Refresh and retry the entire removal';
end; $$;
revoke all on function public.admin_remove_absent_bookings(text,uuid[]) from public,anon;
grant execute on function public.admin_remove_absent_bookings(text,uuid[]) to authenticated;

commit;
