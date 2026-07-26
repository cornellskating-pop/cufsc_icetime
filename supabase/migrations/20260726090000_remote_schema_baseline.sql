
-- Sanitized schema-only baseline captured from production on 2026-07-26.
-- The legacy webhook bearer token was replaced with a non-secret placeholder;
-- the following hardening migration replaces that webhook entirely.

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."admin_approve_request"("p_request_id" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  ar public.approval_requests%rowtype;
  s public.sessions%rowtype;
  active_count int;
begin
  if public.is_admin() is not true then
    raise exception 'Not authorized';
  end if;

  select * into ar
  from public.approval_requests
  where id = p_request_id;

  if ar.id is null then
    return 'Request not found';
  end if;

  if ar.status <> 'OPEN' then
    return 'Request not open';
  end if;

  select * into s from public.sessions where id = ar.session_id;
  if s.id is null then
    update public.approval_requests set status='DENIED' where id = ar.id;
    return 'Session missing; request denied';
  end if;

  if now() > s.end_time then
    update public.approval_requests set status='DENIED' where id = ar.id;
    return 'Session ended; request denied';
  end if;

  select count(*) into active_count
  from public.bookings
  where session_id = s.id and status='active';

  if active_count >= coalesce(s.capacity,0) then
    return 'Session is full';
  end if;

  if exists (
    select 1 from public.bookings
    where user_id = ar.user_id and session_id = s.id and status='active'
  ) then
    update public.approval_requests set status='APPROVED' where id = ar.id;
    return 'Already booked; request approved';
  end if;

  insert into public.bookings (user_id, session_id, status)
  values (ar.user_id, s.id, 'active');

  update public.approval_requests
  set status='APPROVED'
  where id = ar.id;

  return 'Approved + booked';
end;
$$;


ALTER FUNCTION "public"."admin_approve_request"("p_request_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_approve_user_request"("p_request_id" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_req record;
  v_auth_id uuid;
  v_name text;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select * into v_req from public.approval_requests where id = p_request_id and type = 'NEW_USER';
  if v_req.id is null then return 'Request not found'; end if;
  if v_req.status <> 'OPEN' then return 'Request not open'; end if;

  select
    id,
    coalesce(
      raw_user_meta_data->>'full_name',
      raw_user_meta_data->>'name'
    )
  into v_auth_id, v_name
  from auth.users
  where lower(email) = lower(v_req.requester_email);

  insert into public.users (id, email, name, tier, credits_balance, is_admin, paid_dues)
  values (
    coalesce(v_auth_id, gen_random_uuid()),
    v_req.requester_email,
    v_name,
    'Temp', 0, false, false
  )
  on conflict (id) do update
    set email = excluded.email,
        name  = excluded.name;

  update public.approval_requests
  set status = 'APPROVED', decided_at = now(), approver_user_id = auth.uid()
  where id = p_request_id;

  return 'Approved: user created';
end; $$;


ALTER FUNCTION "public"."admin_approve_user_request"("p_request_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_delete_session"("p_id" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  delete from public.bookings where session_id = p_id;
  delete from public.approval_requests where session_id = p_id;
  delete from public.sessions where id = p_id;
  return 'Deleted';
end; $$;


ALTER FUNCTION "public"."admin_delete_session"("p_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_delete_user"("p_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  delete from public.users where id = p_id;
  return 'Deleted';
end;
$$;


ALTER FUNCTION "public"."admin_delete_user"("p_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_deny_request"("p_request_id" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if public.is_admin() is not true then
    raise exception 'Not authorized';
  end if;

  update public.approval_requests
  set status = 'DENIED'
  where id = p_request_id;

  if not found then
    return 'Request not found';
  end if;

  return 'Denied';
end;
$$;


ALTER FUNCTION "public"."admin_deny_request"("p_request_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_approvals"() RETURNS TABLE("approval_id" "text", "type" "text", "created_at" timestamp with time zone, "status" "text", "user_id" "uuid", "user_email" "text", "user_name" "text", "session_id" "text", "start_time" timestamp with time zone, "end_time" timestamp with time zone, "requester_email" "text", "approver_user_id" "uuid", "decided_at" timestamp with time zone, "notes" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if not exists (select 1 from public.users where id = auth.uid() and is_admin = true) then
    raise exception 'not authorized';
  end if;
  return query
  select
    ar.id, ar.type, ar."timestamp", ar.status,
    ar.user_id, u.email, u.name,
    ar.session_id, s.start_time, s.end_time,
    ar.requester_email, ar.approver_user_id, ar.decided_at, ar.notes
  from public.approval_requests ar
  left join public.users u on u.id = ar.user_id
  left join public.sessions s on s.id = ar.session_id
  order by ar."timestamp" desc;
end; $$;


ALTER FUNCTION "public"."admin_list_approvals"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_session_bookings"() RETURNS TABLE("session_id" "text", "start_time" timestamp with time zone, "end_time" timestamp with time zone, "booking_id" "uuid", "booked_at" timestamp with time zone, "user_id" "uuid", "email" "text", "name" "text", "tier" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    s.id as session_id,
    s.start_time,
    s.end_time,
    b.id as booking_id,
    b.created_at as booked_at,
    u.id as user_id,
    u.email,
    u.name,
    u.tier
  from public.sessions s
  join public.bookings b on b.session_id = s.id and b.status = 'active'
  join public.users u on u.id = b.user_id
  order by s.start_time asc, b.created_at asc;
$$;


ALTER FUNCTION "public"."admin_list_session_bookings"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_session_bookings_grouped"() RETURNS TABLE("session_id" "text", "start_time" timestamp with time zone, "end_time" timestamp with time zone, "label" "text", "capacity" integer, "active_bookings" integer, "bookings" "jsonb")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select
    s.id as session_id,
    s.start_time,
    s.end_time,
    s.notes as label,
    s.capacity,
    count(b.id)::int4 as active_bookings,
    jsonb_agg(
      jsonb_build_object(
        'booking_id', b.id,
        'created_at', b.created_at,
        'user_id', b.user_id,
        'email', u.email,
        'name', u.name,
        'tier', u.tier,
        'status', b.status
      )
      order by b.created_at desc
    ) as bookings
  from bookings b
  join sessions s on s.id = b.session_id
  join users u on u.id = b.user_id
  where b.status in ('active','cancelled')
  group by s.id, s.start_time, s.end_time, s.notes, s.capacity
  order by s.start_time asc;
$$;


ALTER FUNCTION "public"."admin_list_session_bookings_grouped"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_sessions"() RETURNS TABLE("id" "text", "start_time" timestamp with time zone, "end_time" timestamp with time zone, "release_at" timestamp with time zone, "capacity" integer, "notes" "text")
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select s.id, s.start_time, s.end_time, s.release_at, s.capacity, s.notes
  from public.sessions s
  order by s.start_time asc;
$$;


ALTER FUNCTION "public"."admin_list_sessions"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_list_users"() RETURNS TABLE("id" "uuid", "email" "text", "name" "text", "tier" "text", "credits_balance" integer, "is_admin" boolean)
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select u.id, u.email, u.name, u.tier, u.credits_balance, u.is_admin
  from public.users u
  where public.is_admin() = true
  order by lower(u.email) asc;
$$;


ALTER FUNCTION "public"."admin_list_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_upsert_session"("p_id" "text", "p_label" "text", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_release_at" timestamp with time zone, "p_capacity" integer) RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if public.is_admin() is not true then
    raise exception 'Not authorized';
  end if;

  if p_id is null or length(trim(p_id)) = 0 then
    raise exception 'Session id required';
  end if;

  insert into public.sessions (id, notes, start_time, end_time, release_at, capacity)
  values (
    p_id,
    p_label,
    p_start_time,
    p_end_time,
    p_release_at,
    greatest(coalesce(p_capacity, 0), 0)
  )
  on conflict (id) do update
    set notes      = excluded.notes,
        start_time = excluded.start_time,
        end_time   = excluded.end_time,
        release_at = excluded.release_at,
        capacity   = excluded.capacity;

  return p_id;
end;
$$;


ALTER FUNCTION "public"."admin_upsert_session"("p_id" "text", "p_label" "text", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_release_at" timestamp with time zone, "p_capacity" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_upsert_user"("p_id" "uuid", "p_email" "text", "p_name" "text", "p_tier" "text", "p_credits_balance" integer, "p_is_admin" boolean) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_id uuid;
begin
  if public.is_admin() is not true then
    raise exception 'Not authorized';
  end if;

  if p_id is null then
    v_id := gen_random_uuid();
  else
    v_id := p_id;
  end if;

  insert into public.users (id, email, name, tier, credits_balance, is_admin)
  values (v_id, lower(p_email), p_name, p_tier, greatest(coalesce(p_credits_balance,0),0), coalesce(p_is_admin,false))
  on conflict (id) do update
    set email = excluded.email,
        name = excluded.name,
        tier = excluded.tier,
        credits_balance = excluded.credits_balance,
        is_admin = excluded.is_admin;

  return v_id;
end;
$$;


ALTER FUNCTION "public"."admin_upsert_user"("p_id" "uuid", "p_email" "text", "p_name" "text", "p_tier" "text", "p_credits_balance" integer, "p_is_admin" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_weekly_reset_credits"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  if public.is_admin() is not true then
    raise exception 'Not authorized';
  end if;

  update public.users u
  set credits_balance = greatest(coalesce(t.weekly_credits, 0), 0)
  from public.tiers t
  where lower(u.tier) = lower(t.name);

  return 'Weekly credits reset from tiers table';
end;
$$;


ALTER FUNCTION "public"."admin_weekly_reset_credits"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_temp_request"("p_request_id" "text", "p_notes" "text" DEFAULT NULL::"text") RETURNS TABLE("ok" boolean, "message" "text", "session_id" "text", "user_email" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  approver public.users;
  req record;
  s public.sessions;
  active_count int;
begin
  -- Identify caller (by auth email) and require admin
  select * into approver
  from public.users
  where lower(email) = lower(auth.jwt() ->> 'email');

  if approver.id is null then
    return query select false, 'Not authorized.', null::text, null::text;
    return;
  end if;

  if approver.is_admin is not true then
    return query select false, 'Admin privileges required.', null::text, (approver.email)::text;
    return;
  end if;

  -- Load request and lock it (so two admins can't approve the same request)
  select ar.id, ar.status, ar.user_id, ar.session_id, u.email as req_user_email
    into req
  from public.approval_requests ar
  join public.users u on u.id = ar.user_id
  where ar.id = p_request_id
  for update;

  if req.id is null then
    return query select false, 'Approval request not found.', null::text, null::text;
    return;
  end if;

  if req.status <> 'OPEN' then
    return query select false, 'Approval request is not OPEN.', req.session_id::text, req.req_user_email::text;
    return;
  end if;

  -- Lock session row to serialize capacity checks
  select * into s
  from public.sessions
  where id = req.session_id
  for update;

  if s.id is null then
    update public.approval_requests
    set status = 'FAILED',
        approver_user_id = approver.id,
        decided_at = now(),
        notes = coalesce(p_notes, notes)
    where id = p_request_id;

    return query select false, 'Session not found.', req.session_id::text, req.req_user_email::text;
    return;
  end if;

  -- Time guard: don't approve for already-ended sessions
  if now() > s.end_time then
    update public.approval_requests
    set status = 'FAILED',
        approver_user_id = approver.id,
        decided_at = now(),
        notes = coalesce(p_notes, notes)
    where id = p_request_id;

    return query select false, 'Session already ended.', s.id::text, req.req_user_email::text;
    return;
  end if;

  -- Duplicate active booking guard
  if exists (
    select 1 from public.bookings b
    where b.user_id = req.user_id
      and b.session_id = req.session_id
      and b.status = 'active'
  ) then
    update public.approval_requests
    set status = 'FAILED',
        approver_user_id = approver.id,
        decided_at = now(),
        notes = coalesce(p_notes, notes)
    where id = p_request_id;

    return query select false, 'User is already booked for this session.', s.id::text, req.req_user_email::text;
    return;
  end if;

  -- Capacity guard
  select count(*) into active_count
  from public.bookings b
  where b.session_id = req.session_id
    and b.status = 'active';

  if (s.capacity - active_count) <= 0 then
    update public.approval_requests
    set status = 'FAILED',
        approver_user_id = approver.id,
        decided_at = now(),
        notes = coalesce(p_notes, notes)
    where id = p_request_id;

    return query select false, 'Session is full.', s.id::text, req.req_user_email::text;
    return;
  end if;

  -- Create booking (NO credit deduction)
  insert into public.bookings(user_id, session_id, status)
  values (req.user_id, req.session_id, 'active');

  -- Mark request approved
  update public.approval_requests
  set status = 'APPROVED',
      approver_user_id = approver.id,
      decided_at = now(),
      notes = coalesce(p_notes, notes)
  where id = p_request_id;

  return query select true, 'Approved and booked (no credit deducted).', s.id::text, req.req_user_email::text;
end;
$$;


ALTER FUNCTION "public"."approve_temp_request"("p_request_id" "text", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."book_session"("p_session_id" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  v_user users; v_session sessions; v_active_count int;
  v_remaining int; v_now timestamp := now(); v_grace boolean;
begin
  select * into v_user from users where id = auth.uid();
  if v_user is null then return 'User not found'; end if;
  select * into v_session from sessions where id = p_session_id;
  if v_session is null then return 'Session not found'; end if;
  if v_session.release_at is not null and v_now < v_session.release_at then return 'Session not released yet'; end if;
  if v_now > v_session.end_time then return 'Session already ended'; end if;
  select count(*) into v_active_count from bookings where session_id = p_session_id and status = 'active';
  v_remaining := v_session.capacity - v_active_count;
  if v_remaining <= 0 then return 'Session full'; end if;
  v_grace := (v_session.start_time - v_now) <= interval '60 minutes';
  if v_user.tier = 'Temp' and v_user.credits_balance <= 0 then
    if exists (
      select 1 from approval_requests
      where user_id = v_user.id and session_id = p_session_id and status = 'OPEN' and type = 'SESSION'
    ) then return 'PENDING'; end if;
    insert into approval_requests (id, type, user_id, session_id)
    values (gen_random_uuid()::text, 'SESSION', v_user.id, p_session_id);
    return 'Approval request submitted';
  end if;
  if v_user.credits_balance <= 0 and not v_grace then return 'Insufficient credits'; end if;
  insert into bookings (user_id, session_id) values (v_user.id, p_session_id);
  if not v_grace then
    update users set credits_balance = credits_balance - 1 where id = v_user.id;
    insert into credit_audit (action, user_id, tier, credits_after)
    values ('BOOK', v_user.id, v_user.tier, v_user.credits_balance - 1);
  end if;
  return 'Booked successfully';
end; $$;


ALTER FUNCTION "public"."book_session"("p_session_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."book_sessions"("session_ids" "text"[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_credits  int;
  v_tier     text;
  v_session  record;
  v_active_count int;
  v_grace    boolean;
  v_results  jsonb := '[]'::jsonb;
begin
  if v_user_id is null then raise exception 'Not authenticated'; end if;

  select credits_balance, tier into v_credits, v_tier
  from public.users where id = v_user_id;

  if v_credits is null then raise exception 'User not found'; end if;

  for v_session in
    select * from public.sessions where id = any(session_ids)
  loop
    if v_session.start_time <= now() then
      v_results := v_results || jsonb_build_object('ok', false, 'message', 'Session already started');
      continue;
    end if;

    select count(*) into v_active_count
    from public.bookings where session_id = v_session.id and status = 'active';

    if v_active_count >= v_session.capacity then
      v_results := v_results || jsonb_build_object('ok', false, 'message', 'Session is full');
      continue;
    end if;

    if exists (
      select 1 from public.bookings
      where user_id = v_user_id and session_id = v_session.id and status = 'active'
    ) then
      v_results := v_results || jsonb_build_object('ok', false, 'message', 'Already booked');
      continue;
    end if;

    -- Temp with no credits → approval request
    if v_tier = 'Temp' and v_credits <= 0 then
      if exists (
        select 1 from public.approval_requests
        where user_id = v_user_id and session_id = v_session.id and status = 'OPEN' and type = 'SESSION'
      ) then
        v_results := v_results || jsonb_build_object('ok', true, 'message', 'Approval request already pending');
      else
        insert into public.approval_requests (id, type, user_id, session_id, status)
        values (gen_random_uuid()::text, 'SESSION', v_user_id, v_session.id, 'OPEN');
        v_results := v_results || jsonb_build_object('ok', true, 'message', 'Approval request submitted');
      end if;
      continue;
    end if;

    v_grace := (v_session.start_time - now()) <= interval '60 minutes';

    if v_credits <= 0 and not v_grace then
      v_results := v_results || jsonb_build_object('ok', false, 'message', 'Not enough credits');
      continue;
    end if;

    insert into public.bookings (user_id, session_id, status)
    values (v_user_id, v_session.id, 'active')
    on conflict do nothing;

    if not v_grace then
      update public.users set credits_balance = credits_balance - 1 where id = v_user_id;
      v_credits := v_credits - 1;
      insert into public.credit_audit (action, user_id, tier, credits_after)
      values ('BOOK', v_user_id, v_tier, v_credits);
    end if;

    v_results := v_results || jsonb_build_object('ok', true, 'message', 'Booked successfully');
  end loop;

  return v_results;
end;
$$;


ALTER FUNCTION "public"."book_sessions"("session_ids" "text"[]) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$declare
  v_session_id text;
  v_start_time timestamptz;
  v_end_time   timestamptz;
  v_user_id    uuid;
  v_user_tier  text;
  v_credits    integer;
begin
  -- booking owned by caller
  v_session_id := (
    select session_id
    from public.bookings
    where id = p_booking_id
      and user_id = auth.uid()
      and status = 'active'
    limit 1
  );

  if v_session_id is null then
    return 'Booking not found';
  end if;

  -- session times
  v_start_time := (select start_time from public.sessions where id = v_session_id);
  v_end_time   := (select end_time   from public.sessions where id = v_session_id);

  if v_start_time is null then
    return 'Session not found';
  end if;

  -- caller info
  v_user_id   := (select id              from public.users where id = auth.uid());
  v_user_tier := (select tier            from public.users where id = auth.uid());
  v_credits   := (select credits_balance from public.users where id = auth.uid());

  if v_user_id is null then
    return 'User not found';
  end if;

  if now() > v_end_time then
    return 'Session already ended';
  end if;

  if now() > v_start_time + interval '30 minutes' then
    return 'This booking can no longer be cancelled because the session started more than 30 minutes ago.';
  end if;

  update public.bookings
     set status = 'cancelled'
   where id = p_booking_id
     and user_id = auth.uid()
     and status = 'active';

  if now() < v_start_time - interval '30 minutes' then
    update public.users
       set credits_balance = credits_balance + 1
     where id = v_user_id;

    insert into public.credit_audit (action, user_id, tier, credits_after)
    values ('CANCEL_REFUND', v_user_id, v_user_tier, v_credits + 1);
  end if;

  return 'Cancelled';
end;$$;


ALTER FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."deny_temp_request"("p_request_id" "text", "p_notes" "text" DEFAULT NULL::"text") RETURNS TABLE("ok" boolean, "message" "text")
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
declare
  approver public.users;
  req_status text;
begin
  select * into approver
  from public.users
  where lower(email) = lower(auth.jwt() ->> 'email');

  if approver.id is null then
    return query select false, 'Not authorized.';
    return;
  end if;

  if approver.is_admin is not true then
    return query select false, 'Admin privileges required.';
    return;
  end if;

  select status into req_status
  from public.approval_requests
  where id = p_request_id
  for update;

  if req_status is null then
    return query select false, 'Approval request not found.';
    return;
  end if;

  if req_status <> 'OPEN' then
    return query select false, 'Approval request is not OPEN.';
    return;
  end if;

  update public.approval_requests
  set status = 'DENIED',
      approver_user_id = approver.id,
      decided_at = now(),
      notes = coalesce(p_notes, notes)
  where id = p_request_id;

  return query select true, 'Denied.';
end;
$$;


ALTER FUNCTION "public"."deny_temp_request"("p_request_id" "text", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users WHERE id = auth.uid() AND is_admin = true
  );
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_user_access"() RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_email text := auth.jwt() ->> 'email';
begin
  if v_email is null then return 'Not authenticated'; end if;
  if exists (select 1 from public.users where lower(email) = lower(v_email)) then
    return 'Already a member';
  end if;
  if exists (
    select 1 from public.approval_requests
    where type = 'NEW_USER' and lower(requester_email) = lower(v_email) and status = 'OPEN'
  ) then return 'PENDING'; end if;
  insert into public.approval_requests (id, type, user_id, requester_email, status)
  values (gen_random_uuid()::text, 'NEW_USER', NULL, v_email, 'OPEN');
  return 'REQUESTED';
end; $$;


ALTER FUNCTION "public"."request_user_access"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_user_id_on_login"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  UPDATE public.users
  SET id = NEW.id
  WHERE lower(email) = lower(NEW.email)
  AND id != NEW.id;
  RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_user_id_on_login"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."bookings" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "session_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "text" DEFAULT 'active'::"text" NOT NULL,
    CONSTRAINT "bookings_status_check" CHECK (("status" = ANY (ARRAY['active'::"text", 'cancelled'::"text"])))
);


ALTER TABLE "public"."bookings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."sessions" (
    "id" "text" NOT NULL,
    "start_time" timestamp with time zone NOT NULL,
    "end_time" timestamp with time zone NOT NULL,
    "capacity" integer NOT NULL,
    "release_at" timestamp with time zone NOT NULL,
    "notes" "text",
    CONSTRAINT "sessions_capacity_check" CHECK (("capacity" >= 0))
);


ALTER TABLE "public"."sessions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "email" "text" NOT NULL,
    "name" "text",
    "tier" "text" DEFAULT 'Basic'::"text" NOT NULL,
    "credits_balance" integer DEFAULT 0 NOT NULL,
    "is_admin" boolean DEFAULT false NOT NULL,
    "paid_dues" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."users" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."admin_session_bookings" WITH ("security_invoker"='on') AS
 SELECT "s"."id" AS "session_id",
    "s"."start_time",
    "s"."end_time",
    "b"."id" AS "booking_id",
    "b"."created_at" AS "booked_at",
    "u"."id" AS "user_id",
    "u"."email",
    "u"."name",
    "u"."tier"
   FROM (("public"."sessions" "s"
     JOIN "public"."bookings" "b" ON ((("b"."session_id" = "s"."id") AND ("b"."status" = 'active'::"text"))))
     JOIN "public"."users" "u" ON (("u"."id" = "b"."user_id")))
  ORDER BY "s"."start_time", "b"."created_at";


ALTER VIEW "public"."admin_session_bookings" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."admin_session_bookings_grouped" WITH ("security_invoker"='on') AS
 SELECT "s"."id" AS "session_id",
    "s"."start_time",
    "s"."end_time",
    "s"."capacity",
    "s"."notes",
    "count"("b"."id") FILTER (WHERE ("b"."status" = 'active'::"text")) AS "active_bookings",
    COALESCE("jsonb_agg"("jsonb_build_object"('booking_id', "b"."id", 'created_at', "b"."created_at", 'status', "b"."status", 'user_id', "u"."id", 'email', "u"."email", 'name', "u"."name", 'tier', "u"."tier") ORDER BY "u"."name") FILTER (WHERE ("b"."id" IS NOT NULL)), '[]'::"jsonb") AS "bookings"
   FROM (("public"."sessions" "s"
     LEFT JOIN "public"."bookings" "b" ON (("b"."session_id" = "s"."id")))
     LEFT JOIN "public"."users" "u" ON (("u"."id" = "b"."user_id")))
  GROUP BY "s"."id", "s"."start_time", "s"."end_time", "s"."capacity", "s"."notes"
  ORDER BY "s"."start_time";


ALTER VIEW "public"."admin_session_bookings_grouped" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."approval_requests" (
    "id" "text" NOT NULL,
    "timestamp" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "text" DEFAULT 'OPEN'::"text" NOT NULL,
    "user_id" "uuid",
    "session_id" "text",
    "approver_user_id" "uuid",
    "decided_at" timestamp with time zone,
    "notes" "text",
    "type" "text" DEFAULT 'SESSION'::"text" NOT NULL,
    "requester_email" "text",
    CONSTRAINT "approval_requests_status_check" CHECK (("status" = ANY (ARRAY['OPEN'::"text", 'APPROVED'::"text", 'FAILED'::"text", 'DENIED'::"text"])))
);


ALTER TABLE "public"."approval_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."credit_audit" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "timestamp" timestamp with time zone DEFAULT "now"() NOT NULL,
    "action" "text" NOT NULL,
    "user_id" "uuid",
    "tier" "text",
    "credits_after" integer
);


ALTER TABLE "public"."credit_audit" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."me" WITH ("security_invoker"='on') AS
 SELECT "id",
    "email",
    "name",
    "tier",
    "credits_balance",
    "is_admin",
    "paid_dues",
    "created_at"
   FROM "public"."users" "u"
  WHERE ("lower"("email") = "lower"(("auth"."jwt"() ->> 'email'::"text")));


ALTER VIEW "public"."me" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."my_bookings" AS
 SELECT "b"."id" AS "booking_id",
    "b"."status",
    "b"."session_id",
    "s"."start_time",
    "s"."end_time"
   FROM ("public"."bookings" "b"
     JOIN "public"."sessions" "s" ON (("s"."id" = "b"."session_id")))
  WHERE ("b"."user_id" = "auth"."uid"());


ALTER VIEW "public"."my_bookings" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."sessions_with_spots" WITH ("security_invoker"='false') AS
 SELECT "s"."id",
    "s"."start_time",
    "s"."end_time",
    "s"."release_at",
    "s"."capacity",
    "s"."notes",
    GREATEST(("s"."capacity" - COALESCE("b"."active_count", (0)::bigint)), (0)::bigint) AS "spots_left"
   FROM ("public"."sessions" "s"
     LEFT JOIN ( SELECT "bookings"."session_id",
            "count"(*) AS "active_count"
           FROM "public"."bookings"
          WHERE ("bookings"."status" = 'active'::"text")
          GROUP BY "bookings"."session_id") "b" ON (("b"."session_id" = "s"."id")));


ALTER VIEW "public"."sessions_with_spots" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."tiers" (
    "name" "text" NOT NULL,
    "weekly_credits" integer NOT NULL
);


ALTER TABLE "public"."tiers" OWNER TO "postgres";


ALTER TABLE ONLY "public"."approval_requests"
    ADD CONSTRAINT "approval_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."credit_audit"
    ADD CONSTRAINT "credit_audit_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."tiers"
    ADD CONSTRAINT "tiers_pkey" PRIMARY KEY ("name");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_email_key" UNIQUE ("email");



ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



CREATE UNIQUE INDEX "uniq_active_booking" ON "public"."bookings" USING "btree" ("user_id", "session_id") WHERE ("status" = 'active'::"text");



CREATE OR REPLACE TRIGGER "notify-admins-on-approval" AFTER INSERT ON "public"."approval_requests" FOR EACH ROW EXECUTE FUNCTION "supabase_functions"."http_request"('https://dtdyvpjmavurynbccjei.supabase.co/functions/v1/notify-admins', 'POST', '{"Content-type":"application/json","Authorization":"Bearer <REDACTED_SERVICE_ROLE_TOKEN>"}', '{}', '5000');



ALTER TABLE ONLY "public"."approval_requests"
    ADD CONSTRAINT "approval_requests_approver_user_id_fkey" FOREIGN KEY ("approver_user_id") REFERENCES "public"."users"("id");



ALTER TABLE ONLY "public"."approval_requests"
    ADD CONSTRAINT "approval_requests_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."approval_requests"
    ADD CONSTRAINT "approval_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE ON DELETE SET NULL;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "public"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."bookings"
    ADD CONSTRAINT "bookings_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON UPDATE CASCADE;



ALTER TABLE ONLY "public"."credit_audit"
    ADD CONSTRAINT "credit_audit_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE SET NULL;



CREATE POLICY "admin modify sessions" ON "public"."sessions" USING ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE (("u"."id" = "auth"."uid"()) AND ("u"."is_admin" = true)))));



ALTER TABLE "public"."approval_requests" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "approvals_admin_update" ON "public"."approval_requests" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE (("lower"("u"."email") = "lower"(("auth"."jwt"() ->> 'email'::"text"))) AND "u"."is_admin")))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE (("lower"("u"."email") = "lower"(("auth"."jwt"() ->> 'email'::"text"))) AND "u"."is_admin"))));



CREATE POLICY "approvals_insert" ON "public"."approval_requests" FOR INSERT WITH CHECK ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "approvals_insert_allowlisted" ON "public"."approval_requests" FOR INSERT TO "authenticated" WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE ("lower"("u"."email") = "lower"(("auth"."jwt"() ->> 'email'::"text"))))));



CREATE POLICY "approvals_select" ON "public"."approval_requests" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "approvals_update" ON "public"."approval_requests" FOR UPDATE USING ("public"."is_admin"());



ALTER TABLE "public"."bookings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "bookings_cancel_own" ON "public"."bookings" FOR UPDATE TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE (("u"."id" = "bookings"."user_id") AND ("lower"("u"."email") = "lower"(("auth"."jwt"() ->> 'email'::"text"))))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE (("u"."id" = "bookings"."user_id") AND ("lower"("u"."email") = "lower"(("auth"."jwt"() ->> 'email'::"text")))))));



CREATE POLICY "bookings_insert_own" ON "public"."bookings" FOR INSERT WITH CHECK ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "bookings_select_own" ON "public"."bookings" FOR SELECT USING ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "bookings_update_own" ON "public"."bookings" FOR UPDATE USING ((("user_id" = "auth"."uid"()) OR "public"."is_admin"()));



ALTER TABLE "public"."credit_audit" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "read sessions" ON "public"."sessions" FOR SELECT USING (("auth"."uid"() IS NOT NULL));



ALTER TABLE "public"."sessions" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "sessions_admin_write" ON "public"."sessions" USING ((EXISTS ( SELECT 1
   FROM "public"."users"
  WHERE (("users"."id" = "auth"."uid"()) AND ("users"."is_admin" = true)))));



CREATE POLICY "sessions_read" ON "public"."sessions" FOR SELECT USING (("auth"."role"() = 'authenticated'::"text"));



CREATE POLICY "sessions_read_allowlisted" ON "public"."sessions" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE ("lower"("u"."email") = "lower"(("auth"."jwt"() ->> 'email'::"text"))))));



ALTER TABLE "public"."tiers" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "tiers_read_allowlisted" ON "public"."tiers" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."users" "u"
  WHERE ("lower"("u"."email") = "lower"(("auth"."jwt"() ->> 'email'::"text"))))));



ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "users_admin_all" ON "public"."users" USING ("public"."is_admin"());



