-- =====================================================================
-- B66 – Making Memories: veilige DELETE-policies (RLS)
-- Uitvoeren in: Supabase SQL Editor (eerst op een test-/staging-project!)
--
-- Principe:
--   * Een gebruiker mag alleen rijen verwijderen van een camper waar hij
--     lid van is via camper_users, met een schrijfrol (admin, editor, lid).
--   * 'viewer' mag NIET verwijderen.
--   * Idempotent: DROP POLICY IF EXISTS + CREATE POLICY; veilig om
--     opnieuw te draaien.
--   * Alles in één transactie: bij een fout (bv. onbekende kolom) wordt
--     er niets doorgevoerd.
--   * Raakt GEEN data; wijzigt alleen policies en één hulpfunctie.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 0. Hulpfunctie: mag de ingelogde gebruiker schrijven op deze camper?
--    SECURITY DEFINER zodat de check ook werkt als camper_users zelf
--    strenge RLS heeft (voorkomt recursie/lege resultaten).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.b66_can_write_camper(p_camper_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.camper_users cu
    WHERE cu.camper_id = p_camper_id
      AND cu.user_id   = auth.uid()
      AND cu.role IN ('admin', 'editor', 'lid')
  );
$$;

REVOKE ALL ON FUNCTION public.b66_can_write_camper(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.b66_can_write_camper(bigint) TO authenticated;

-- Variant: alleen camper-admin (voor gevoelige objecten)
CREATE OR REPLACE FUNCTION public.b66_is_camper_admin(p_camper_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.camper_users cu
    WHERE cu.camper_id = p_camper_id
      AND cu.user_id   = auth.uid()
      AND cu.role      = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION public.b66_is_camper_admin(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.b66_is_camper_admin(bigint) TO authenticated;

-- ---------------------------------------------------------------------
-- 1. reizen  (camper_id)
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS reizen_delete ON public.reizen;
CREATE POLICY reizen_delete ON public.reizen
  FOR DELETE TO authenticated
  USING ( public.b66_can_write_camper(camper_id) );

-- ---------------------------------------------------------------------
-- 2. tankbeurten  (camper_id)
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS tankbeurten_delete ON public.tankbeurten;
CREATE POLICY tankbeurten_delete ON public.tankbeurten
  FOR DELETE TO authenticated
  USING ( public.b66_can_write_camper(camper_id) );

-- ---------------------------------------------------------------------
-- 3. reiskosten  (camper_id + reis_id; de app vult beide)
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS reiskosten_delete ON public.reiskosten;
CREATE POLICY reiskosten_delete ON public.reiskosten
  FOR DELETE TO authenticated
  USING ( public.b66_can_write_camper(camper_id) );

-- ---------------------------------------------------------------------
-- 4. reis_stops  (via reis_id -> reizen.camper_id)
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS reis_stops_delete ON public.reis_stops;
CREATE POLICY reis_stops_delete ON public.reis_stops
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.reizen r
      WHERE r.id = reis_stops.reis_id
        AND public.b66_can_write_camper(r.camper_id)
    )
  );

-- ---------------------------------------------------------------------
-- 5. fotos  (via stop_id -> reis_stops.reis_id -> reizen.camper_id)
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS fotos_delete ON public.fotos;
CREATE POLICY fotos_delete ON public.fotos
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.reis_stops s
      JOIN public.reizen r ON r.id = s.reis_id
      WHERE s.id = fotos.stop_id
        AND public.b66_can_write_camper(r.camper_id)
    )
  );

-- ---------------------------------------------------------------------
-- 6. friend_requests  (alleen betrokken partijen)
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS friend_requests_delete ON public.friend_requests;
CREATE POLICY friend_requests_delete ON public.friend_requests
  FOR DELETE TO authenticated
  USING ( auth.uid() IN (requester_user_id, recipient_user_id) );

-- ---------------------------------------------------------------------
-- 7. Buiten de prioriteitslijst, maar de app verwijdert hier wel rijen
--    (zonder policy faalt dat stil zodra RLS aan staat):
--    - friends   : removeVriend()  -> alleen eigen rij
--    - personen  : persoon verwijderen op camper
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS friends_delete ON public.friends;
CREATE POLICY friends_delete ON public.friends
  FOR DELETE TO authenticated
  USING ( user_id = auth.uid() );

DROP POLICY IF EXISTS personen_delete ON public.personen;
CREATE POLICY personen_delete ON public.personen
  FOR DELETE TO authenticated
  USING ( public.b66_can_write_camper(camper_id) );

-- ---------------------------------------------------------------------
-- 8. campers: BEWUST GEEN DELETE-policy.
--    De app verwijdert nooit een camper, en door ON DELETE CASCADE zou
--    één delete alle reizen, stops en leden meenemen. Zonder policy is
--    verwijderen via de API geblokkeerd (alleen service_role kan het).
--    Wil je het toch toestaan, alleen voor camper-admins:
--
-- DROP POLICY IF EXISTS campers_delete ON public.campers;
-- CREATE POLICY campers_delete ON public.campers
--   FOR DELETE TO authenticated
--   USING ( public.b66_is_camper_admin(id) );
-- ---------------------------------------------------------------------

COMMIT;

-- =====================================================================
-- CONTROLE (los uitvoeren na COMMIT): moeten allemaal policy_count >= 1
-- zijn, behalve campers (bewust 0).
-- =====================================================================
SELECT t.tablename,
       COUNT(p.policyname) AS delete_policies
FROM (VALUES ('reizen'),('tankbeurten'),('reiskosten'),('reis_stops'),
             ('fotos'),('friend_requests'),('friends'),('personen'),
             ('campers')) AS t(tablename)
LEFT JOIN pg_policies p
       ON p.schemaname = 'public'
      AND p.tablename  = t.tablename
      AND p.cmd        = 'DELETE'
GROUP BY t.tablename
ORDER BY t.tablename;

-- =====================================================================
-- TERUGDRAAIEN (indien nodig):
--   DROP POLICY IF EXISTS reizen_delete          ON public.reizen;
--   DROP POLICY IF EXISTS tankbeurten_delete     ON public.tankbeurten;
--   DROP POLICY IF EXISTS reiskosten_delete      ON public.reiskosten;
--   DROP POLICY IF EXISTS reis_stops_delete      ON public.reis_stops;
--   DROP POLICY IF EXISTS fotos_delete           ON public.fotos;
--   DROP POLICY IF EXISTS friend_requests_delete ON public.friend_requests;
--   DROP POLICY IF EXISTS friends_delete         ON public.friends;
--   DROP POLICY IF EXISTS personen_delete        ON public.personen;
--   DROP FUNCTION IF EXISTS public.b66_can_write_camper(bigint);
--   DROP FUNCTION IF EXISTS public.b66_is_camper_admin(bigint);
-- =====================================================================
