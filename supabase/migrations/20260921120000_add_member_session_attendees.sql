begin;

-- Deliberately expose names only; keep profile and booking RLS unchanged.
create function public.list_upcoming_session_attendees()
returns table (
  session_id text,
  start_time timestamptz,
  end_time timestamptz,
  label text,
  capacity integer,
  names text[]
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.users u where u.id = auth.uid()
  ) then
    raise exception 'Not authorized';
  end if;

  return query
  select s.id, s.start_time, s.end_time, s.notes, s.capacity,
    coalesce(array_agg(coalesce(nullif(btrim(u.name), ''), '—') order by b.created_at, b.id)
      filter (where b.id is not null), array[]::text[])
  from public.sessions s
  left join public.bookings b on b.session_id = s.id and b.status = 'active'
  left join public.users u on u.id = b.user_id
  where s.start_time >= now()
  group by s.id, s.start_time, s.end_time, s.notes, s.capacity
  order by s.start_time, s.id;
end;
$$;

revoke all on function public.list_upcoming_session_attendees() from public, anon;
grant execute on function public.list_upcoming_session_attendees() to authenticated;

commit;
