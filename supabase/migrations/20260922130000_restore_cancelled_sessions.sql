begin;

create table private.session_cancellation_snapshots (
  session_id text not null,
  cancelled_at timestamptz not null,
  capacity integer not null,
  notes text,
  pending_requests jsonb not null default '[]'::jsonb,
  primary key (session_id, cancelled_at)
);
revoke all on private.session_cancellation_snapshots from public, anon, authenticated;

alter table public.booking_removal_notifications add column session_id text;
alter table public.booking_removal_notifications add column superseded_at timestamptz;
update public.booking_removal_notifications n set session_id = b.session_id from public.bookings b where b.id = n.booking_id;
create function public.set_removal_notification_session()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  select session_id into new.session_id from public.bookings where id = new.booking_id;
  return new;
end;
$$;
revoke all on function public.set_removal_notification_session() from public, anon, authenticated;
create trigger set_removal_notification_session before insert on public.booking_removal_notifications
for each row execute function public.set_removal_notification_session();

create table private.session_restorations (
  session_id text not null, cancelled_at timestamptz not null,
  restored_at timestamptz not null default now(), restored_by uuid not null,
  restored_bookings boolean not null, capacity integer not null,
  primary key (session_id, cancelled_at)
);
revoke all on private.session_restorations from public, anon, authenticated;

-- Snapshot future cancellations. Legacy cancellations require an explicit capacity.
create or replace function public.protect_cancelled_session()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if old.cancelled_at is not null then
    if new.cancelled_at is not null then
      raise exception 'Use Restore Session to reopen a cancelled session';
    end if;
    if not public.is_admin() or now() > old.cancelled_at + interval '7 days' or old.start_time <= now() then
      raise exception 'Restoration requires an admin, a future session, and cancellation within seven days';
    end if;
    return new;
  end if;
  if new.cancelled_at is not null then
    insert into private.session_cancellation_snapshots (session_id, cancelled_at, capacity, notes, pending_requests)
      values (old.id, new.cancelled_at, old.capacity, old.notes,
        coalesce((select jsonb_agg(jsonb_build_object('id', id, 'notes', notes)) from public.approval_requests
          where session_id = old.id and status = 'OPEN'), '[]'::jsonb));
    new.capacity := 0;
    new.notes := 'Cancelled: ' || coalesce(nullif(old.notes, ''), old.id);
  end if;
  return new;
end;
$$;

create function public.admin_session_restore_preview(p_session_id text)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare s public.sessions%rowtype; v_capacity integer; v_count integer; v_refunds integer;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select * into s from public.sessions where id = p_session_id;
  if not found or s.cancelled_at is null then raise exception 'Session is not cancelled'; end if;
  select capacity into v_capacity from private.session_cancellation_snapshots where session_id = s.id and cancelled_at = s.cancelled_at;
  select count(*), count(*) filter (where n.refunded) into v_count, v_refunds
    from public.booking_removal_notifications n join public.bookings b on b.id = n.booking_id
    where b.session_id = s.id and n.reason = 'session_cancelled' and n.created_at = s.cancelled_at;
  return jsonb_build_object('cancelled_at', s.cancelled_at, 'deadline', s.cancelled_at + interval '7 days',
    'eligible', now() <= s.cancelled_at + interval '7 days' and now() < s.start_time,
    'capacity', v_capacity, 'bookings', v_count, 'refunded_credits', v_refunds);
end;
$$;
revoke all on function public.admin_session_restore_preview(text) from public, anon;
grant execute on function public.admin_session_restore_preview(text) to authenticated;

