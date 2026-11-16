begin;

alter table private.skating_infractions
  add column justification text check (justification is null or char_length(regexp_replace(justification, '^[[:space:]]+|[[:space:]]+$', '', 'g')) between 3 and 1000),
  add column void_justification text check (void_justification is null or char_length(regexp_replace(void_justification, '^[[:space:]]+|[[:space:]]+$', '', 'g')) between 3 and 1000),
  drop constraint skating_infractions_reason_check;
alter table private.skating_infractions add constraint skating_infractions_reason_check
  check (reason in ('unregistered', 'no_show', 'manual'));

-- Originals remain in skating_infractions; this append-only application log
-- records each new award/removal and supplies request idempotency for manual adds.
create table private.strike_adjustments (
  id uuid primary key,
  user_id uuid references public.users(id) on update cascade on delete set null,
  strike_id uuid references private.skating_infractions(id) on delete set null,
  action text not null check (action in ('ADD', 'REMOVE')),
  justification text not null check (char_length(regexp_replace(justification, '^[[:space:]]+|[[:space:]]+$', '', 'g')) between 3 and 1000),
  marked_date date not null,
  reason text not null,
  actor_id uuid references public.users(id) on update cascade on delete set null,
  occurred_at timestamptz not null default now()
);
create index strike_adjustments_user on private.strike_adjustments(user_id, occurred_at);
alter table private.strike_adjustments enable row level security;
revoke all on private.strike_adjustments from public, anon, authenticated;

create function public.admin_add_strike(p_user_id uuid, p_date date, p_justification text, p_request_id uuid)
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid; v_existing private.strike_adjustments%rowtype; v_note text := regexp_replace(p_justification, '^[[:space:]]+|[[:space:]]+$', '', 'g');
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if v_note is null or char_length(v_note) not between 3 and 1000 then raise exception 'Written justification must be 3–1000 characters'; end if;
  if p_date is null or p_date > (now() at time zone 'America/New_York')::date then raise exception 'Enter a valid strike date that is not in the future'; end if;
  if p_request_id is null then raise exception 'Request ID is required'; end if;
  perform id from public.users where id = p_user_id for update;
  if not found then raise exception 'User not found'; end if;
  select * into v_existing from private.strike_adjustments where id = p_request_id;
  if found then
    if v_existing.user_id is distinct from p_user_id or v_existing.action <> 'ADD'
      or v_existing.actor_id is distinct from auth.uid() or v_existing.marked_date <> p_date
      or v_existing.justification <> v_note then raise exception 'Request ID was already used for a different adjustment'; end if;
    return v_existing.strike_id;
  end if;
  if exists(select 1 from private.skating_infractions where user_id = p_user_id and marked_date = p_date and voided_at is null) then
    raise exception 'This skater already has an active strike on that date';
  end if;
  insert into private.skating_infractions(user_id, marked_date, created_by, reason, justification)
    values(p_user_id, p_date, auth.uid(), 'manual', v_note) returning id into v_id;
  insert into private.strike_adjustments(id, user_id, strike_id, action, justification, marked_date, reason, actor_id)
    values(p_request_id, p_user_id, v_id, 'ADD', v_note, p_date, 'manual', auth.uid());
  return v_id;
end; $$;
revoke all on function public.admin_add_strike(uuid, date, text, uuid) from public, anon;
grant execute on function public.admin_add_strike(uuid, date, text, uuid) to authenticated;

