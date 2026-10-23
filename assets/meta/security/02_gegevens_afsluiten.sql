-- =====================================================================
-- B66 – Making Memories: DEEL 2 – lezen, toevoegen en wijzigen afsluiten
-- Uitvoeren in: Supabase SQL Editor. Draai dit NA deel 1.
--
-- Afspraken (besluiten van de Lead-Developer, 2026-10-23):
--   * LEZEN: alleen leden van de camper (elke rol, ook viewer).
--     Uitzondering: vrienden zien alleen stops met 'delen met vrienden'
--     aan (en de reis en foto's die daarbij horen).
--   * TOEVOEGEN en WIJZIGEN: admin, editor en lid. Een viewer kijkt alleen.
--   * VERWIJDEREN: alleen admin en editor (staat al; hier alleen
--     'onderhoud' erbij, die had mogelijk een open regel).
--
-- Wat dit oplost: bij reizen, stops, foto's, tankbeurten, kosten,
-- personen en onderhoud staan nu naast de strenge regels ook regels met
-- 'true'. Daardoor kan elke ingelogde gebruiker via de database alles
-- lezen, toevoegen en (bij personen en tankbeurten) wijzigen, ook bij
-- campers waar hij niet bij hoort. Alle bestaande regels voor lezen,
-- toevoegen en wijzigen op deze tabellen worden vervangen.
--
-- Veiligheid van dit script:
--   * Eerst worden de bestaande regels vastgelegd in b66_policy_backup.
--   * Alles zit in een transactie: bij een fout verandert er niets.
--   * Het script wijzigt GEEN gegevens, alleen regels en hulpfuncties.
--   * Veilig om opnieuw te draaien.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Vastlegging van de huidige regels (voor terugdraaien)
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.b66_policy_backup (
  saved_at    timestamptz NOT NULL DEFAULT now(),
  stap        text,
  schemaname  text,
  tablename   text,
  policyname  text,
  permissive  text,
  roles       text,
  cmd         text,
  qual        text,
  with_check  text
);
ALTER TABLE public.b66_policy_backup ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.b66_policy_backup FROM anon, authenticated;

INSERT INTO public.b66_policy_backup
  (stap, schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check)
SELECT '02', schemaname, tablename, policyname, permissive, roles::text, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('campers','reizen','reis_stops','fotos','tankbeurten',
                    'reiskosten','personen','onderhoud');

-- ---------------------------------------------------------------------
-- 1. Hulpfuncties (SECURITY DEFINER: voorkomen dat regels op reizen en
--    stops elkaar eindeloos aanroepen)
-- ---------------------------------------------------------------------

-- Is de ingelogde gebruiker lid van deze camper (elke rol)?
CREATE OR REPLACE FUNCTION public.b66_is_member(p_camper_id bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.camper_users cu
    WHERE cu.camper_id = p_camper_id AND cu.user_id = auth.uid()
  );
$$;

-- Mag de ingelogde gebruiker gegevens toevoegen/wijzigen? (admin, editor, lid)
CREATE OR REPLACE FUNCTION public.b66_can_write(p_camper_id bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.camper_users cu
    WHERE cu.camper_id = p_camper_id
      AND cu.user_id   = auth.uid()
      AND cu.role IN ('admin', 'editor', 'lid')
  );
$$;

-- Is een lid van deze camper bevriend met de ingelogde gebruiker?
CREATE OR REPLACE FUNCTION public.b66_is_friend_of_camper(p_camper_id bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.camper_users cu
    JOIN public.friends f ON f.friend_user_id = cu.user_id
    WHERE cu.camper_id = p_camper_id
      AND f.user_id    = auth.uid()
  );
$$;

-- Van welke camper is deze reis?
CREATE OR REPLACE FUNCTION public.b66_trip_camper(p_reis_id bigint)
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT r.camper_id FROM public.reizen r WHERE r.id = p_reis_id;
$$;

-- Heeft deze reis minstens een stop die met vrienden gedeeld is?
CREATE OR REPLACE FUNCTION public.b66_trip_has_shared_stop(p_reis_id bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.reis_stops s
    WHERE s.reis_id = p_reis_id AND s.gedeeld_met_vrienden IS TRUE
  );
$$;

-- Van welke camper is deze stop?
CREATE OR REPLACE FUNCTION public.b66_stop_camper(p_stop_id bigint)
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT r.camper_id
  FROM public.reis_stops s
  JOIN public.reizen r ON r.id = s.reis_id
  WHERE s.id = p_stop_id;
$$;

-- Mag de ingelogde gebruiker deze stop (en zijn foto's) zien?
CREATE OR REPLACE FUNCTION public.b66_stop_visible(p_stop_id bigint)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.reis_stops s
    JOIN public.reizen r ON r.id = s.reis_id
    WHERE s.id = p_stop_id
      AND ( public.b66_is_member(r.camper_id)
            OR ( s.gedeeld_met_vrienden IS TRUE
                 AND public.b66_is_friend_of_camper(r.camper_id) ) )
  );
$$;

DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'b66_is_member(bigint)', 'b66_can_write(bigint)',
    'b66_is_friend_of_camper(bigint)', 'b66_trip_camper(bigint)',
    'b66_trip_has_shared_stop(bigint)', 'b66_stop_camper(bigint)',
    'b66_stop_visible(bigint)'
  ] LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION public.%s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%s TO authenticated', f);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 2. Beveiliging (RLS) aan, en alle bestaande regels voor lezen,
