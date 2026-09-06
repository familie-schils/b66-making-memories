create or replace function public.get_platform_overview()
returns table(
  total_users bigint,
  total_campers bigint,
  total_trips bigint,
  total_stops bigint,
  total_photos bigint,
  total_fuel_entries bigint,
  total_cost_entries bigint,
  latest_camper_name text,
  latest_camper_brand text,
  latest_camper_model text,
  latest_camper_created_at timestamptz,
  latest_photo_uploaded_at timestamptz,
  total_photo_bytes bigint
)
language plpgsql
security definer
set search_path = public, storage
as $$
begin
  if not public.is_head_admin(auth.uid()) then
    raise exception 'Forbidden: head admin role required' using errcode = '42501';
  end if;

  return query
  with latest_camper as (
    select
      c.naam,
      c.merk,
      c.model,
      c.created_at
    from public.campers c
    order by c.created_at desc nulls last, c.id desc
    limit 1
  ),
  photo_metrics as (
    select
      max(o.created_at) as latest_photo_uploaded_at,
      coalesce(sum(
        case
          when coalesce(o.metadata->>'size', '') ~ '^[0-9]+$' then (o.metadata->>'size')::bigint
          else 0
        end
      ), 0)::bigint as total_photo_bytes
    from storage.objects o
    where o.bucket_id = 'fotos'
  )
  select
    (select count(*) from public.profiles)::bigint as total_users,
    (select count(*) from public.campers)::bigint as total_campers,
    (select count(*) from public.reizen)::bigint as total_trips,
    (select count(*) from public.reis_stops)::bigint as total_stops,
    (select count(*) from public.fotos)::bigint as total_photos,
    (select count(*) from public.tankbeurten)::bigint as total_fuel_entries,
    (select count(*) from public.reiskosten)::bigint as total_cost_entries,
    lc.naam::text as latest_camper_name,
    lc.merk::text as latest_camper_brand,
    lc.model::text as latest_camper_model,
    lc.created_at as latest_camper_created_at,
    pm.latest_photo_uploaded_at,
    pm.total_photo_bytes
  from photo_metrics pm
  left join latest_camper lc on true;
end;
$$;

revoke all on function public.get_platform_overview() from public;
revoke all on function public.get_platform_overview() from anon;
grant execute on function public.get_platform_overview() to authenticated;
grant execute on function public.get_platform_overview() to service_role;
