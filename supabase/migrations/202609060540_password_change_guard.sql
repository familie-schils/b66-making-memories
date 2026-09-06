create or replace function public.can_change_own_password(p_user_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select auth.uid() = p_user_id
$$;

revoke all on function public.can_change_own_password(uuid) from public;
revoke all on function public.can_change_own_password(uuid) from anon;
grant execute on function public.can_change_own_password(uuid) to authenticated;
grant execute on function public.can_change_own_password(uuid) to service_role;
