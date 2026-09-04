begin;

do $$
declare
  updated_count integer;
begin
  update public.sessions
  set release_at = (
    (release_at at time zone 'America/New_York')::date + time '21:00:00'
  ) at time zone 'America/New_York'
  where id like 'CUFSC-2026-%'
    and (start_time at time zone 'America/New_York')::date
      between date '2026-09-10' and date '2026-12-07'
    and release_at is not null;

  get diagnostics updated_count = row_count;

  if updated_count <> 46 then
    raise exception 'Expected to update 46 Fall 2026 sessions, updated %', updated_count;
  end if;
end;
$$;

commit;
