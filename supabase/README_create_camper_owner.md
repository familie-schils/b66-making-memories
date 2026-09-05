# Nieuwe Campereigenaar – veilige backend implementatie

## Inhoud

- Migratie: `/home/runner/work/b66-making-memories/b66-making-memories/supabase/migrations/202609050545_create_camper_owner_provisioning.sql`
- Edge Function: `/home/runner/work/b66-making-memories/b66-making-memories/supabase/functions/create-camper-owner/index.ts`
- Frontend aanroep: `/home/runner/work/b66-making-memories/b66-making-memories/test-agent.html`

## Deploy-stappen

1. Voer de migratie uit in Supabase SQL editor.
2. Deploy Edge Function `create-camper-owner`.
3. Zet secret `SUPABASE_SERVICE_ROLE_KEY` in Edge Functions.
4. Zorg dat de function via frontend alleen wordt aangeroepen door ingelogde users.
5. Controleer dat er exact één actieve hoofdadmin in `public.platform_admins` staat.

## Function contract

Input body:

- `email` (verplicht)
- `password` (optioneel)
- `generate_password` (optioneel, boolean)
- `display_name` (optioneel)
- `camper_name` (optioneel)

Output bij succes:

- `status = "ok"`
- `user_id`
- `profile_id`
- `camper_id`
- `generated_password` (alleen wanneer server-side wachtwoordgeneratie gebruikt is)

HTTP fouten:

- `401` unauthenticated
- `403` caller is geen hoofdbeheerder
- `409` email bestaat al
- `422` validatiefout
- `500` provisioningfout

## Testscenario’s

1. Happy flow  
   Hoofdbeheerder maakt eigenaar aan; controleer records in `auth.users`, `profiles`, `campers.owner_id`, `camper_users(role='admin')`.

2. Autorisatie  
   Niet-hoofdbeheerder krijgt `403`; er worden geen records aangemaakt.

3. Duplicaat e-mail  
   Tweede aanvraag met hetzelfde e-mailadres geeft `409`.

4. Transactionele consistentie  
   Forceer fout in `provision_camper_owner_data`; auth user moet gecompenseerd verwijderd worden.

5. Concurrency  
   Twee gelijktijdige aanvragen voor hetzelfde e-mailadres geven exact één succesvolle provisioning.

6. Idempotency  
   Herhaal dezelfde request met dezelfde `x-idempotency-key`; tweede call moet bestaande succesvolle response teruggeven.

7. Auditability  
   Controleer `owner_provision_audit` op `attempt/success/failed` met actor en doelmail.
