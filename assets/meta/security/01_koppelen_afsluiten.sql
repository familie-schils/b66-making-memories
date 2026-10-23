-- =====================================================================
-- B66 – Making Memories: DEEL 1 – koppelen aan campers afsluiten
-- Uitvoeren in: Supabase SQL Editor. Draai dit VOOR deel 2.
--
-- Wat dit oplost:
--   1. Nu kan elke ingelogde gebruiker zichzelf als admin aan ELKE camper
--      koppelen (de regel op camper_users controleert alleen de eigen
--      gebruikers-ID). Straks mag een koppeling alleen nog:
--        a) door een admin van die camper (andere leden toevoegen);
--        b) door de eigenaar van een NIEUWE camper zonder leden (als admin);
--        c) met een openstaande uitnodiging op het eigen e-mailadres, met
--           precies de rol uit die uitnodiging;
--        d) met een nog niet gebruikte oude camper-uitnodigingscode (rol
--           'lid') die op het eigen e-mailadres is aangemaakt.
--   2. Niet-ingelogde bezoekers (en iedereen) kunnen nu campers aanmaken
--      via vijf ruime regels. Straks blijft er een over: alleen met jezelf
--      als eigenaar. De app maakt campers al zo aan (owner_id = jij).
--   3. Een uitgenodigde kan nu zijn eigen uitnodiging aanpassen, ook de
--      rol. Straks mag hij alleen de status op 'accepted' zetten.
--
-- Veiligheid van dit script:
--   * Eerst worden de bestaande regels vastgelegd in de tabel
--     b66_policy_backup (niet leesbaar via de app), voor terugdraaien.
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
ALTER TABLE public.b66_policy_backup ENABLE ROW LEVEL SECURITY;  -- geen regels = niet leesbaar via de app
REVOKE ALL ON public.b66_policy_backup FROM anon, authenticated;

INSERT INTO public.b66_policy_backup
  (stap, schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check)
SELECT '01', schemaname, tablename, policyname, permissive, roles::text, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('camper_users', 'campers', 'invitations');

-- ---------------------------------------------------------------------
-- 1. Hulpfuncties (SECURITY DEFINER: werken ook als de tabellen zelf
--    strenge regels hebben, en voorkomen dat regels elkaar eindeloos
--    aanroepen)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.b66_my_email()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT lower(u.email) FROM auth.users u WHERE u.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.b66_my_email() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.b66_my_email() TO authenticated;

