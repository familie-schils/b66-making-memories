-- =====================================================================
-- B66 – Making Memories: DEEL 6a – foto-opslag: lees- en verwijderregels
-- Uitvoeren in: Supabase SQL Editor, NA deel 1 t/m 4 (deel 5, profielen, mag ervoor of erna).
-- Mag VOOR de nieuwe app-versie: de huidige app blijft gewoon werken.
--
-- Het probleem in gewone taal:
--   * Er is alleen een regel om foto's te UPLOADEN. Verwijderen mag niemand,
--     dus "foto verwijderen" in de app laat het bestand gewoon staan.
--     Gevolg (live, 2026-10-24): 53 van de 90 bestanden (87 MB) horen
--     nergens meer bij.
--   * Er is geen maximum bestandsgrootte (grootste bestand: 14 MB).
--   * Er is geen leesregel: de app kan dus geen tijdelijke, beveiligde
--     links maken (nodig voordat de bucket privé kan, zie deel 6b).
--
-- Wat dit script doet:
--   1. Hulpfuncties die bij een bestand de camper vinden en zeggen of jij
--      het mag zien. Ze werken voor oude bestanden (in de hoofdmap, via
--      fotos.url) en voor nieuwe (stops/<camper>/..., camper-uitleg/<camper>/...).
--   2. Leesregel: leden van de camper, vrienden bij gedeelde stops,
--      hoofdbeheerder, en wie het bestand zelf heeft geüpload.
--   3. Verwijderregel: admin of editor van de camper, hoofdbeheerder, of
--      degene die het bestand zelf heeft geüpload.
--   4. Bucket: maximaal 5 MB per bestand, alleen jpg/png/webp.
--      (De oude app maakt foto's van maximaal 3 MB, die blijft dus werken.)
--
-- NIET in dit script (zie 06b, pas NA de nieuwe app op main):
--   uploadregel aanscherpen, bucket privé, limiet naar 1 MB.
--
-- Veiligheid: alleen regels, hulpfuncties en bucket-instellingen; geen
-- gegevens en geen bestanden. Bestaande storage-regels eerst naar
-- b66_policy_backup (stap 06a). Eén transactie, veilig om opnieuw te draaien.
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
SELECT '06a', schemaname, tablename, policyname, permissive, roles::text, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects';

DO $$
BEGIN
  IF to_regprocedure('public.b66_stop_visible(bigint)') IS NULL
     OR to_regprocedure('public.b66_can_delete_camper(bigint)') IS NULL
     OR to_regprocedure('public.b66_is_member(bigint)') IS NULL THEN
    RAISE EXCEPTION 'Draai eerst deel 2 en het delete-script: hulpfuncties ontbreken';
  END IF;
END $$;

-- ---------------------------------------------------------------------
-- 1. Hulpfuncties
-- ---------------------------------------------------------------------

-- Hoofdbeheerder van het platform (werkt ook als platform_admins ontbreekt).
CREATE OR REPLACE FUNCTION public.b66_is_head_admin()
RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.platform_admins pa
    WHERE pa.user_id = auth.uid() AND pa.active = true AND pa.role = 'head_admin'
  );
EXCEPTION WHEN undefined_table THEN
  RETURN false;
END;
$$;

-- Camper uit het pad: stops/<camper>/... of camper-uitleg/<camper>/...
CREATE OR REPLACE FUNCTION public.b66_path_camper(p_name text)
RETURNS bigint
LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$
  SELECT CASE
    WHEN split_part(p_name, '/', 1) IN ('stops', 'camper-uitleg')
     AND split_part(p_name, '/', 2) ~ '^[0-9]{1,18}$'
     AND split_part(p_name, '/', 3) <> ''
    THEN split_part(p_name, '/', 2)::bigint
  END;
$$;

-- Stop-id bij een bestand (via fotos.url, die eindigt op /fotos/<pad>).
CREATE OR REPLACE FUNCTION public.b66_photo_stop(p_name text)
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT f.stop_id
  FROM public.fotos f
  WHERE f.url LIKE '%/fotos/%'
    AND right(f.url, length(p_name) + 7) = '/fotos/' || p_name
  ORDER BY f.id
  LIMIT 1;
$$;

