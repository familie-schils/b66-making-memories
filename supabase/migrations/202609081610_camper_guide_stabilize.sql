-- Campergids stabilisatie voor omgevingen waar tijdelijk een alternatief model is gebruikt.

do $$
declare
  legacy_table_name text := 'public.' || quote_ident('camper_guide_topics' || '_v2');
  legacy_exists boolean := false;
  legacy_row record;
  mapped_topic_id bigint;
begin
  legacy_exists := to_regclass(legacy_table_name) is not null;
  if not legacy_exists then
    return;
  end if;

  create temp table if not exists _camper_guide_legacy_map (
    legacy_id bigint primary key,
    topic_id bigint not null
  ) on commit drop;

  for legacy_row in execute format(
    'select id, legacy_topic_id, camper_id, title, category, explanation, created_at, created_by, updated_at, updated_by, photos
     from %s
     order by id',
    legacy_table_name
  )
  loop
    mapped_topic_id := null;

    if legacy_row.legacy_topic_id is not null and exists (
      select 1
      from public.camper_guide_topics
      where id = legacy_row.legacy_topic_id
    ) then
      update public.camper_guide_topics
      set camper_id = legacy_row.camper_id,
          title = legacy_row.title,
          category = legacy_row.category,
          explanation = legacy_row.explanation,
          updated_at = legacy_row.updated_at,
          updated_by = legacy_row.updated_by
      where id = legacy_row.legacy_topic_id;

      mapped_topic_id := legacy_row.legacy_topic_id;
    else
      insert into public.camper_guide_topics (
        camper_id,
        title,
        category,
        explanation,
        created_at,
        created_by,
        updated_at,
        updated_by
      )
      values (
        legacy_row.camper_id,
        legacy_row.title,
        legacy_row.category,
        legacy_row.explanation,
        legacy_row.created_at,
        legacy_row.created_by,
        legacy_row.updated_at,
        legacy_row.updated_by
      )
      returning id into mapped_topic_id;
    end if;

    insert into _camper_guide_legacy_map (legacy_id, topic_id)
    values (legacy_row.id, mapped_topic_id)
    on conflict (legacy_id) do update set topic_id = excluded.topic_id;
  end loop;

  delete from public.camper_guide_topic_photos photos
  using _camper_guide_legacy_map topic_map
  where photos.topic_id = topic_map.topic_id;

  execute format(
    'insert into public.camper_guide_topic_photos (topic_id, storage_path, caption, sort_order, created_at, created_by)
     select
       topic_map.topic_id,
       nullif(btrim(photo_item.value->>''storage_path''), '''') as storage_path,
       nullif(btrim(photo_item.value->>''caption''), '''') as caption,
       photo_item.ordinality - 1 as sort_order,
       legacy_topics.created_at,
       legacy_topics.created_by
     from %s legacy_topics
     join _camper_guide_legacy_map topic_map on topic_map.legacy_id = legacy_topics.id
     cross join lateral jsonb_array_elements(coalesce(legacy_topics.photos, ''[]''::jsonb)) with ordinality as photo_item(value, ordinality)
     where nullif(btrim(photo_item.value->>''storage_path''), '''') is not null',
    legacy_table_name
  );

  perform setval(
    pg_get_serial_sequence('public.camper_guide_topics','id'),
    greatest(coalesce((select max(id) from public.camper_guide_topics),0),1),
    true
  );

  execute format('drop table if exists %s cascade', legacy_table_name);
end
$$;

drop policy if exists camper_guide_topics_insert_policy on public.camper_guide_topics;
create policy camper_guide_topics_insert_policy
on public.camper_guide_topics
for insert
with check (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_users cu
    where cu.camper_id = camper_guide_topics.camper_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
);

drop policy if exists camper_guide_topics_update_policy on public.camper_guide_topics;
create policy camper_guide_topics_update_policy
on public.camper_guide_topics
for update
using (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_users cu
    where cu.camper_id = camper_guide_topics.camper_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
)
with check (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_users cu
    where cu.camper_id = camper_guide_topics.camper_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
);

drop policy if exists camper_guide_topics_delete_policy on public.camper_guide_topics;
create policy camper_guide_topics_delete_policy
on public.camper_guide_topics
for delete
using (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_users cu
    where cu.camper_id = camper_guide_topics.camper_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
);

drop policy if exists camper_guide_topic_photos_insert_policy on public.camper_guide_topic_photos;
create policy camper_guide_topic_photos_insert_policy
on public.camper_guide_topic_photos
for insert
with check (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_guide_topics t
    join public.camper_users cu on cu.camper_id = t.camper_id
    where t.id = camper_guide_topic_photos.topic_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
);

drop policy if exists camper_guide_topic_photos_update_policy on public.camper_guide_topic_photos;
create policy camper_guide_topic_photos_update_policy
on public.camper_guide_topic_photos
for update
using (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_guide_topics t
    join public.camper_users cu on cu.camper_id = t.camper_id
    where t.id = camper_guide_topic_photos.topic_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
)
with check (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_guide_topics t
    join public.camper_users cu on cu.camper_id = t.camper_id
    where t.id = camper_guide_topic_photos.topic_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
);

drop policy if exists camper_guide_topic_photos_delete_policy on public.camper_guide_topic_photos;
create policy camper_guide_topic_photos_delete_policy
on public.camper_guide_topic_photos
for delete
using (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_guide_topics t
    join public.camper_users cu on cu.camper_id = t.camper_id
    where t.id = camper_guide_topic_photos.topic_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
);