CREATE POLICY "users_select_own" ON "public"."users" FOR SELECT USING ((("id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "users_update_own" ON "public"."users" FOR UPDATE USING (("id" = "auth"."uid"()));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_approve_request"("p_request_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_approve_request"("p_request_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_approve_request"("p_request_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_approve_user_request"("p_request_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_approve_user_request"("p_request_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_approve_user_request"("p_request_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_delete_session"("p_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_delete_session"("p_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_delete_session"("p_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_delete_user"("p_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_delete_user"("p_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_delete_user"("p_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_deny_request"("p_request_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."admin_deny_request"("p_request_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_deny_request"("p_request_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_list_approvals"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_approvals"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_approvals"() TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_list_session_bookings"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_session_bookings"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_session_bookings"() TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_list_session_bookings_grouped"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_session_bookings_grouped"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_session_bookings_grouped"() TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_list_sessions"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_sessions"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_sessions"() TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_list_users"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_list_users"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_list_users"() TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_upsert_session"("p_id" "text", "p_label" "text", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_release_at" timestamp with time zone, "p_capacity" integer) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_upsert_session"("p_id" "text", "p_label" "text", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_release_at" timestamp with time zone, "p_capacity" integer) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_upsert_session"("p_id" "text", "p_label" "text", "p_start_time" timestamp with time zone, "p_end_time" timestamp with time zone, "p_release_at" timestamp with time zone, "p_capacity" integer) TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_upsert_user"("p_id" "uuid", "p_email" "text", "p_name" "text", "p_tier" "text", "p_credits_balance" integer, "p_is_admin" boolean) TO "anon";
GRANT ALL ON FUNCTION "public"."admin_upsert_user"("p_id" "uuid", "p_email" "text", "p_name" "text", "p_tier" "text", "p_credits_balance" integer, "p_is_admin" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_upsert_user"("p_id" "uuid", "p_email" "text", "p_name" "text", "p_tier" "text", "p_credits_balance" integer, "p_is_admin" boolean) TO "service_role";



GRANT ALL ON FUNCTION "public"."admin_weekly_reset_credits"() TO "anon";
GRANT ALL ON FUNCTION "public"."admin_weekly_reset_credits"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_weekly_reset_credits"() TO "service_role";



GRANT ALL ON FUNCTION "public"."approve_temp_request"("p_request_id" "text", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."approve_temp_request"("p_request_id" "text", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_temp_request"("p_request_id" "text", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."book_session"("p_session_id" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."book_session"("p_session_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."book_session"("p_session_id" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."book_sessions"("session_ids" "text"[]) TO "anon";
GRANT ALL ON FUNCTION "public"."book_sessions"("session_ids" "text"[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."book_sessions"("session_ids" "text"[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cancel_booking"("p_booking_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."deny_temp_request"("p_request_id" "text", "p_notes" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."deny_temp_request"("p_request_id" "text", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."deny_temp_request"("p_request_id" "text", "p_notes" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."request_user_access"() TO "anon";
GRANT ALL ON FUNCTION "public"."request_user_access"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."request_user_access"() TO "service_role";



GRANT ALL ON FUNCTION "public"."sync_user_id_on_login"() TO "anon";
GRANT ALL ON FUNCTION "public"."sync_user_id_on_login"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."sync_user_id_on_login"() TO "service_role";



GRANT ALL ON TABLE "public"."bookings" TO "anon";
GRANT ALL ON TABLE "public"."bookings" TO "authenticated";
GRANT ALL ON TABLE "public"."bookings" TO "service_role";



GRANT ALL ON TABLE "public"."sessions" TO "anon";
GRANT ALL ON TABLE "public"."sessions" TO "authenticated";
GRANT ALL ON TABLE "public"."sessions" TO "service_role";



GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";



GRANT ALL ON TABLE "public"."admin_session_bookings" TO "anon";
GRANT ALL ON TABLE "public"."admin_session_bookings" TO "authenticated";
GRANT ALL ON TABLE "public"."admin_session_bookings" TO "service_role";



GRANT ALL ON TABLE "public"."admin_session_bookings_grouped" TO "anon";
GRANT ALL ON TABLE "public"."admin_session_bookings_grouped" TO "authenticated";
GRANT ALL ON TABLE "public"."admin_session_bookings_grouped" TO "service_role";



GRANT ALL ON TABLE "public"."approval_requests" TO "anon";
GRANT ALL ON TABLE "public"."approval_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."approval_requests" TO "service_role";



GRANT ALL ON TABLE "public"."credit_audit" TO "anon";
GRANT ALL ON TABLE "public"."credit_audit" TO "authenticated";
GRANT ALL ON TABLE "public"."credit_audit" TO "service_role";



GRANT ALL ON TABLE "public"."me" TO "anon";
GRANT ALL ON TABLE "public"."me" TO "authenticated";
GRANT ALL ON TABLE "public"."me" TO "service_role";



GRANT ALL ON TABLE "public"."my_bookings" TO "anon";
GRANT ALL ON TABLE "public"."my_bookings" TO "authenticated";
GRANT ALL ON TABLE "public"."my_bookings" TO "service_role";



GRANT ALL ON TABLE "public"."sessions_with_spots" TO "anon";
GRANT ALL ON TABLE "public"."sessions_with_spots" TO "authenticated";
GRANT ALL ON TABLE "public"."sessions_with_spots" TO "service_role";



GRANT ALL ON TABLE "public"."tiers" TO "anon";
GRANT ALL ON TABLE "public"."tiers" TO "authenticated";
GRANT ALL ON TABLE "public"."tiers" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