create function public.admin_restore_session(p_session_id text, p_restore_bookings boolean, p_capacity integer default null)
returns text language plpgsql security definer set search_path = public, pg_temp as $$
declare
  s public.sessions%rowtype;
  snap private.session_cancellation_snapshots%rowtype;
  v_capacity integer; v_notes text; v_count integer := 0; r record;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  if p_restore_bookings is null then raise exception 'Choose a restoration option'; end if;
  select * into s from public.sessions where id = p_session_id for update nowait;
  if not found then raise exception 'Session not found'; end if;
  if s.cancelled_at is null then return 'Session is already open; nothing changed'; end if;
  if now() > s.cancelled_at + interval '7 days' or now() >= s.start_time then
    raise exception 'Restore within seven days of cancellation and before session start';
  end if;
  select * into snap from private.session_cancellation_snapshots where session_id = s.id and cancelled_at = s.cancelled_at;
  if found then
    v_capacity := snap.capacity; v_notes := snap.notes;
  else
    if p_capacity is null or p_capacity < 0 then raise exception 'Confirm the original capacity for this older cancellation'; end if;
    v_capacity := p_capacity; v_notes := regexp_replace(s.notes, '^Cancelled: ', '');
  end if;

  if p_restore_bookings then
    if exists (select 1 from public.booking_removal_notifications n
      left join public.bookings b on b.id = n.booking_id left join public.users u on u.id = b.user_id
      where n.session_id = s.id and n.reason = 'session_cancelled' and n.created_at = s.cancelled_at
        and (b.id is null or u.id is null)) then
      raise exception 'An original member or booking was deleted. Reopen empty instead.';
    end if;
    -- Do not infer identity from names or addresses. Original booking IDs are authoritative.
    perform u.id from public.users u where u.id in (
      select b.user_id from public.bookings b join public.booking_removal_notifications n on n.booking_id = b.id
      where b.session_id = s.id and n.reason = 'session_cancelled' and n.created_at = s.cancelled_at
    ) order by u.id for update nowait;
    perform b.id from public.bookings b join public.booking_removal_notifications n on n.booking_id = b.id
      where b.session_id = s.id and n.reason = 'session_cancelled' and n.created_at = s.cancelled_at
      order by b.id for update of b nowait;
    for r in select b.*, n.refunded, u.credits_balance from public.bookings b
      join public.booking_removal_notifications n on n.booking_id = b.id
      join public.users u on u.id = b.user_id
      where b.session_id = s.id and n.reason = 'session_cancelled' and n.created_at = s.cancelled_at
      order by b.created_at, b.id
    loop
      if r.status <> 'cancelled' then raise exception 'A previous booking changed; restoration aborted'; end if;
      if r.refunded and r.credits_balance < 1 then
        raise exception 'A member has already used the refunded credit. Restore empty or resolve their balance first.';
      end if;
      if r.refunded then
        update public.users set credits_balance = credits_balance - 1 where id = r.user_id;
        insert into public.credit_audit (action, user_id, tier, credits_after)
          select 'RESTORE_BOOKING', id, lower(tier), credits_balance from public.users where id = r.user_id;
      end if;
      -- New IDs preserve audit/notification history and permit later cancellations.
      insert into public.bookings (user_id, session_id, created_at, status, credit_charged)
        values (r.user_id, s.id, r.created_at, 'active', r.refunded);
      v_count := v_count + 1;
    end loop;
    if (select count(*) from public.bookings where session_id = s.id and status = 'active') > v_capacity then
      raise exception 'Restored bookings exceed capacity';
    end if;
    perform id from public.approval_requests where session_id = s.id and status = 'DENIED'
      and decided_at = s.cancelled_at and notes = 'Session cancelled by an administrator' for update nowait;
    update public.approval_requests set status = 'OPEN', decided_at = null, approver_user_id = null, notes = (select item->>'notes' from jsonb_array_elements(coalesce(snap.pending_requests, '[]'::jsonb)) item where item->>'id' = approval_requests.id)
      where session_id = s.id and status = 'DENIED' and decided_at = s.cancelled_at
      and notes = 'Session cancelled by an administrator';
  end if;
  insert into private.session_restorations (session_id, cancelled_at, restored_by, restored_bookings, capacity)
    values (s.id, s.cancelled_at, auth.uid(), p_restore_bookings, v_capacity);
  update public.booking_removal_notifications set superseded_at = now()
    where session_id = s.id and reason = 'session_cancelled' and created_at = s.cancelled_at;
  update public.sessions set cancelled_at = null, capacity = v_capacity, notes = v_notes where id = s.id;
  return format('Session reopened. %s booking(s) restored.', v_count);
exception when lock_not_available then
  raise exception 'This session is being updated. Please retry restoration.';
end;
$$;
revoke all on function public.admin_restore_session(text, boolean, integer) from public, anon;
grant execute on function public.admin_restore_session(text, boolean, integer) to authenticated;
commit;
