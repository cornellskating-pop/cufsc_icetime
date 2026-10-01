begin;
alter table public.users add column booking_view text not null default 'calendar'
  check (booking_view in ('calendar', 'list'));
create function public.set_booking_view(p_view text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then raise exception 'Not authenticated'; end if;
  if p_view is null or p_view not in ('calendar', 'list') then raise exception 'Invalid booking view'; end if;
  update public.users set booking_view = p_view where id = auth.uid();
  if not found then raise exception 'Member not found'; end if;
end;
$$;
revoke all on function public.set_booking_view(text) from public, anon;
grant execute on function public.set_booking_view(text) to authenticated;

create or replace function public.book_sessions(session_ids text[])
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_credits integer;
  v_tier text;
  v_session_id text;
  v_session public.sessions%rowtype;
  v_active_count integer;
  v_grace boolean;
  v_results jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'Not authenticated';
  end if;
  if session_ids is null or cardinality(session_ids) = 0 then
    raise exception 'Select at least one session';
  end if;
  if exists (
    select 1
    from unnest(session_ids) as item(value)
    where value is null
  ) then
    raise exception 'Session IDs cannot be null';
  end if;
  if (
    select count(distinct value)
    from unnest(session_ids) as item(value)
  ) <> cardinality(session_ids) then
    raise exception 'Duplicate session IDs are not allowed';
  end if;

  select credits_balance, lower(tier)
  into v_credits, v_tier
  from public.users
  where id = v_user_id
  for update;

  if not found then
    raise exception 'User not found';
  end if;

  -- Acquire session locks in a consistent order for larger overlapping batches.
  perform s.id from public.sessions s where s.id = any(session_ids) order by s.id for update;

  foreach v_session_id in array session_ids
  loop
    select * into v_session
    from public.sessions
    where id = v_session_id
    for update;

    if not found then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Session not found'
      );
      continue;
    end if;

    if v_session.release_at is not null and now() < v_session.release_at then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Session is not open yet'
      );
      continue;
    end if;

    if now() >= v_session.start_time then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Session already started'
      );
      continue;
    end if;

    if exists (
      select 1
      from public.bookings
      where user_id = v_user_id
        and session_id = v_session_id
        and status = 'active'
    ) then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Already booked'
      );
      continue;
    end if;

    select count(*) into v_active_count
    from public.bookings
    where session_id = v_session_id
      and status = 'active';

    if v_active_count >= v_session.capacity then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Session is full'
      );
      continue;
    end if;

    if v_tier = 'temp' and v_credits <= 0 then
      if exists (
        select 1
        from public.approval_requests
        where user_id = v_user_id
          and session_id = v_session_id
          and status = 'OPEN'
          and type = 'SESSION'
      ) then
        v_results := v_results || jsonb_build_object(
          'ok', true,
          'session_id', v_session_id,
          'message', 'Approval request already pending'
        );
      else
        insert into public.approval_requests (
          id, type, user_id, session_id, status
        )
        values (
          gen_random_uuid()::text,
          'SESSION',
          v_user_id,
          v_session_id,
          'OPEN'
        );
        v_results := v_results || jsonb_build_object(
          'ok', true,
          'session_id', v_session_id,
          'message', 'Approval request submitted'
        );
      end if;
      continue;
    end if;

    v_grace := v_session.start_time - now() <= interval '60 minutes';

    if v_credits <= 0 and not v_grace then
      v_results := v_results || jsonb_build_object(
        'ok', false,
        'session_id', v_session_id,
        'message', 'Not enough credits'
      );
      continue;
    end if;

    insert into public.bookings (
      user_id, session_id, status, credit_charged
    )
    values (
      v_user_id, v_session_id, 'active', not v_grace
    );

    if not v_grace then
      v_credits := v_credits - 1;
      update public.users
      set credits_balance = v_credits
      where id = v_user_id;

      insert into public.credit_audit (
        action, user_id, tier, credits_after
      )
      values (
        'BOOK', v_user_id, v_tier, v_credits
      );
    end if;

    v_results := v_results || jsonb_build_object(
      'ok', true,
      'session_id', v_session_id,
      'message', 'Booked successfully'
    );
  end loop;

  return v_results;
end;
$$;


commit;