CREATE OR REPLACE FUNCTION public.b66_may_add_member(
  p_camper_id bigint,
  p_user_id   uuid,
  p_role      text
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN false;
  END IF;

  -- a) een admin van deze camper mag leden toevoegen
  IF EXISTS (
    SELECT 1 FROM public.camper_users cu
    WHERE cu.camper_id = p_camper_id
      AND cu.user_id   = auth.uid()
      AND cu.role      = 'admin'
  ) THEN
    RETURN true;
  END IF;

  -- alle andere paden: alleen jezelf koppelen
  IF p_user_id IS DISTINCT FROM auth.uid() THEN
    RETURN false;
  END IF;

  -- b) eigenaar van een nieuwe camper zonder leden wordt admin
  IF p_role = 'admin'
     AND EXISTS (SELECT 1 FROM public.campers c
                 WHERE c.id = p_camper_id AND c.owner_id = auth.uid())
     AND NOT EXISTS (SELECT 1 FROM public.camper_users cu
                     WHERE cu.camper_id = p_camper_id) THEN
    RETURN true;
  END IF;

  -- c) openstaande, niet verlopen uitnodiging op het eigen e-mailadres,
  --    met precies deze rol
  IF EXISTS (
    SELECT 1 FROM public.invitations i
    WHERE i.camper_id = p_camper_id
      AND lower(i.email) = public.b66_my_email()
      AND i.status     = 'pending'
      AND i.expires_at > now()
      AND i.role       = p_role
  ) THEN
    RETURN true;
  END IF;

  -- d) oude camper-uitnodigingscode (alleen nog voor eerder gedeelde
  --    links): alleen rol 'lid', en alleen op het e-mailadres waarvoor de
  --    code is aangemaakt. Een code zonder e-mailadres geeft geen toegang.
  IF p_role = 'lid' AND EXISTS (
    SELECT 1 FROM public.camper_invites ci
    WHERE ci.camper_id = p_camper_id
      AND COALESCE(ci.used, false) = false
      AND lower(ci.email) = public.b66_my_email()
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;

REVOKE ALL ON FUNCTION public.b66_may_add_member(bigint, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.b66_may_add_member(bigint, uuid, text) TO authenticated;

-- ---------------------------------------------------------------------
-- 2. camper_users: koppelen alleen via een toegestaan pad
--    (alle bestaande INSERT-regels worden vervangen)
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname = 'public' AND tablename = 'camper_users' AND cmd = 'INSERT'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.camper_users', r.policyname);
  END LOOP;
END $$;

CREATE POLICY camper_users_insert ON public.camper_users
  FOR INSERT TO authenticated
  WITH CHECK ( public.b66_may_add_member(camper_id, user_id, role) );

-- ---------------------------------------------------------------------
-- 3. campers: aanmaken alleen met jezelf als eigenaar, alleen ingelogd
--    (verwijdert o.a. test_anon_insert en vier regels met 'true')
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname = 'public' AND tablename = 'campers' AND cmd = 'INSERT'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.campers', r.policyname);
  END LOOP;
END $$;

CREATE POLICY campers_insert_own ON public.campers
  FOR INSERT TO authenticated
  WITH CHECK ( owner_id = auth.uid() );

-- ---------------------------------------------------------------------
-- 4. invitations: een uitgenodigde mag alleen de status op 'accepted'
--    zetten. Een admin van de camper mag alles wijzigen. Zonder
--    ingelogde gebruiker (dashboard / server) geldt geen beperking.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.b66_invitations_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.camper_users cu
    WHERE cu.camper_id = OLD.camper_id
      AND cu.user_id   = auth.uid()
      AND cu.role      = 'admin'
  ) THEN
    RETURN NEW;
  END IF;

  IF NEW.camper_id        IS DISTINCT FROM OLD.camper_id
     OR NEW.email            IS DISTINCT FROM OLD.email
     OR NEW.role             IS DISTINCT FROM OLD.role
     OR NEW.invitation_token IS DISTINCT FROM OLD.invitation_token
     OR NEW.expires_at       IS DISTINCT FROM OLD.expires_at
     OR NEW.created_by       IS DISTINCT FROM OLD.created_by
     OR NEW.created_at       IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'Alleen de status van een uitnodiging mag worden gewijzigd'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status AND NEW.status <> 'accepted' THEN
    RAISE EXCEPTION 'Een uitgenodigde mag een uitnodiging alleen accepteren'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS b66_invitations_guard ON public.invitations;
CREATE TRIGGER b66_invitations_guard
  BEFORE UPDATE ON public.invitations
  FOR EACH ROW EXECUTE FUNCTION public.b66_invitations_guard();

COMMIT;

-- =====================================================================
-- CONTROLE (los uitvoeren na COMMIT):
--   camper_users en campers hebben elk precies 1 INSERT-regel.
-- =====================================================================
SELECT tablename, policyname, cmd, roles::text AS roles, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('camper_users', 'campers')
  AND cmd = 'INSERT'
ORDER BY tablename;

-- =====================================================================
-- TERUGDRAAIEN (indien nodig): de oude regels staan in b66_policy_backup.
--   Bekijk ze met:
--     select tablename, policyname, cmd, roles, qual, with_check
--     from public.b66_policy_backup where stap = '01' order by saved_at desc;
--   Zet een oude regel terug door hem opnieuw aan te maken, bijvoorbeeld:
--     DROP POLICY camper_users_insert ON public.camper_users;
--     CREATE POLICY "authenticated users can create camper link"
--       ON public.camper_users FOR INSERT TO authenticated
--       WITH CHECK (user_id = auth.uid());
--   De trigger verwijder je met:
--     DROP TRIGGER b66_invitations_guard ON public.invitations;
-- =====================================================================
