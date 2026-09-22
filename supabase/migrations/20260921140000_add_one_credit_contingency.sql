begin;
create function public.admin_one_credit_contingency()
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
  return 'Balances set to 1 credit; temporary accounts set to 0. Normal tier balances resume at the next weekly reset.';
end;
$$;
revoke all on function public.admin_one_credit_contingency() from public, anon;
grant execute on function public.admin_one_credit_contingency() to authenticated;
commit;
