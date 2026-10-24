-- =====================================================================
-- B66 – Making Memories: DEEL 5b – foto-opslag privé en uploads afsluiten
-- Uitvoeren in: Supabase SQL Editor, NA deel 5a
-- en PAS NADAT de nieuwe app-versie (test-agent.html met beveiligde
-- foto-links en uploadpad stops/<camper>/...) via main live staat in index.html.
--
-- WAARSCHUWING: draai je dit eerder, dan ziet de oude app geen foto's meer
-- (openbare links werken dan niet) en kan hij geen foto's meer uploaden.
--
-- Het probleem in gewone taal:
--   * De bucket is openbaar: iedereen met een link ziet de foto, ook van
--     stops die niet gedeeld zijn, zonder in te loggen.
--   * Iedere ingelogde gebruiker mag alles in de bucket zetten, waar dan ook.
--
-- Wat dit script doet:
--   1. Uploaden mag alleen nog:
--        stops/<camper>/...          door admin, editor of lid van die camper;
--        camper-uitleg/<camper>/...  door de admin van die camper of de
--                                    hoofdbeheerder (zelfde regel als de gids).
--   2. Bucket privé; de app gebruikt tijdelijke links (1 uur geldig).
--   3. Maximaal 1 MB per bestand (de app maakt nu foto's van ca. 200-400 KB).
--
-- Terugdraaien (als het misgaat):
--   UPDATE storage.buckets SET public = true WHERE id = 'fotos';
--   en de oude uploadregel staat in b66_policy_backup (stap 05b).
--
-- Eén transactie, veilig om opnieuw te draaien.
-- =====================================================================

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.b66_path_camper(text)') IS NULL
     OR to_regprocedure('public.b66_is_head_admin()') IS NULL THEN
    RAISE EXCEPTION 'Draai eerst deel 5a (05a_fotos_regels.sql)';
  END IF;
END $$;

INSERT INTO public.b66_policy_backup
  (stap, schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check)
SELECT '05b', schemaname, tablename, policyname, permissive, roles::text, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects';

-- 1. Alle bestaande uploadregels voor storage.objects vervangen.
--    (Live was dat alleen "authenticated-upload 1m4ctr_0": bucket fotos, verder alles.)
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname = 'storage' AND tablename = 'objects' AND cmd IN ('INSERT', 'ALL')
  LOOP
    EXECUTE format('DROP POLICY %I ON storage.objects', r.policyname);
  END LOOP;
END $$;

CREATE POLICY b66_fotos_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'fotos'
    AND (
      (split_part(name, '/', 1) = 'stops'
        AND COALESCE(public.b66_can_write(public.b66_path_camper(name)), false))
      OR
      (split_part(name, '/', 1) = 'camper-uitleg'
        AND (COALESCE(public.b66_is_camper_admin(public.b66_path_camper(name)), false)
             OR public.b66_is_head_admin()))
    )
  );

-- 2 en 3. Bucket privé, maximaal 1 MB.
UPDATE storage.buckets
SET public             = false,
    file_size_limit    = 1024 * 1024,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'fotos';

COMMIT;

-- =====================================================================
-- CONTROLE (los uitvoeren)
-- =====================================================================
-- SELECT policyname, cmd FROM pg_policies
-- WHERE schemaname = 'storage' AND tablename = 'objects' ORDER BY cmd;
-- verwacht: b66_fotos_delete (DELETE), b66_fotos_insert (INSERT), b66_fotos_select (SELECT)
--
-- SELECT id, public, file_size_limit FROM storage.buckets;
-- verwacht: fotos | false | 1048576
