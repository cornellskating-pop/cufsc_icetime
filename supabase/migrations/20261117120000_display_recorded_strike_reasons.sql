begin;

-- Expose only the caller’s own active award explanations, never correction/audit notes.
create or replace function public.my_infractions()
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  if auth.uid() is null or not exists(select 1 from public.users where id=auth.uid()) then raise exception 'Not authorized'; end if;
  return jsonb_build_object('restriction',private.booking_restriction(auth.uid()),'strikes',
    (select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'marked_date',i.marked_date,'reason',i.reason,'justification',i.justification)
      order by i.marked_date desc,i.id),'[]'::jsonb)
     from private.skating_infractions i where user_id=auth.uid() and voided_at is null));
end; $$;
revoke all on function public.my_infractions() from public,anon;
grant execute on function public.my_infractions() to authenticated;

-- Retain the dated admin endpoint and its existing fields for older clients.
drop function public.admin_list_infractions(date);
create function public.admin_list_infractions(p_date date)
returns table (id uuid, user_id uuid, name text, email text, marked_date date, restriction jsonb, reason text, justification text)
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  return query select i.id, u.id, u.name, u.email, i.marked_date, private.booking_restriction(u.id), i.reason, i.justification
    from private.skating_infractions i join public.users u on u.id = i.user_id
    where i.marked_date = p_date and i.voided_at is null order by u.name, u.id;
end; $$;
revoke all on function public.admin_list_infractions(date) from public, anon;
grant execute on function public.admin_list_infractions(date) to authenticated;

commit;
