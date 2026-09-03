DROP POLICY IF EXISTS reiskosten_update ON public.reiskosten;

CREATE POLICY reiskosten_update
ON public.reiskosten
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.camper_users cu
    WHERE cu.camper_id = reiskosten.camper_id
      AND cu.user_id = auth.uid()
      AND cu.role IN ('editor', 'admin')
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.camper_users cu
    WHERE cu.camper_id = reiskosten.camper_id
      AND cu.user_id = auth.uid()
      AND cu.role IN ('editor', 'admin')
  )
);
