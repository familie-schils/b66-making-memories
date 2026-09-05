-- Veilige provisioning voor "Nieuwe Campereigenaar"
-- Gebruik Edge Function + auth.admin.createUser(), daarna interne RPC voor domeindata.

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'head_admin' check (role = 'head_admin'),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create unique index if not exists platform_admins_single_active_head_admin_idx
  on public.platform_admins ((role))
  where active = true and role = 'head_admin';

create table if not exists public.owner_provision_audit (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  target_user_id uuid references auth.users(id) on delete set null,
  target_email text not null,
  idempotency_key text,
  status text not null check (status in ('attempt', 'success', 'failed')),
  error_message text,
  result jsonb
);

create unique index if not exists owner_provision_audit_created_by_idempotency_idx
  on public.owner_provision_audit (created_by, idempotency_key)
  where idempotency_key is not null and status = 'success';

create unique index if not exists profiles_email_lower_unique_idx
  on public.profiles (lower(email));

alter table public.campers
  add column if not exists owner_id uuid references auth.users(id);

create unique index if not exists camper_users_camper_user_unique_idx
  on public.camper_users (camper_id, user_id);

alter table public.camper_users
  drop constraint if exists camper_users_role_check;

alter table public.camper_users
  add constraint camper_users_role_check
  check (role in ('admin', 'editor', 'member', 'lid'));

create or replace function public.is_head_admin(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.platform_admins pa
    where pa.user_id = p_user_id
      and pa.active = true
      and pa.role = 'head_admin'
  );
$$;

revoke all on function public.is_head_admin(uuid) from public;
grant execute on function public.is_head_admin(uuid) to authenticated;
grant execute on function public.is_head_admin(uuid) to service_role;

create or replace function public.provision_camper_owner_data(
  p_user_id uuid,
  p_email text,
  p_display_name text default null,
  p_camper_name text default null
)
returns table(profile_id uuid, camper_id bigint)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_camper_id bigint;
  v_email text;
  v_display_name text;
  v_camper_name text;
begin
  if p_user_id is null then
    raise exception 'p_user_id is verplicht';
  end if;

  v_email := lower(trim(coalesce(p_email, '')));
  if v_email = '' then
    raise exception 'p_email is verplicht';
  end if;

  v_display_name := nullif(trim(coalesce(p_display_name, '')), '');
  v_camper_name := nullif(trim(coalesce(p_camper_name, '')), '');
  if v_camper_name is null then
    v_camper_name := 'Camper van ' || v_email;
  end if;

  insert into public.profiles (user_id, email, display_name)
  values (
    p_user_id,
    v_email,
    coalesce(v_display_name, split_part(v_email, '@', 1))
  )
  on conflict (user_id) do update
  set
    email = excluded.email,
    display_name = excluded.display_name;

  insert into public.campers (naam, owner_id)
  values (v_camper_name, p_user_id)
  returning id into v_camper_id;

  insert into public.camper_users (camper_id, user_id, role)
  values (v_camper_id, p_user_id, 'admin')
  on conflict (camper_id, user_id) do update
  set role = 'admin';

  return query
  select p_user_id, v_camper_id;
end;
$$;

revoke all on function public.provision_camper_owner_data(uuid, text, text, text) from public;
revoke all on function public.provision_camper_owner_data(uuid, text, text, text) from anon;
revoke all on function public.provision_camper_owner_data(uuid, text, text, text) from authenticated;
grant execute on function public.provision_camper_owner_data(uuid, text, text, text) to service_role;

alter table public.platform_admins enable row level security;
alter table public.owner_provision_audit enable row level security;

drop policy if exists platform_admins_select_policy on public.platform_admins;
create policy platform_admins_select_policy
on public.platform_admins
for select
to authenticated
using (
  auth.uid() = user_id
  or public.is_head_admin(auth.uid())
);

drop policy if exists owner_provision_audit_select_policy on public.owner_provision_audit;
create policy owner_provision_audit_select_policy
on public.owner_provision_audit
for select
to authenticated
using (
  created_by = auth.uid()
  or public.is_head_admin(auth.uid())
);

revoke all on public.platform_admins from anon;
revoke all on public.platform_admins from authenticated;
grant select on public.platform_admins to authenticated;

revoke all on public.owner_provision_audit from anon;
revoke all on public.owner_provision_audit from authenticated;
grant select on public.owner_provision_audit to authenticated;

-- Compatibele bootstrap: zet bestaande vaste hoofdadmin over naar persistente rol.
insert into public.platform_admins (user_id, role, active, created_by)
select
  '13032a8d-1c16-4f80-b497-b679abf36682'::uuid,
  'head_admin',
  true,
  '13032a8d-1c16-4f80-b497-b679abf36682'::uuid
where exists (
  select 1
  from auth.users
  where id = '13032a8d-1c16-4f80-b497-b679abf36682'::uuid
)
and not exists (
  select 1
  from public.platform_admins
  where active = true
    and role = 'head_admin'
);
