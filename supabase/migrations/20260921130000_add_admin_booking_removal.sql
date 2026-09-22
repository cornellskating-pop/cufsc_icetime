begin;

-- Durable notification records are inaccessible to browser clients.
create table public.booking_removal_notifications (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique,
  recipient_email text not null,
  member_name text,
  start_time timestamptz not null,
  end_time timestamptz not null,
  refunded boolean not null,
  removed_by uuid not null,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
alter table public.booking_removal_notifications enable row level security;
revoke all on public.booking_removal_notifications from public, anon, authenticated;
grant select, update on public.booking_removal_notifications to service_role;

create function public.notify_booking_removal_webhook()
returns trigger language plpgsql security definer
set search_path = public, pg_temp
as $$
declare v_secret text;
begin
  select decrypted_secret into v_secret from vault.decrypted_secrets
  where name = 'notify_admins_webhook_secret' order by created_at desc limit 1;
  if v_secret is null then
    raise warning 'Booking removal email pending: webhook secret is not configured';
    return new;
  end if;
  perform net.http_post(
    url := 'https://dtdyvpjmavurynbccjei.supabase.co/functions/v1/notify-admins',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret),
    body := jsonb_build_object('type', 'INSERT', 'table', 'booking_removal_notifications', 'record', jsonb_build_object('id', new.id))
  );
  return new;
end;
$$;
revoke all on function public.notify_booking_removal_webhook() from public, anon, authenticated;
create trigger booking_removal_notification after insert on public.booking_removal_notifications
for each row execute function public.notify_booking_removal_webhook();

create function public.admin_remove_booking(p_booking_id uuid)
returns text language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_booking public.bookings%rowtype;
  v_session public.sessions%rowtype;
  v_user public.users%rowtype;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select * into v_booking from public.bookings where id = p_booking_id for update;
  if not found or v_booking.status <> 'active' then return 'Booking is no longer active'; end if;
  select * into v_session from public.sessions where id = v_booking.session_id;
  if not found or v_session.end_time <= now() then raise exception 'Cannot remove a booking from an ended session'; end if;
  select * into v_user from public.users where id = v_booking.user_id for update;
  if not found then raise exception 'Member not found'; end if;
  update public.bookings set status = 'cancelled' where id = p_booking_id;
  if v_booking.credit_charged then
    update public.users set credits_balance = credits_balance + 1 where id = v_user.id;
    insert into public.credit_audit (action, user_id, tier, credits_after)
    values ('CANCEL_REFUND', v_user.id, lower(v_user.tier), v_user.credits_balance + 1);
  end if;
  insert into public.booking_removal_notifications
    (booking_id, recipient_email, member_name, start_time, end_time, refunded, removed_by)
  values (v_booking.id, v_user.email, v_user.name, v_session.start_time, v_session.end_time, v_booking.credit_charged, auth.uid());
  return 'Member removed. Removal email queued.';
end;
$$;
revoke all on function public.admin_remove_booking(uuid) from public, anon;
grant execute on function public.admin_remove_booking(uuid) to authenticated;
commit;
