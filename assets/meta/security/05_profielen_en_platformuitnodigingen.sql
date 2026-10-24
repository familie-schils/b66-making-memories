-- =====================================================================
-- B66 – Making Memories: DEEL 5 – profielen en platformuitnodigingen
-- Uitvoeren in: Supabase SQL Editor, NA deel 1 t/m 4.
--
-- Wat dit oplost (in gewone taal):
--   1. PLATFORMUITNODIGINGEN (tabel invite_codes). Nu kan iedere ingelogde
--      gebruiker zulke uitnodigingen aanmaken en iedereen (ook niet
--      ingelogd) ze lezen. Straks:
--        * aanmaken, lezen en verwijderen: alleen de hoofdbeheerder;
--        * opzoeken op exacte code kan voor iedereen (de uitgenodigde
--          opent de link voordat hij een account heeft), maar alleen
--          die ene code;
--        * de uitgenodigde kan zijn eigen uitnodiging als 'gebruikt'
--          markeren, en niets anders.
--   2. PROFIELEN (tabel profiles). Nu kan iedere ingelogde gebruiker alle
--      namen en e-mailadressen zien. Straks zie je alleen: jezelf, leden
--      van jouw campers, je vrienden, mensen met wie je een vriendenverzoek
--      hebt, en (hoofdbeheerder) iedereen.
--   3. VRIEND ZOEKEN OP E-MAIL. Dat gebeurde via de profielen. Straks via
--      een kleine functie die alleen het gebruikers-ID teruggeeft, voor
--      één exact e-mailadres.
--
-- Veiligheid: alleen regels en functies, geen gegevens. De huidige regels
-- worden eerst vastgelegd in b66_policy_backup (stap 05).
-- Alles in één transactie, veilig om opnieuw te draaien.
-- =====================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.b66_policy_backup (
  saved_at timestamptz NOT NULL DEFAULT now(), stap text, schemaname text,
  tablename text, policyname text, permissive text, roles text, cmd text,
  qual text, with_check text
);
ALTER TABLE public.b66_policy_backup ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.b66_policy_backup FROM anon, authenticated;

INSERT INTO public.b66_policy_backup
  (stap, schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check)
SELECT '05', schemaname, tablename, policyname, permissive, roles::text, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('invite_codes', 'profiles');

DO $$
BEGIN
  IF to_regprocedure('public.b66_my_email()') IS NULL THEN
    RAISE EXCEPTION 'Draai eerst deel 1: b66_my_email() bestaat nog niet';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 0. Hulpfuncties
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.b66_is_head_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.platform_admins pa
    WHERE pa.user_id = auth.uid()
      AND pa.active  = true
      AND pa.role    = 'head_admin'
  );
$$;

