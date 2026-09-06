create table if not exists public.system_settings (
  id smallint primary key default 1 check (id = 1),
  db_limit_mb numeric(12,2) not null default 500 check (db_limit_mb > 0),
  storage_limit_gb numeric(12,2) not null default 5 check (storage_limit_gb > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

insert into public.system_settings (id, db_limit_mb, storage_limit_gb, updated_by)
values (1, 500, 5, auth.uid())
on conflict (id) do nothing;

alter table public.system_settings enable row level security;

drop policy if exists system_settings_select_policy on public.system_settings;
create policy system_settings_select_policy
on public.system_settings
for select
to authenticated
using (public.is_head_admin(auth.uid()));

drop policy if exists system_settings_insert_policy on public.system_settings;
create policy system_settings_insert_policy
on public.system_settings
for insert
to authenticated
with check (public.is_head_admin(auth.uid()));

drop policy if exists system_settings_update_policy on public.system_settings;
create policy system_settings_update_policy
on public.system_settings
for update
to authenticated
using (public.is_head_admin(auth.uid()))
with check (public.is_head_admin(auth.uid()));

revoke all on public.system_settings from anon;
revoke all on public.system_settings from authenticated;
grant select, insert, update on public.system_settings to authenticated;

create or replace function public.upsert_system_settings(
  p_db_limit_mb numeric,
  p_storage_limit_gb numeric
)
returns table(id smallint, db_limit_mb numeric, storage_limit_gb numeric, updated_at timestamptz, updated_by uuid)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_head_admin(auth.uid()) then
    raise exception 'Forbidden: head admin role required' using errcode = '42501';
  end if;

  if p_db_limit_mb is null or p_db_limit_mb <= 0 then
    raise exception 'Database limiet moet groter zijn dan 0 MB';
  end if;

  if p_storage_limit_gb is null or p_storage_limit_gb <= 0 then
    raise exception 'Storage limiet moet groter zijn dan 0 GB';
  end if;

  insert into public.system_settings (id, db_limit_mb, storage_limit_gb, updated_at, updated_by)
  values (1, p_db_limit_mb, p_storage_limit_gb, now(), auth.uid())
  on conflict (id) do update
  set
    db_limit_mb = excluded.db_limit_mb,
    storage_limit_gb = excluded.storage_limit_gb,
    updated_at = now(),
    updated_by = auth.uid();

  return query
  select ss.id, ss.db_limit_mb, ss.storage_limit_gb, ss.updated_at, ss.updated_by
  from public.system_settings ss
  where ss.id = 1;
end;
$$;

revoke all on function public.upsert_system_settings(numeric, numeric) from public;
revoke all on function public.upsert_system_settings(numeric, numeric) from anon;
grant execute on function public.upsert_system_settings(numeric, numeric) to authenticated;
grant execute on function public.upsert_system_settings(numeric, numeric) to service_role;

create or replace function public.get_system_storage_metrics()
returns table(db_used_bytes bigint, photo_used_bytes bigint)
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if not public.is_head_admin(auth.uid()) then
    raise exception 'Forbidden: head admin role required' using errcode = '42501';
  end if;

  return query
  select
    pg_database_size(current_database())::bigint as db_used_bytes,
    coalesce((
      select sum(
        case
          when coalesce(o.metadata->>'size', '') ~ '^[0-9]+$' then (o.metadata->>'size')::bigint
          else 0
        end
      )
      from storage.objects o
      where o.bucket_id = 'fotos'
    ), 0)::bigint as photo_used_bytes;
end;
$$;

revoke all on function public.get_system_storage_metrics() from public;
revoke all on function public.get_system_storage_metrics() from anon;
grant execute on function public.get_system_storage_metrics() to authenticated;
grant execute on function public.get_system_storage_metrics() to service_role;
