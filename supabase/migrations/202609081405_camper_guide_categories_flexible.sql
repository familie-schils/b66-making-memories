alter table public.camper_guide_topics
  drop constraint if exists camper_guide_topics_category_check;

update public.camper_guide_topics
set category = trim(category)
where category <> trim(category);

alter table public.camper_guide_topics
  add constraint camper_guide_topics_category_check
  check (length(trim(category)) > 0);
