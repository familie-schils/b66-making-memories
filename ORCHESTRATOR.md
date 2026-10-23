# B66 – Making Memories: Orchestrator Command Center

## Actieve Status: Database Beveiliging & Vrienden-Logica Audit

De Orchestrator Agent (AI) en de Lead-Developer hebben het eerste rapport gelezen. De prioriteit ligt bij het beveiligen van de tabellen: reizen, tankbeurten, reis_stops, reiskosten, fotos, campers en friend_requests.

## Opdracht voor de GitHub Agent:

1. Stop met het vragen van handmatige SQL-queries aan de Lead-Developer via chats.
2. Schrijf een SQL-script genaamd `check_security_status.sql` in een nieuwe map `assets/meta/security/`.
3. Dit script moet de live status van RLS en actieve policies opvragen, exact zoals je voorstelde in je SQL-queries 1 t/m 4.
4. Bereid een Pull Request (PR) voor waarin je dit script klaarzet, zodat de Lead-Developer dit in één klik kan uitvoeren in zijn Supabase SQL Editor wanneer hij tijd heeft.
5. Zodra de resultaten er zijn, schrijf je jouw conclusie direct in DIT bestand (`ORCHESTRATOR.md`) onder het kopje '## Database Audit Resultaten'.

Pas GEEN live data of productiecode aan. Werk uitsluitend via dit bestand en aparte branches.

## Database Audit Resultaten

Datum: 2026-10-21  
Bron: statische code-audit op de lokale kopie van `b66-making-memories` (geen live Supabase-query, geen wijziging aan productiedata of app-code).  
Live-check klaargezet in `assets/meta/security/check_security_status.sql` (queries 1–4, alleen SELECT op catalogus).

### Samenvatting

De zeven prioriteitstabellen (`reizen`, `tankbeurten`, `reis_stops`, `reiskosten`, `fotos`, `campers`, `friend_requests`) hebben **geen RLS-migratie in** `supabase/migrations/`. De applicatie filtert in JavaScript op `camper_id` / `user_id`. Dat is geen databasegrens: zonder RLS (of met RLS zonder policies) kan iedere ingelogde client via de API alle rijen lezen of wijzigen.

Conclusie zolang de live SQL-uitvoer ontbreekt: **beveiliging van deze tabellen is in de repo niet aantoonbaar en moet als open risico worden behandeld.**

### Bevindingen per tabel

| Tabel | RLS in repo-migraties | Policies in repo | Opmerking |
| --- | --- | --- | --- |
| `reizen` | niet gevonden | geen | Client filtert vaak op `camper_id`; oudere HTML-snapshots en enkele queries doen `select('*')` zonder camperfilter. |
| `tankbeurten` | niet gevonden | geen | Zelfde patroon: UI-filter, geen server-side policy in git. |
| `reis_stops` | niet gevonden | geen | Koppeling via `reis_id`. Vriendendeling (`gedeeld_met_vrienden`) bestaat alleen in de app; zonder RLS is die vlag geen toegangspoort. |
| `reiskosten` | niet gevonden | alleen `reiskosten_update_policy.sql` in de repo-root | Alleen `FOR UPDATE` voor rollen `editor` en `admin`. Geen SELECT/INSERT/DELETE, bestand staat niet in `supabase/migrations/`. |
| `fotos` | niet gevonden | geen | Metadata-tabel zonder policy. Storage-bucket `fotos` wordt via `getPublicUrl` benaderd (publieke URL als het object of de bucket publiek is). |
| `campers` | niet gevonden | geen | Camperprofiel (kenteken, merk, model, …) is client-side beperkt tot “eigen” camper. |
| `friend_requests` | tabel alleen als SQL-comment in `index.html` / `test-agent.html` | geen | App vertrouwt op filters `requester_user_id` / `recipient_user_id`. Zonder RLS kan een client verzoeken van anderen lezen of updaten. |

Wel RLS in migraties, maar **buiten** deze opdracht: `platform_admins`, `owner_provision_audit`, `system_settings`, `camper_guide_topics`, `camper_guide_topic_photos`.

### Extra risico’s (vrienden-logica en gerelateerde objecten)

1. **Vriendendeling is geen RLS.** `loadOntdektePlaatsen` haalt vriend-campers, hun `reizen` en daarna `reis_stops` met `gedeeld_met_vrienden = true`. Dat werkt alleen als die rijen voor de ingelogde gebruiker zichtbaar zijn. Ontbreekt RLS, dan is de filter cosmetisch. Staat RLS strak op “alleen eigen camper”, dan faalt delen totdat er een policy voor vrienden bijkomt.
2. **Omgekeerde share-vlag.** Bij opslaan van een stop: `gedeeld_met_vrienden: !document.getElementById('shareWithFriends').checked`. Een aangevinkt “delen”-vak zet de kolom op `false`.
3. `friends`**-tabel** zit niet in de prioriteitslijst, maar `ensureMutualFriendship` insert beide richtingen vanuit de browser. `removeVriend` deelt op `id` zonder te controleren dat de rij bij `auth.uid()` hoort — opnieuw alleen veilig mét RLS.
4. **Profiel-enumeratie.** Vriend toevoegen zoekt `profiles` op e-mail. Dat is functioneel nodig; zonder strikte SELECT-policy op `profiles` is dat een gebruikerslijst.
5. `get_platform_overview()` is `SECURITY DEFINER` en telt o.a. `reizen`, `reis_stops`, `fotos`, `tankbeurten`, `reiskosten`. Execute staat op `authenticated`; de functie zelf checkt `is_head_admin`. Dat is acceptabel, maar blijft een extra pad naast RLS.
6. **Rollen komen niet overeen.** `reiskosten_update` eist `editor`/`admin`. Elders in comments en UI komen `lid`, `viewer` en `Camper Lid` voor. Policies die op de verkeerde rolstrings matchen, blokkeren of laten te veel door.

