-- =====================================================================
-- B66 – Making Memories: DEEL 4 – vrienden en camperleden afsluiten
-- Uitvoeren in: Supabase SQL Editor, NA deel 1, 1b, 2 en 3.
--
-- Wat dit oplost (in gewone taal):
--   1. VRIENDEN. Nu kan iedere ingelogde gebruiker zichzelf als "vriend"
--      van iemand anders toevoegen, zonder verzoek of toestemming. Omdat
--      vrienden de gedeelde stops mogen zien (deel 2), kan iemand zo
--      meekijken bij vreemden. Straks kan een vriendschap alleen ontstaan
--      uit een vriendenverzoek: de ontvanger accepteert, dan worden beide
--      kanten aangemaakt.
--   2. VRIENDENVERZOEKEN. Nu kan iemand een verzoek direct als
--      "geaccepteerd" aanmaken, of de ontvanger/afzender in een verzoek
--      wijzigen. Straks kan een nieuw verzoek alleen 'in afwachting' zijn,
--      en kunnen afzender en ontvanger niet meer worden gewijzigd. Alleen
--      de ontvanger kan accepteren of afwijzen; de afzender kan een
--      afgewezen verzoek opnieuw versturen.
--   3. VRIEND VERWIJDEREN. Nu verwijdert de een alleen zijn eigen kant;
--      de ander blijft daardoor nog meekijken. Straks mag elk van beiden
--      beide kanten verwijderen.
--   4. CAMPERLEDEN. Nu ziet een admin alleen zichzelf in de ledenlijst en
--      kan hij leden niet wijzigen of verwijderen. Straks: leden van een
--      camper zien elkaar, en een admin kan de rol van anderen wijzigen
--      (viewer, editor of lid, niet admin) en anderen verwijderen, maar
--      niet zichzelf.
--
-- Veiligheid: alleen regels en hulpfuncties, geen gegevens. De huidige
-- regels worden eerst vastgelegd in b66_policy_backup (stap 04).
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
SELECT '04', schemaname, tablename, policyname, permissive, roles::text, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('friends', 'friend_requests', 'camper_users');

DO $$
BEGIN
  IF to_regprocedure('public.b66_is_member(bigint)') IS NULL THEN
    RAISE EXCEPTION 'Draai eerst deel 2 (02_gegevens_afsluiten.sql): b66_is_member bestaat nog niet';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 0. Hulpfunctie: is de ingelogde gebruiker admin van deze camper?
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.b66_is_admin(p_camper_id bigint)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.camper_users cu
    WHERE cu.camper_id = p_camper_id
      AND cu.user_id   = auth.uid()
      AND cu.role      = 'admin'
  );
