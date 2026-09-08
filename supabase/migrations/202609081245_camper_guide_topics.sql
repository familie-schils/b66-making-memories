create table if not exists public.camper_guide_topics (
  id bigint generated always as identity primary key,
  camper_id bigint not null references public.campers(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  category text not null check (category in ('Elektriciteit','Water','Koelkast','Toilet','Luifel','Overig')),
  explanation text not null default '',
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

create table if not exists public.camper_guide_topic_photos (
  id bigint generated always as identity primary key,
  topic_id bigint not null references public.camper_guide_topics(id) on delete cascade,
  storage_path text not null,
  caption text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create index if not exists camper_guide_topics_camper_id_idx
  on public.camper_guide_topics (camper_id);

create index if not exists camper_guide_topics_camper_sort_idx
  on public.camper_guide_topics (camper_id, sort_order, id);

create index if not exists camper_guide_topic_photos_topic_id_idx
  on public.camper_guide_topic_photos (topic_id);

alter table public.camper_guide_topics enable row level security;
alter table public.camper_guide_topic_photos enable row level security;

drop policy if exists camper_guide_topics_select_policy on public.camper_guide_topics;
create policy camper_guide_topics_select_policy
on public.camper_guide_topics
for select
using (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_users cu
    where cu.camper_id = camper_guide_topics.camper_id
      and cu.user_id = auth.uid()
      and cu.role in ('admin','editor','member','lid','viewer')
  )
);

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

drop policy if exists camper_guide_topic_photos_select_policy on public.camper_guide_topic_photos;
create policy camper_guide_topic_photos_select_policy
on public.camper_guide_topic_photos
for select
using (
  public.is_head_admin(auth.uid())
  or exists (
    select 1
    from public.camper_guide_topics t
    join public.camper_users cu on cu.camper_id = t.camper_id
    where t.id = camper_guide_topic_photos.topic_id
      and cu.user_id = auth.uid()
      and cu.role in ('admin','editor','member','lid','viewer')
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
