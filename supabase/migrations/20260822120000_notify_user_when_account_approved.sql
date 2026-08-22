begin;

-- Reuse the authenticated approval webhook for both new-request admin emails
-- and new-user approval emails. Only the relevant status transition is sent.
create or replace function public.notify_admins_webhook()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_webhook_secret text;
begin
  if tg_op = 'UPDATE' and not (
    new.type = 'NEW_USER'
    and new.status = 'APPROVED'
    and old.status is distinct from new.status
  ) then
    return new;
  end if;

  select decrypted_secret
  into v_webhook_secret
  from vault.decrypted_secrets
  where name = 'notify_admins_webhook_secret'
  order by created_at desc
  limit 1;

  if v_webhook_secret is null then
    raise warning 'notify_admins_webhook_secret is not configured; notification skipped';
    return new;
  end if;

  perform net.http_post(
    url := 'https://dtdyvpjmavurynbccjei.supabase.co/functions/v1/notify-admins',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-webhook-secret', v_webhook_secret
    ),
    body := jsonb_build_object(
      'type', tg_op,
      'schema', 'public',
      'table', 'approval_requests',
      'record', jsonb_build_object('id', new.id)
    )
  );

  return new;
end;
$$;

revoke all on function public.notify_admins_webhook() from public, anon, authenticated;

drop trigger if exists "notify-admins-on-approval" on public.approval_requests;
create trigger "notify-admins-on-approval"
after insert or update of status on public.approval_requests
for each row execute function public.notify_admins_webhook();

commit;
