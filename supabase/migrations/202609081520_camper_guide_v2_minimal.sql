-- Campergids stabilisatie: behoud het bestaande onderwerpen- en fotomodel.

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
