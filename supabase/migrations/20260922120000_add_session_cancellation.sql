begin;
alter table public.sessions add column cancelled_at timestamptz;
alter table public.booking_removal_notifications
  add column reason text not null default 'booking_removed'
  check (reason in ('booking_removed', 'session_cancelled'));

-- Retain the session/history while closing all existing booking entry points.
create function public.protect_cancelled_session()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if old.cancelled_at is not null then
    raise exception 'Cancelled sessions cannot be edited or reopened';
  end if;
  if new.cancelled_at is not null then
    new.capacity := 0;
    new.notes := 'Cancelled: ' || coalesce(nullif(old.notes, ''), old.id);
  end if;
  return new;
end;
$$;
revoke all on function public.protect_cancelled_session() from public, anon, authenticated;
create trigger protect_cancelled_session before update on public.sessions
for each row execute function public.protect_cancelled_session();

create function public.admin_cancel_session(p_session_id text)
returns text language plpgsql security definer
set search_path = public, pg_temp as $$
declare
  v_session public.sessions%rowtype;
  v_booking record;
  v_count integer := 0;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select * into v_session from public.sessions where id = p_session_id for update nowait;
  if not found then raise exception 'Session not found'; end if;
  if v_session.cancelled_at is not null then return 'Session already cancelled'; end if;
  if v_session.end_time <= now() then raise exception 'Cannot cancel an ended session'; end if;

  -- Booking/approval RPCs lock users before sessions; never wait on those
  -- users while holding the session lock. On contention roll back and retry.
  perform u.id from public.users u where u.id in
    (select b.user_id from public.bookings b where b.session_id = p_session_id and b.status = 'active')
    order by u.id for update nowait;
  perform b.id from public.bookings b where b.session_id = p_session_id and b.status = 'active'
    order by b.id for update nowait;

  update public.sessions set cancelled_at = now() where id = p_session_id;
  for v_booking in
    select b.*, u.email, u.name, u.tier from public.bookings b
    join public.users u on u.id = b.user_id
    where b.session_id = p_session_id and b.status = 'active' order by b.id
  loop
    update public.bookings set status = 'cancelled' where id = v_booking.id;
    if v_booking.credit_charged then
      update public.users set credits_balance = credits_balance + 1 where id = v_booking.user_id;
      insert into public.credit_audit (action, user_id, tier, credits_after)
        select 'CANCEL_REFUND', id, lower(tier), credits_balance from public.users where id = v_booking.user_id;
    end if;
    insert into public.booking_removal_notifications
      (booking_id, recipient_email, member_name, start_time, end_time, refunded, removed_by, reason)
    values (v_booking.id, v_booking.email, v_booking.name, v_session.start_time, v_session.end_time,
      v_booking.credit_charged, auth.uid(), 'session_cancelled');
    v_count := v_count + 1;
  end loop;
  -- Lock pending requests without waiting on a concurrent approval operation.
  perform id from public.approval_requests where session_id = p_session_id and status = 'OPEN' for update nowait;
  update public.approval_requests set status = 'DENIED', decided_at = now(), approver_user_id = auth.uid(),
    notes = 'Session cancelled by an administrator'
    where session_id = p_session_id and status = 'OPEN';
  return format('Session cancelled. %s booking(s) cancelled; charged credits refunded and notification emails queued.', v_count);
exception when lock_not_available then
  raise exception 'This session is being updated. Please retry cancellation.';
end;
$$;
revoke all on function public.admin_cancel_session(text) from public, anon;
grant execute on function public.admin_cancel_session(text) to authenticated;
create or replace view public.sessions_with_spots with (security_invoker = false) as
select s.id, s.start_time, s.end_time, s.release_at, s.capacity, s.notes,
  greatest(s.capacity - coalesce(b.active_count, 0::bigint), 0::bigint) as spots_left,
  s.cancelled_at
from public.sessions s
left join (select session_id, count(*) as active_count from public.bookings
  where status = 'active' group by session_id) b on b.session_id = s.id;
commit;