-- Mag de ingelogde gebruiker het profiel van deze persoon zien?
CREATE OR REPLACE FUNCTION public.b66_can_see_profile(p_user_id uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT auth.uid() IS NOT NULL AND (
       p_user_id = auth.uid()
    OR public.b66_is_head_admin()
    OR EXISTS (  -- lid van dezelfde camper
         SELECT 1
         FROM public.camper_users a
         JOIN public.camper_users b ON b.camper_id = a.camper_id
         WHERE a.user_id = auth.uid() AND b.user_id = p_user_id
       )
    OR EXISTS (  -- vriend (beide richtingen)
         SELECT 1 FROM public.friends f
         WHERE (f.user_id = auth.uid() AND f.friend_user_id = p_user_id)
            OR (f.friend_user_id = auth.uid() AND f.user_id = p_user_id)
       )
    OR EXISTS (  -- vriendenverzoek tussen jullie
         SELECT 1 FROM public.friend_requests r
         WHERE (r.requester_user_id = auth.uid() AND r.recipient_user_id = p_user_id)
            OR (r.recipient_user_id = auth.uid() AND r.requester_user_id = p_user_id)
       )
  );
$$;

-- Vriend zoeken op exact e-mailadres: geeft alleen het gebruikers-ID.
CREATE OR REPLACE FUNCTION public.b66_find_user_by_email(p_email text)
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.user_id
  FROM public.profiles p
  WHERE auth.uid() IS NOT NULL
    AND p_email IS NOT NULL
    AND length(trim(p_email)) >= 5
    AND lower(p.email) = lower(trim(p_email))
  LIMIT 1;
$$;

-- Platformuitnodiging opzoeken op exacte code (ook voor niet-ingelogd).
CREATE OR REPLACE FUNCTION public.b66_get_platform_invite(p_code text)
RETURNS TABLE (id bigint, email text, invite_code text, used boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT ic.id::bigint, ic.email::text, ic.invite_code::text, COALESCE(ic.used, false)
  FROM public.invite_codes ic
  WHERE p_code IS NOT NULL
    AND length(p_code) >= 8
    AND ic.invite_code = p_code
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.b66_is_head_admin() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.b66_can_see_profile(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.b66_find_user_by_email(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.b66_get_platform_invite(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.b66_is_head_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.b66_can_see_profile(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.b66_find_user_by_email(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.b66_get_platform_invite(text) TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 1. invite_codes
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname='public' AND tablename='invite_codes'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.invite_codes', r.policyname);
  END LOOP;
END $$;

CREATE POLICY invite_codes_select ON public.invite_codes
  FOR SELECT TO authenticated
  USING (public.b66_is_head_admin() OR lower(email) = public.b66_my_email());

CREATE POLICY invite_codes_insert ON public.invite_codes
  FOR INSERT TO authenticated
  WITH CHECK (public.b66_is_head_admin() AND (created_by IS NULL OR created_by = auth.uid()));

CREATE POLICY invite_codes_update ON public.invite_codes
  FOR UPDATE TO authenticated
  USING (public.b66_is_head_admin() OR lower(email) = public.b66_my_email())
  WITH CHECK (public.b66_is_head_admin() OR lower(email) = public.b66_my_email());

CREATE POLICY invite_codes_delete ON public.invite_codes
  FOR DELETE TO authenticated
  USING (public.b66_is_head_admin());

-- De uitgenodigde mag alleen 'gebruikt' invullen, niets anders wijzigen.
CREATE OR REPLACE FUNCTION public.b66_invite_codes_guard()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR public.b66_is_head_admin() THEN
    RETURN NEW;
  END IF;
  IF to_jsonb(NEW) - 'used' - 'used_at' IS DISTINCT FROM to_jsonb(OLD) - 'used' - 'used_at' THEN
    RAISE EXCEPTION 'Alleen de status "gebruikt" van een uitnodiging mag worden gewijzigd'
      USING ERRCODE = '42501';
  END IF;
  IF COALESCE(NEW.used, false) = false AND COALESCE(OLD.used, false) = true THEN
    RAISE EXCEPTION 'Een gebruikte uitnodiging kan niet opnieuw worden geopend'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS b66_invite_codes_guard ON public.invite_codes;
CREATE TRIGGER b66_invite_codes_guard
  BEFORE UPDATE ON public.invite_codes
  FOR EACH ROW EXECUTE FUNCTION public.b66_invite_codes_guard();

-- ---------------------------------------------------------------------
-- 2. profiles: alleen lezen wat je mag zien (invoegen/wijzigen blijft
--    ongewijzigd: alleen je eigen profiel)
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname='public' AND tablename='profiles' AND cmd IN ('SELECT','ALL')
  LOOP
    EXECUTE format('DROP POLICY %I ON public.profiles', r.policyname);
  END LOOP;
END $$;

CREATE POLICY profiles_select ON public.profiles
  FOR SELECT TO authenticated
  USING (public.b66_can_see_profile(user_id));

COMMIT;

-- =====================================================================
-- CONTROLE (los uitvoeren): verwacht
--   invite_codes: DELETE 1, INSERT 1, SELECT 1, UPDATE 1
--   profiles:     INSERT 1, SELECT 1, UPDATE 1
-- =====================================================================
SELECT tablename, cmd, count(*) AS regels
FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('invite_codes', 'profiles')
GROUP BY tablename, cmd
ORDER BY tablename, cmd;

-- TERUGDRAAIEN: oude regels staan in b66_policy_backup (stap = '05').
--   De trigger verwijder je met:
--     DROP TRIGGER b66_invite_codes_guard ON public.invite_codes;
