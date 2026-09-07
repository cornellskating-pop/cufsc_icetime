do $$
begin
  if not exists (
    select 1
    from public.tiers
    where lower(name) = 'temp'
      and weekly_credits = 0
  ) then
    raise exception 'The zero-credit temp tier must exist before converting accounts';
  end if;
end;
$$;

update public.users
set tier = 'temp',
    credits_balance = 0
where is_admin = false
  and (
    tier is distinct from 'temp'
    or credits_balance is distinct from 0
  );
