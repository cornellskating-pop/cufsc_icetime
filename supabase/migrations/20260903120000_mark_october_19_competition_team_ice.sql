begin;

do $$
declare
  target_session_id constant text := 'CUFSC-2026-10-19-2000';
begin
  if not exists (
    select 1
    from public.sessions
    where id = target_session_id
  ) then
    raise exception 'Session % does not exist', target_session_id;
  end if;

  if exists (
    select 1
    from public.bookings
    where session_id = target_session_id
      and status = 'active'
  ) then
    raise exception 'Session % has active bookings and was not changed', target_session_id;
  end if;

  update public.sessions
  set notes = 'Competition Team Practice',
      capacity = 0
  where id = target_session_id;
end;
$$;

commit;
