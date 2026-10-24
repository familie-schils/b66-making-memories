-- =====================================================================
-- B66 – Making Memories: DEEL 3 – uitnodigingen afsluiten
-- Uitvoeren in: Supabase SQL Editor, NA deel 1, 1b en 2.
--
-- Het probleem in gewone taal:
--   De regel "invitations_read_by_token" staat op 'true'. Daardoor kan
--   IEDEREEN (ook niet ingelogd) alle uitnodigingen lezen: e-mailadressen,
--   rollen en de geheime codes waarmee je lid van een camper wordt.
--
-- De oplossing:
--   1. Een uitnodiging opzoeken kan alleen nog met de exacte code, via een
--      kleine functie (b66_get_invitation). Zonder code geen overzicht.
--   2. Lezen mag verder alleen:
--        * een admin van de camper (voor het overzicht van zijn uitnodigingen);
--        * de uitgenodigde zelf (alleen zijn eigen uitnodigingen).
--
-- Veiligheid: alleen regels en een hulpfunctie, geen gegevens.
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
SELECT '03', schemaname, tablename, policyname, permissive, roles::text, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'invitations';

DO $$
BEGIN
  IF to_regprocedure('public.b66_my_email()') IS NULL THEN
    RAISE EXCEPTION 'Draai eerst deel 1 (01_koppelen_afsluiten.sql): b66_my_email() bestaat nog niet';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 1. Opzoeken op exacte code (ook voor niet-ingelogde bezoekers, want
--    iemand opent de uitnodigingslink eerst en registreert daarna).
--    Geeft alleen deze ene uitnodiging terug, nooit het aanmaker-ID.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.b66_get_invitation(p_token text)
RETURNS TABLE (
  id uuid,
  camper_id bigint,
  email text,
  role text,
  invitation_token text,
  status text,
  expires_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT i.id, i.camper_id, i.email::text, i.role::text, i.invitation_token::text,
         i.status::text, i.expires_at
  FROM public.invitations i
  WHERE p_token IS NOT NULL
    AND length(p_token) >= 8
    AND i.invitation_token = p_token
    AND i.status NOT IN ('revoked', 'accepted')
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.b66_get_invitation(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.b66_get_invitation(text) TO anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Alle bestaande leesregels op invitations vervangen
-- ---------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname = 'public' AND tablename = 'invitations' AND cmd IN ('SELECT','ALL')
  LOOP
    EXECUTE format('DROP POLICY %I ON public.invitations', r.policyname);
  END LOOP;
END $$;

CREATE POLICY invitations_select ON public.invitations
  FOR SELECT TO authenticated
  USING (
    camper_id IN (
      SELECT cu.camper_id FROM public.camper_users cu
      WHERE cu.user_id = auth.uid() AND cu.role = 'admin'
    )
    OR lower(email) = public.b66_my_email()
  );

COMMIT;

-- =====================================================================
-- CONTROLE 1: er is precies 1 leesregel op invitations, en die bevat
-- geen 'true'. Verwacht: 1 rij, kolom qual is NIET 'true'.
-- =====================================================================
SELECT policyname, cmd, roles::text AS roles, qual
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'invitations' AND cmd = 'SELECT';

-- =====================================================================
-- CONTROLE 2: een andere uitnodiging opzoeken zonder code kan niet.
-- (Als je dit in de SQL Editor draait, ben je 'postgres' en ziet alles;
--  de echte test is in de app.)
-- TERUGDRAAIEN: oude regels staan in b66_policy_backup (stap = '03').
-- =====================================================================