$$;
REVOKE ALL ON FUNCTION public.b66_is_admin(bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.b66_is_admin(bigint) TO authenticated;

-- ---------------------------------------------------------------------
-- 1. friend_requests
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname='public' AND tablename='friend_requests' AND cmd IN ('INSERT','UPDATE','ALL')
  LOOP
    EXECUTE format('DROP POLICY %I ON public.friend_requests', r.policyname);
  END LOOP;
END $$;

-- Een nieuw verzoek: van jezelf, naar een ander, altijd 'pending'.
CREATE POLICY friend_requests_insert ON public.friend_requests
  FOR INSERT TO authenticated
  WITH CHECK (
    requester_user_id = auth.uid()
    AND recipient_user_id <> auth.uid()
    AND status = 'pending'
  );

-- Wijzigen: alleen als je zelf afzender of ontvanger bent; wat precies,
-- bewaakt de trigger hieronder.
CREATE POLICY friend_requests_update ON public.friend_requests
  FOR UPDATE TO authenticated
  USING (auth.uid() IN (requester_user_id, recipient_user_id))
  WITH CHECK (auth.uid() IN (requester_user_id, recipient_user_id));

CREATE OR REPLACE FUNCTION public.b66_friend_requests_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.requester_user_id IS DISTINCT FROM OLD.requester_user_id
     OR NEW.recipient_user_id IS DISTINCT FROM OLD.recipient_user_id THEN
    RAISE EXCEPTION 'Afzender en ontvanger van een vriendenverzoek kunnen niet worden gewijzigd'
      USING ERRCODE = '42501';
  END IF;
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;
  IF auth.uid() = OLD.recipient_user_id THEN
    IF NEW.status IN ('accepted', 'rejected') THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'De ontvanger kan een verzoek alleen accepteren of afwijzen'
      USING ERRCODE = '42501';
  END IF;
  IF auth.uid() = OLD.requester_user_id THEN
    IF NEW.status = 'pending' AND OLD.status = 'rejected' THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'De afzender kan alleen een afgewezen verzoek opnieuw versturen'
      USING ERRCODE = '42501';
  END IF;
  RAISE EXCEPTION 'Niet toegestaan' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS b66_friend_requests_guard ON public.friend_requests;
CREATE TRIGGER b66_friend_requests_guard
  BEFORE UPDATE ON public.friend_requests
  FOR EACH ROW EXECUTE FUNCTION public.b66_friend_requests_guard();

-- ---------------------------------------------------------------------
-- 2. friends: alleen aanmaken vanuit een vriendenverzoek
--    * de ONTVANGER mag beide kanten aanmaken zolang het verzoek loopt
--      of is geaccepteerd (zo werkt de app bij accepteren);
--    * afzender of ontvanger mag ontbrekende kanten herstellen als het
--      verzoek al geaccepteerd is.
--    Verwijderen: elk van beiden, beide kanten.
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname='public' AND tablename='friends' AND cmd IN ('INSERT','DELETE','ALL')
  LOOP
    EXECUTE format('DROP POLICY %I ON public.friends', r.policyname);
  END LOOP;
END $$;

CREATE POLICY friends_insert ON public.friends
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id <> friend_user_id
    AND EXISTS (
      SELECT 1 FROM public.friend_requests fr
      WHERE (
              (fr.requester_user_id = friends.user_id AND fr.recipient_user_id = friends.friend_user_id)
           OR (fr.requester_user_id = friends.friend_user_id AND fr.recipient_user_id = friends.user_id)
            )
        AND (
              (fr.status = 'pending'  AND fr.recipient_user_id = auth.uid())
           OR (fr.status = 'accepted' AND auth.uid() IN (fr.requester_user_id, fr.recipient_user_id))
            )
    )
  );

CREATE POLICY friends_delete ON public.friends
  FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR friend_user_id = auth.uid());

-- ---------------------------------------------------------------------
-- 3. camper_users: ledenlijst, rol wijzigen, lid verwijderen
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname='public' AND tablename='camper_users' AND cmd IN ('SELECT','UPDATE','DELETE','ALL')
  LOOP
    EXECUTE format('DROP POLICY %I ON public.camper_users', r.policyname);
  END LOOP;
END $$;

CREATE POLICY camper_users_select ON public.camper_users
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.b66_is_member(camper_id)
    OR EXISTS (
         SELECT 1 FROM public.friends f
         WHERE f.user_id = auth.uid() AND f.friend_user_id = camper_users.user_id
       )
  );

CREATE POLICY camper_users_update ON public.camper_users
  FOR UPDATE TO authenticated
  USING (public.b66_is_admin(camper_id) AND user_id <> auth.uid())
  WITH CHECK (
    public.b66_is_admin(camper_id)
    AND user_id <> auth.uid()
    AND role IN ('viewer', 'editor', 'lid')
  );

CREATE POLICY camper_users_delete ON public.camper_users
  FOR DELETE TO authenticated
  USING (public.b66_is_admin(camper_id) AND user_id <> auth.uid());

COMMIT;

-- =====================================================================
-- CONTROLE (los uitvoeren): verwacht per tabel/actie precies 1 regel,
-- behalve friends SELECT (1) en camper_users INSERT (1).
-- =====================================================================
SELECT tablename, cmd, count(*) AS regels
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('friends', 'friend_requests', 'camper_users')
GROUP BY tablename, cmd
ORDER BY tablename, cmd;

-- TERUGDRAAIEN: oude regels staan in b66_policy_backup (stap = '04').
--   De trigger verwijder je met:
--     DROP TRIGGER b66_friend_requests_guard ON public.friend_requests;
