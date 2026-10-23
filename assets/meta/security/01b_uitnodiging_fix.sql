-- =====================================================================
-- B66 – Making Memories: DEEL 1b – herstel "Uitnodiging afronden mislukt"
-- Uitvoeren in: Supabase SQL Editor, NA deel 1 (01_koppelen_afsluiten.sql).
--
-- Het probleem in gewone taal:
--   De oude regel "invitations_update" vergelijkt het e-mailadres van de
--   uitnodiging met het adres in de verborgen login-tabel (auth.users).
--   Die tabel mag een gewone ingelogde gebruiker NIET lezen (dat is goed
--   zo). Daardoor krijgt hij "permission denied for table users" zodra
--   hij een uitnodiging wil bijwerken.
--
-- De oplossing:
--   Dezelfde regel, maar dan via de hulpfunctie b66_my_email() uit deel 1.
--   Die functie mag de login-tabel wél lezen en geeft alleen jouw eigen
--   e-mailadres terug. Wie wat mag wijzigen blijft hetzelfde:
--     * een admin van de camper mag de uitnodiging wijzigen;
--     * de uitgenodigde mag alleen de status op 'accepted' zetten
--       (dat bewaakt de beveiliging uit deel 1 al).
--
-- Veiligheid: alleen deze ene regel wordt vervangen, geen gegevens.
-- Alles in één transactie, veilig om opnieuw te draaien.
-- =====================================================================

BEGIN;

-- Vastleggen van de huidige regels op invitations (voor terugdraaien)
CREATE TABLE IF NOT EXISTS public.b66_policy_backup (
  saved_at timestamptz NOT NULL DEFAULT now(), stap text, schemaname text,
  tablename text, policyname text, permissive text, roles text, cmd text,
  qual text, with_check text
);
ALTER TABLE public.b66_policy_backup ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.b66_policy_backup FROM anon, authenticated;

INSERT INTO public.b66_policy_backup
  (stap, schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check)
SELECT '01b', schemaname, tablename, policyname, permissive, roles::text, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'invitations';

-- Controle: de hulpfunctie uit deel 1 moet bestaan
DO $$
BEGIN
  IF to_regprocedure('public.b66_my_email()') IS NULL THEN
    RAISE EXCEPTION 'Draai eerst deel 1 (01_koppelen_afsluiten.sql): b66_my_email() bestaat nog niet';
  END IF;
END $$;

-- Vervang de UPDATE-regel
DROP POLICY IF EXISTS invitations_update ON public.invitations;

CREATE POLICY invitations_update ON public.invitations
  FOR UPDATE TO authenticated
  USING (
    camper_id IN (
      SELECT cu.camper_id FROM public.camper_users cu
      WHERE cu.user_id = auth.uid() AND cu.role = 'admin'
    )
    OR lower(email) = public.b66_my_email()
  );

COMMIT;

-- =====================================================================
-- CONTROLE 1 (los uitvoeren): geen enkele regel mag nog rechtstreeks
-- in de login-tabel kijken. Verwacht: GEEN rijen.
-- =====================================================================
SELECT tablename, policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND (qual ILIKE '%auth.users%' OR with_check ILIKE '%auth.users%'
       OR qual ILIKE '%users.email%' OR with_check ILIKE '%users.email%');

-- =====================================================================
-- CONTROLE 2 (los uitvoeren): alle regels op invitations
-- Stuur mij dit resultaat als er nog een fout is.
-- =====================================================================
SELECT policyname, cmd, roles::text AS roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'invitations'
ORDER BY cmd, policyname;

-- TERUGDRAAIEN: oude regel staat in b66_policy_backup (stap = '01b').