create function public.admin_void_infraction(p_id uuid, p_justification text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid; v_strike private.skating_infractions%rowtype; v_note text := regexp_replace(p_justification, '^[[:space:]]+|[[:space:]]+$', '', 'g');
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if v_note is null or char_length(v_note) not between 3 and 1000 then raise exception 'Written justification must be 3–1000 characters'; end if;
  select user_id into v_user from private.skating_infractions where id = p_id;
  if not found then raise exception 'Strike not found'; end if;
  perform id from public.users where id = v_user for update;
  select * into v_strike from private.skating_infractions where id = p_id for update;
  if not found then raise exception 'Strike not found'; end if;
  if v_strike.voided_at is not null then return; end if;
  update private.skating_infractions set voided_at = now(), voided_by = auth.uid(), void_justification = v_note where id = p_id;
  insert into private.strike_adjustments(id, user_id, strike_id, action, justification, marked_date, reason, actor_id)
    values(gen_random_uuid(), v_user, p_id, 'REMOVE', v_note, v_strike.marked_date, v_strike.reason, auth.uid());
end; $$;
revoke all on function public.admin_void_infraction(uuid, text) from public, anon;
grant execute on function public.admin_void_infraction(uuid, text) to authenticated;

-- Stale clients must not bypass the written-justification requirement.
create or replace function public.admin_void_infraction(p_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  raise exception 'Written justification is required. Reload and enter a reason for removing the strike';
end; $$;

create function public.admin_submit_infractions(p_user_ids uuid[], p_date date, p_justification text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare v_user uuid; v_id uuid; v_added integer := 0; v_note text := regexp_replace(p_justification, '^[[:space:]]+|[[:space:]]+$', '', 'g');
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if v_note is null or char_length(v_note) not between 3 and 1000 then raise exception 'Written justification must be 3–1000 characters'; end if;
  if p_date is null or p_date > (now() at time zone 'America/New_York')::date then raise exception 'Enter a valid date that is not in the future'; end if;
  if p_user_ids is null or cardinality(p_user_ids) not between 1 and 100
    or exists(select 1 from unnest(p_user_ids) x where x is null)
    or (select count(distinct x) from unnest(p_user_ids) x) <> cardinality(p_user_ids) then raise exception 'Choose 1 to 100 distinct skaters'; end if;
  perform id from public.users where id = any(p_user_ids) order by id for update;
  if (select count(*) from public.users where id = any(p_user_ids)) <> cardinality(p_user_ids) then raise exception 'Skater account not found'; end if;
  foreach v_user in array p_user_ids loop
    v_id := null;
    insert into private.skating_infractions(user_id, marked_date, created_by, justification)
      values(v_user, p_date, auth.uid(), v_note) on conflict(user_id, marked_date) where voided_at is null do nothing returning id into v_id;
    if v_id is not null then
      insert into private.strike_adjustments(id,user_id,strike_id,action,justification,marked_date,reason,actor_id)
        values(gen_random_uuid(),v_user,v_id,'ADD',v_note,p_date,'unregistered',auth.uid());
      v_added := v_added+1;
    end if;
  end loop;
  return jsonb_build_object('added',v_added,'already_marked',cardinality(p_user_ids)-v_added);
end; $$;
revoke all on function public.admin_submit_infractions(uuid[], date, text) from public, anon;
grant execute on function public.admin_submit_infractions(uuid[], date, text) to authenticated;
create or replace function public.admin_submit_infractions(p_user_ids uuid[], p_date date)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  raise exception 'Written justification is required. Reload and enter a reason for awarding strikes';
end; $$;

create or replace function public.admin_user_infractions(p_user_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_history jsonb;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if not exists(select 1 from public.users where id = p_user_id) then raise exception 'User not found'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'marked_date',i.marked_date,'reason',i.reason,
    'session_start',i.session_start,'created_at',i.created_at,'justification',i.justification,
    'created_by',i.created_by,'created_by_name',a.name,'voided_at',i.voided_at,'voided_by',i.voided_by,
    'voided_by_name',v.name,'void_justification',i.void_justification) order by i.marked_date desc,i.created_at desc,i.id),'[]'::jsonb)
    into v_history from private.skating_infractions i
    left join public.users a on a.id=i.created_by left join public.users v on v.id=i.voided_by
    where i.user_id=p_user_id;
  return jsonb_build_object('restriction',private.booking_restriction(p_user_id),'history',v_history,
    'strikes',(select coalesce(jsonb_agg(s),'[]'::jsonb) from jsonb_array_elements(v_history) s where s->>'voided_at' is null));
end; $$;

commit;