-- Camper bij een bestand: eerst uit het pad, anders via fotos of de campergids.
CREATE OR REPLACE FUNCTION public.b66_photo_camper(p_name text)
RETURNS bigint
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    public.b66_path_camper(p_name),
    public.b66_stop_camper(public.b66_photo_stop(p_name)),
    (SELECT t.camper_id
       FROM public.camper_guide_topic_photos g
       JOIN public.camper_guide_topics t ON t.id = g.topic_id
      WHERE g.storage_path = p_name
      LIMIT 1)
  );
$$;

-- Mag de ingelogde gebruiker dit bestand zien?
CREATE OR REPLACE FUNCTION public.b66_photo_visible(p_name text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.b66_is_head_admin()
    -- stopfoto: zelfde regel als de tabel fotos (leden, vrienden bij gedeelde stop)
    OR COALESCE(public.b66_stop_visible(public.b66_photo_stop(p_name)), false)
    -- alle andere bestanden van een camper (nieuw pad of campergids): alleen leden
    OR COALESCE(public.b66_is_member(public.b66_photo_camper(p_name)), false);
$$;

REVOKE ALL ON FUNCTION public.b66_is_head_admin()        FROM public, anon;
REVOKE ALL ON FUNCTION public.b66_path_camper(text)      FROM public, anon;
REVOKE ALL ON FUNCTION public.b66_photo_stop(text)       FROM public, anon;
REVOKE ALL ON FUNCTION public.b66_photo_camper(text)     FROM public, anon;
REVOKE ALL ON FUNCTION public.b66_photo_visible(text)    FROM public, anon;
GRANT EXECUTE ON FUNCTION public.b66_is_head_admin()     TO authenticated;
GRANT EXECUTE ON FUNCTION public.b66_path_camper(text)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.b66_photo_stop(text)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.b66_photo_camper(text)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.b66_photo_visible(text) TO authenticated;

-- ---------------------------------------------------------------------
-- 2 en 3. Lees- en verwijderregels op storage.objects (alleen bucket fotos)
-- ---------------------------------------------------------------------
DROP POLICY IF EXISTS b66_fotos_select ON storage.objects;
DROP POLICY IF EXISTS b66_fotos_delete ON storage.objects;

CREATE POLICY b66_fotos_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'fotos'
    AND (owner_id = auth.uid()::text OR public.b66_photo_visible(name))
  );

CREATE POLICY b66_fotos_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'fotos'
    AND (
      owner_id = auth.uid()::text
      OR COALESCE(public.b66_can_delete_camper(public.b66_photo_camper(name)), false)
    )
  );

-- ---------------------------------------------------------------------
-- 4. Bucket-instellingen (blijft voorlopig openbaar, zie 06b)
-- ---------------------------------------------------------------------
UPDATE storage.buckets
SET file_size_limit    = 5 * 1024 * 1024,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
WHERE id = 'fotos';

COMMIT;

-- =====================================================================
-- CONTROLE (los uitvoeren)
-- =====================================================================
-- SELECT policyname, cmd, roles, qual, with_check
-- FROM pg_policies WHERE schemaname = 'storage' AND tablename = 'objects';
-- verwacht: b66_fotos_select (SELECT), b66_fotos_delete (DELETE) en de
-- bestaande uploadregel "authenticated-upload 1m4ctr_0" (INSERT).
--
-- SELECT id, public, file_size_limit, allowed_mime_types FROM storage.buckets;
-- verwacht: fotos | true | 5242880 | {image/jpeg,image/png,image/webp}

-- =====================================================================
-- OPRUIMEN: bestanden die nergens bij horen (alleen lezen)
-- Verwijderen kan NIET met SQL (Supabase blokkeert dat). Gebruik
-- Storage > fotos in het dashboard en verwijder de bestanden uit deze lijst.
-- =====================================================================
-- SELECT o.name, pg_size_pretty((o.metadata->>'size')::bigint) AS grootte, o.created_at
-- FROM storage.objects o
-- WHERE o.bucket_id = 'fotos'
--   AND public.b66_photo_stop(o.name) IS NULL
--   AND NOT EXISTS (SELECT 1 FROM public.camper_guide_topic_photos g WHERE g.storage_path = o.name)
--   AND o.created_at < now() - interval '1 day'
-- ORDER BY o.created_at;
