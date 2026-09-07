create or replace function public.admin_reset_non_admin_accounts_to_temp()
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_updated_count integer;
begin
  if not public.is_admin() then
    raise exception 'Not authorized';
  end if;

  if not exists (
    select 1
    from public.tiers
    where lower(name) = 'temp'
      and weekly_credits = 0
  ) then
    raise exception 'The zero-credit temp tier must exist before resetting accounts';
  end if;

  update public.users
  set tier = 'temp',
      credits_balance = 0
  where is_admin = false
    and (
      tier is distinct from 'temp'
      or credits_balance is distinct from 0
    );

  get diagnostics v_updated_count = row_count;

  return format(
    'Reset %s non-admin account%s to the temp tier',
    v_updated_count,
    case when v_updated_count = 1 then '' else 's' end
  );
end;
$$;

revoke all on function public.admin_reset_non_admin_accounts_to_temp()
from public, anon, authenticated;
grant execute on function public.admin_reset_non_admin_accounts_to_temp()
to authenticated;