### Wat queries 1–4 in Supabase moeten bevestigen

Script: `assets/meta/security/check_security_status.sql`

1. Tabel bestaat + `relrowsecurity` / `relforcerowsecurity`.
2. Actieve policies (`pg_policies`: cmd, roles, using, with check).
3. Grants voor `anon`, `authenticated`, `public`.
4. Dekkingsmatrix: per tabel × SELECT/INSERT/UPDATE/DELETE het aantal policies (`policy_count = 0` is een gat).

Verwachte uitkomst op basis van git: RLS uit of RLS aan zonder (volledige) policies; hoogstens een UPDATE-policy op `reiskosten` als dat losse bestand ooit handmatig is gedraaid.

### Acties (nog niet uitgevoerd — geen live of productiecode)

1. Lead-Developer: script plakken in Supabase SQL Editor, resultaten terugzetten onder dit kopje.
2. Daarna, op een aparte branch: `ENABLE ROW LEVEL SECURITY` + policies per prioriteitstabel, lidmaatschap via `camper_users`, uitzondering voor bewust gedeelde `reis_stops`.
3. `friend_requests` (en bij voorkeur `friends`) alleen zichtbaar/wijzigbaar voor requester of recipient.
4. Storage-policies voor bucket `fotos` nalopen; geen publieke objecten tenzij expres.
5. `reiskosten_update_policy.sql` in een echte migratie zetten en uitbreiden naar SELECT/INSERT/DELETE met consistente rollen.
6. Share-checkbox-inversie in TEST-AGENT herstellen (aparte functionele fix, niet in deze audit-PR).

Live SQL-resultaten: nog niet beschikbaar. Deze sectie is de code-audit; plak de output van queries 1–4 hieronder wanneer die gedraaid is.

## Database Audit Resultaten

De live database-analyse heeft de volgende RLS-status opgeleverd:

- RLS staat succesvol AAN op alle tabellen.

- Risico: Vrijwel alle DELETE-acties hebben 0 actieve policies, wat data-verwijdering voor gebruikers blokkeert of onveilig omzeilt.

## Volgende Opdracht voor de Cursor Agent:

1. Analyseer de exacte SQL-definities van de huidige policies op `reis_stops` en `tankbeurten` (zoek naar de exacte criteria in je lokale code of bereid een script voor om ze uit te lezen).

2. Repareer in `index.html` en `test-agent.html` de logische bug rondom de "gedeeld_met_vrienden" checkbox (zorg dat 'AAN' ook echt 'DELEN' betekent in de database en niet 'PRIVÉ').

3. Schrijf een overzichtelijk voorstel in dit bestand onder een nieuw kopje '## Voorgestelde RLS Fixes' om de DELETE-policies veilig in te richten op basis van `auth.uid() = user_id` of camper-lidmaatschap.


## Voorgestelde RLS Fixes

Script: `assets/meta/security/delete_policies.sql` (nog NIET uitgevoerd; eerst testen op staging, niet op productie).

**Aanpak:** DELETE alleen toestaan voor leden van de camper via `camper_users` met rol `admin`, `editor` of `lid`. Rol `viewer` mag niet verwijderen. De check zit in de hulpfunctie `b66_can_write_camper(camper_id)` (`SECURITY DEFINER`, vaste `search_path`), zodat strenge RLS op `camper_users` de policies niet breekt.

| Tabel | DELETE-criterium |
| --- | --- |
| `reizen`, `tankbeurten`, `reiskosten` | `b66_can_write_camper(camper_id)` |
| `reis_stops` | via `reis_id` naar `reizen.camper_id` |
| `fotos` | via `stop_id` naar `reis_stops` naar `reizen.camper_id` |
| `friend_requests` | `auth.uid()` is requester of recipient |
| `friends` (extra) | `user_id = auth.uid()` |
| `personen` (extra) | `b66_can_write_camper(camper_id)` |
| `campers` | bewust geen policy (cascade-risico); optioneel alleen camper-admin, staat uitgecommentarieerd in het script |

**Nog open:**
1. Storage-policies voor bucket `fotos` (`storage.objects` DELETE) zijn niet meegenomen; de app verwijdert daar bestanden met `storage.remove()`.
2. Policy-definities van `reis_stops` en `tankbeurten` zijn niet uit de live database gelezen; check met `pg_policies` of er SELECT/INSERT/UPDATE-policies bestaan die dezelfde rolnamen gebruiken.
3. Rolnamen in de app (`viewer`, `editor`, `lid`, `admin`) moeten overeenkomen met wat in `camper_users.role` staat.

## Checkbox-fix gedeeld_met_vrienden (test-agent.html)

Alleen `test-agent.html` is aangepast (acceptatie). `index.html` (productie) blijft ongewijzigd: de workflow `sync-test-agent-release.yml` kopieert `test-agent.html` naar `index.html` zodra een wijziging op `main` komt. Test dus eerst op de branch; een merge naar `main` zet de fix live.

- Opslaan: `gedeeld_met_vrienden` = checkbox aangevinkt (was omgekeerd).
- Laden bij bewerken: checkbox = `Boolean(stop.gedeeld_met_vrienden)` (was omgekeerd).
- Label: "Deze stop delen met vrienden" (was "niet delen").
- Nieuwe stop: checkbox standaard aan (gedrag blijft zoals het was: standaard gedeeld).
- Bestaande data hoeft niet gemigreerd te worden: de oude UI was consistent omgekeerd, dus `true` in de database betekende al "gedeeld".
