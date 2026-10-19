begin;

-- Shared by the scheduled worker and the authorized manual admin RPC.
create or replace function private.weekly_reset_credits()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Serialize with booking/credit edits, using the same stable order as other resets.
  perform id from public.users
  where lower(tier) = 'basic' or is_admin is true
  order by id for update;

  update public.users
  set credits_balance = 2
  where lower(tier) = 'basic' or is_admin is true;

  return 'Basic members and admins reset to 2 credits. Other balances, including temporary members, preserved.';
end;
$$;
revoke all on function private.weekly_reset_credits() from public, anon, authenticated;

-- Keep the contingency behavior; clarify its completion message.
create or replace function public.admin_one_credit_contingency()
returns text language plpgsql security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  -- Lock in a stable order and serialize with the existing per-user booking locks.
  perform id from public.users order by id for update;
  with updated as (
    update public.users
    set credits_balance = case when lower(tier) = 'temp' then 0 else 1 end
    returning id, tier, credits_balance
  )
  insert into public.credit_audit (action, user_id, tier, credits_after)
  select 'CONTINGENCY_RESET', id, lower(tier), credits_balance from updated;
  return 'Balances set to 1 credit; temporary accounts set to 0. The next weekly reset sets Basic members and admins to 2; other balances stay unchanged.';
end;
$$;
revoke all on function public.admin_one_credit_contingency() from public, anon;
grant execute on function public.admin_one_credit_contingency() to authenticated;
commit;