--    toevoegen en wijzigen op deze tabellen weghalen. Daarna maken we
--    hieronder per tabel precies de gewenste regels aan.
-- ---------------------------------------------------------------------
DO $$
DECLARE t text; r record;
BEGIN
  FOREACH t IN ARRAY ARRAY['reizen','reis_stops','fotos','tankbeurten',
                           'reiskosten','personen','onderhoud','campers']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR r IN SELECT policyname FROM pg_policies
             WHERE schemaname = 'public' AND tablename = t
               AND cmd IN ('SELECT', 'UPDATE', 'ALL')
    LOOP
      EXECUTE format('DROP POLICY %I ON public.%I', r.policyname, t);
    END LOOP;
    -- INSERT-regels: bij campers regelt deel 1 dat (niet hier weghalen)
    IF t <> 'campers' THEN
      FOR r IN SELECT policyname FROM pg_policies
               WHERE schemaname = 'public' AND tablename = t AND cmd = 'INSERT'
      LOOP
        EXECUTE format('DROP POLICY %I ON public.%I', r.policyname, t);
      END LOOP;
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- 3. campers (lezen: lid of eigenaar; wijzigen: admin/editor/lid)
-- ---------------------------------------------------------------------
CREATE POLICY campers_select ON public.campers
  FOR SELECT TO authenticated
  USING ( public.b66_is_member(id) OR owner_id = auth.uid() );

CREATE POLICY campers_update ON public.campers
  FOR UPDATE TO authenticated
  USING      ( public.b66_can_write(id) )
  WITH CHECK ( public.b66_can_write(id) );

-- ---------------------------------------------------------------------
-- 4. reizen
-- ---------------------------------------------------------------------
CREATE POLICY reizen_select ON public.reizen
  FOR SELECT TO authenticated
  USING (
    public.b66_is_member(camper_id)
    OR ( public.b66_is_friend_of_camper(camper_id)
         AND public.b66_trip_has_shared_stop(id) )
  );

CREATE POLICY reizen_insert ON public.reizen
  FOR INSERT TO authenticated
  WITH CHECK ( public.b66_can_write(camper_id) );

CREATE POLICY reizen_update ON public.reizen
  FOR UPDATE TO authenticated
  USING      ( public.b66_can_write(camper_id) )
  WITH CHECK ( public.b66_can_write(camper_id) );

-- ---------------------------------------------------------------------
-- 5. reis_stops  (camper via de reis)
-- ---------------------------------------------------------------------
CREATE POLICY reis_stops_select ON public.reis_stops
  FOR SELECT TO authenticated
  USING (
    public.b66_is_member(public.b66_trip_camper(reis_id))
    OR ( gedeeld_met_vrienden IS TRUE
         AND public.b66_is_friend_of_camper(public.b66_trip_camper(reis_id)) )
  );

CREATE POLICY reis_stops_insert ON public.reis_stops
  FOR INSERT TO authenticated
  WITH CHECK ( public.b66_can_write(public.b66_trip_camper(reis_id)) );

CREATE POLICY reis_stops_update ON public.reis_stops
  FOR UPDATE TO authenticated
  USING      ( public.b66_can_write(public.b66_trip_camper(reis_id)) )
  WITH CHECK ( public.b66_can_write(public.b66_trip_camper(reis_id)) );

