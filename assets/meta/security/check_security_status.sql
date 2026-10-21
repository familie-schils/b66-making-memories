-- Making Memories — live RLS-status (read-only)
-- Doel: in de Supabase SQL Editor in één keer queries 1 t/m 4 uitvoeren.
-- Wijzigt geen data, policies of grants. Alleen SELECT op catalogus-views.
--
-- Prioriteitstabellen (ORCHESTRATOR.md):
--   reizen, tankbeurten, reis_stops, reiskosten, fotos, campers, friend_requests

-- =============================================================================
-- Query 1 — Bestaat de tabel, staat RLS aan, is RLS forced?
-- =============================================================================
select
  expected.table_name,
  (to_regclass('public.' || expected.table_name) is not null) as table_exists,
  coalesce(c.relrowsecurity, false) as rls_enabled,
  coalesce(c.relforcerowsecurity, false) as rls_forced
from (
  values
    ('reizen'),
    ('tankbeurten'),
    ('reis_stops'),
    ('reiskosten'),
    ('fotos'),
    ('campers'),
    ('friend_requests')
) as expected(table_name)
left join pg_class c
  on c.oid = to_regclass('public.' || expected.table_name)
left join pg_namespace n
  on n.oid = c.relnamespace
 and n.nspname = 'public'
order by expected.table_name;

-- =============================================================================
-- Query 2 — Actieve RLS-policies (naam, commando, rollen, using / with check)
-- =============================================================================
select
  expected.table_name,
  p.policyname,
  p.permissive,
  p.roles,
  p.cmd,
  p.qual as using_expression,
  p.with_check as with_check_expression
from (
  values
    ('reizen'),
    ('tankbeurten'),
    ('reis_stops'),
    ('reiskosten'),
    ('fotos'),
    ('campers'),
    ('friend_requests')
) as expected(table_name)
left join pg_policies p
  on p.schemaname = 'public'
 and p.tablename = expected.table_name
order by expected.table_name, p.cmd nulls first, p.policyname;

-- =============================================================================
-- Query 3 — Table grants voor anon / authenticated / public
-- =============================================================================
select
  expected.table_name,
  g.grantee,
  g.privilege_type
from (
  values
    ('reizen'),
    ('tankbeurten'),
    ('reis_stops'),
    ('reiskosten'),
    ('fotos'),
    ('campers'),
    ('friend_requests')
) as expected(table_name)
left join information_schema.role_table_grants g
  on g.table_schema = 'public'
 and g.table_name = expected.table_name
 and g.grantee in ('anon', 'authenticated', 'public')
order by expected.table_name, g.grantee, g.privilege_type;

-- =============================================================================
-- Query 4 — Dekkingsmatrix: per tabel × commando hoeveel policies?
--           0 = gat (geen policy voor dat commando, ook geen ALL)
-- =============================================================================
with expected_tables as (
  select * from (
    values
      ('reizen'),
      ('tankbeurten'),
      ('reis_stops'),
      ('reiskosten'),
      ('fotos'),
      ('campers'),
      ('friend_requests')
  ) as t(table_name)
),
expected_cmds as (
  select * from (
    values
      ('SELECT'),
      ('INSERT'),
      ('UPDATE'),
      ('DELETE')
  ) as c(cmd)
)
select
  t.table_name,
  c.cmd,
  count(p.policyname) as policy_count,
  bool_or(p.cmd = 'ALL') as has_all_policy,
  coalesce(cls.relrowsecurity, false) as rls_enabled
from expected_tables t
cross join expected_cmds c
left join pg_class cls
  on cls.oid = to_regclass('public.' || t.table_name)
left join pg_policies p
  on p.schemaname = 'public'
 and p.tablename = t.table_name
 and p.cmd in (c.cmd, 'ALL')
group by t.table_name, c.cmd, cls.relrowsecurity
order by t.table_name, c.cmd;
