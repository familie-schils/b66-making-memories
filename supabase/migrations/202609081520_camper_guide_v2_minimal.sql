-- Campergids v2: minimale structuur met foto's als onderdeel van onderwerp.
-- Behoud legacy-tabellen tijdelijk voor rollback/controle, maar zonder schrijfpolicies.

create table if not exists public.camper_guide_topics_v2 (
  id bigint generated always as identity primary key,
  legacy_topic_id bigint unique,
  camper_id bigint not null references public.campers(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  category text not null check (length(trim(category)) > 0),
  explanation text not null default '',
  photos jsonb not null default '[]'::jsonb check (jsonb_typeof(photos) = 'array'),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create index if not exists camper_guide_topics_v2_camper_id_idx
  on public.camper_guide_topics_v2 (camper_id, id);

alter table public.camper_guide_topics_v2 enable row level security;

drop policy if exists camper_guide_topics_v2_select_policy on public.camper_guide_topics_v2;
create policy camper_guide_topics_v2_select_policy
on public.camper_guide_topics_v2
for select
using (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_users cu
    where cu.camper_id = camper_guide_topics_v2.camper_id
      and cu.user_id = auth.uid()
  )
);

drop policy if exists camper_guide_topics_v2_insert_policy on public.camper_guide_topics_v2;
create policy camper_guide_topics_v2_insert_policy
on public.camper_guide_topics_v2
for insert
with check (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_users cu
    where cu.camper_id = camper_guide_topics_v2.camper_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
);

drop policy if exists camper_guide_topics_v2_update_policy on public.camper_guide_topics_v2;
create policy camper_guide_topics_v2_update_policy
on public.camper_guide_topics_v2
for update
using (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_users cu
    where cu.camper_id = camper_guide_topics_v2.camper_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
)
with check (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_users cu
    where cu.camper_id = camper_guide_topics_v2.camper_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
);

drop policy if exists camper_guide_topics_v2_delete_policy on public.camper_guide_topics_v2;
create policy camper_guide_topics_v2_delete_policy
on public.camper_guide_topics_v2
for delete
using (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_users cu
    where cu.camper_id = camper_guide_topics_v2.camper_id
      and cu.user_id = auth.uid()
      and cu.role = 'admin'
  )
);

insert into public.camper_guide_topics_v2 (
  legacy_topic_id,
  camper_id,
  title,
  category,
  explanation,
  photos,
  created_at,
  created_by,
  updated_at,
  updated_by
)
select
  t.id,
  t.camper_id,
  t.title,
  trim(t.category),
  t.explanation,
  coalesce(
    p.photos,
    '[]'::jsonb
  ) as photos,
  t.created_at,
  t.created_by,
  t.updated_at,
  t.updated_by
from public.camper_guide_topics t
left join (
  select
    topic_id,
    jsonb_agg(
      jsonb_build_object(
        'storage_path', storage_path,
        'caption', caption
      )
      order by sort_order, id
    ) as photos
  from public.camper_guide_topic_photos
  group by topic_id
) p on p.topic_id = t.id
where not exists (
  select 1
  from public.camper_guide_topics_v2 v2
  where v2.legacy_topic_id = t.id
);

-- Legacy write-lock: laat bestaande data leesbaar, maar stop nieuwe writes op v1-structuur.
drop policy if exists camper_guide_topics_insert_policy on public.camper_guide_topics;
drop policy if exists camper_guide_topics_update_policy on public.camper_guide_topics;
drop policy if exists camper_guide_topics_delete_policy on public.camper_guide_topics;

drop policy if exists camper_guide_topic_photos_insert_policy on public.camper_guide_topic_photos;
drop policy if exists camper_guide_topic_photos_update_policy on public.camper_guide_topic_photos;
drop policy if exists camper_guide_topic_photos_delete_policy on public.camper_guide_topic_photos;