-- ---------------------------------------------------------------------
-- 6. fotos  (camper via de stop; geen UPDATE: de app wijzigt foto's niet)
-- ---------------------------------------------------------------------
CREATE POLICY fotos_select ON public.fotos
  FOR SELECT TO authenticated
  USING ( public.b66_stop_visible(stop_id) );

CREATE POLICY fotos_insert ON public.fotos
  FOR INSERT TO authenticated
  WITH CHECK ( public.b66_can_write(public.b66_stop_camper(stop_id)) );

-- ---------------------------------------------------------------------
-- 7. tankbeurten, reiskosten, personen, onderhoud  (camper_id)
-- ---------------------------------------------------------------------
CREATE POLICY tankbeurten_select ON public.tankbeurten
  FOR SELECT TO authenticated USING ( public.b66_is_member(camper_id) );
CREATE POLICY tankbeurten_insert ON public.tankbeurten
  FOR INSERT TO authenticated WITH CHECK ( public.b66_can_write(camper_id) );
CREATE POLICY tankbeurten_update ON public.tankbeurten
  FOR UPDATE TO authenticated
  USING ( public.b66_can_write(camper_id) ) WITH CHECK ( public.b66_can_write(camper_id) );

CREATE POLICY reiskosten_select ON public.reiskosten
  FOR SELECT TO authenticated USING ( public.b66_is_member(camper_id) );
CREATE POLICY reiskosten_insert ON public.reiskosten
  FOR INSERT TO authenticated WITH CHECK ( public.b66_can_write(camper_id) );
CREATE POLICY reiskosten_update ON public.reiskosten
  FOR UPDATE TO authenticated
  USING ( public.b66_can_write(camper_id) ) WITH CHECK ( public.b66_can_write(camper_id) );

CREATE POLICY personen_select ON public.personen
  FOR SELECT TO authenticated USING ( public.b66_is_member(camper_id) );
CREATE POLICY personen_insert ON public.personen
  FOR INSERT TO authenticated WITH CHECK ( public.b66_can_write(camper_id) );
CREATE POLICY personen_update ON public.personen
  FOR UPDATE TO authenticated
  USING ( public.b66_can_write(camper_id) ) WITH CHECK ( public.b66_can_write(camper_id) );

CREATE POLICY onderhoud_select ON public.onderhoud
  FOR SELECT TO authenticated USING ( public.b66_is_member(camper_id) );
CREATE POLICY onderhoud_insert ON public.onderhoud
  FOR INSERT TO authenticated WITH CHECK ( public.b66_can_write(camper_id) );
CREATE POLICY onderhoud_update ON public.onderhoud
  FOR UPDATE TO authenticated
  USING ( public.b66_can_write(camper_id) ) WITH CHECK ( public.b66_can_write(camper_id) );

-- ---------------------------------------------------------------------
-- 8. onderhoud: verwijderen alleen admin/editor (kan een open regel hebben)
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname = 'public' AND tablename = 'onderhoud' AND cmd = 'DELETE'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.onderhoud', r.policyname);
  END LOOP;
END $$;

CREATE POLICY onderhoud_delete ON public.onderhoud
  FOR DELETE TO authenticated
  USING ( public.b66_can_delete_camper(camper_id) );

COMMIT;

-- =====================================================================
-- CONTROLE (los uitvoeren na COMMIT): per tabel en soort het aantal
-- regels. Verwacht: select/insert/update = 1 per tabel (fotos: geen
-- update; campers: geen delete, insert staat in deel 1), delete = 1
-- bij reizen, reis_stops, fotos, tankbeurten, reiskosten, personen en
-- onderhoud.
-- =====================================================================
SELECT tablename, cmd, COUNT(*) AS regels
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('campers','reizen','reis_stops','fotos','tankbeurten',
                    'reiskosten','personen','onderhoud')
GROUP BY tablename, cmd
ORDER BY tablename, cmd;

-- =====================================================================
-- TERUGDRAAIEN (indien nodig): de oude regels staan in b66_policy_backup.
--   select tablename, policyname, cmd, roles, qual, with_check
--   from public.b66_policy_backup where stap = '02' order by saved_at desc;
--   Maak een oude regel opnieuw aan met CREATE POLICY, en haal de nieuwe
--   weg met DROP POLICY. Stuur de uitkomst gerust door, dan schrijf ik
--   het terugdraaiscript.
-- =====================================================================
