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

Script: `assets/meta/security/delete_policies.sql`. Let op: een eerdere versie (met rol `lid` erbij en hulpfunctie `b66_can_write_camper`) is mogelijk al in Supabase uitgevoerd. De huidige versie vervangt die en is veilig om opnieuw te draaien.

**Aanpak (besluit Lead-Developer, 2026-10-23):** verwijderen mag alleen de `admin` of `editor` van de eigen camper (via `camper_users`) en de hoofdbeheerder van het platform (tabel `platform_admins`, zoals de app die ook gebruikt). Gewone leden (`lid` / `member`) en `viewer` mogen niet verwijderen. De check zit in de hulpfunctie `b66_can_delete_camper(camper_id)` (`SECURITY DEFINER`, vaste `search_path`), zodat strenge RLS op `camper_users` de policies niet breekt.

| Tabel | DELETE-criterium |
| --- | --- |
| `reizen`, `tankbeurten`, `reiskosten` | `b66_can_delete_camper(camper_id)` |
| `reis_stops` | via `reis_id` naar `reizen.camper_id` |
| `fotos` | via `stop_id` naar `reis_stops` naar `reizen.camper_id` |
| `friend_requests` | `auth.uid()` is requester of recipient |
| `friends` (extra) | `user_id = auth.uid()` |
| `personen` (extra) | `b66_can_delete_camper(camper_id)` |
| `campers` | bewust geen policy (cascade-risico); optioneel alleen camper-admin, staat uitgecommentarieerd in het script |

**Live bevinding (2026-10-23):** `tankbeurten` ("Authenticated users can delete tankbeurten") en `personen` ("personen delete") hebben al een DELETE-regel met `true`: elke ingelogde gebruiker kan daar alles van iedereen verwijderen. `friends` heeft `user_id = auth.uid()` (goed). Het script verwijdert de open regels (op exacte naam) en vervangt ze. Het script zelf was op dat moment nog niet toegepast: de eerste poging stopte omdat `public.is_head_admin(uuid)` in de live database niet bestaat (migratie `202609050545` is daar nooit toegepast). Het script gebruikt nu direct de tabel `platform_admins` en werkt ook als die tabel ontbreekt. Gevolg: repo-migraties en live database lopen uiteen; later gelijktrekken.

**Nog open:**
1. Storage-policies voor bucket `fotos` (`storage.objects` DELETE) zijn niet meegenomen; de app verwijdert daar bestanden met `storage.remove()`.
2. Policy-definities van `reis_stops` en `tankbeurten` zijn niet uit de live database gelezen; check met `pg_policies` of er SELECT/INSERT/UPDATE-policies bestaan die dezelfde rolnamen gebruiken.
3. Rollen in gebruik (live, 2026-10-23): `admin` 9, `lid` 2, `editor` 1, `viewer` 1. Er is in de live database **geen** controleregel op `camper_users.role` (de regel uit migratie `202609050545` is niet toegepast), dus elke tekst is als rol toegestaan. Voorstel: `check (role in ('admin','editor','lid','viewer'))` toevoegen als aparte migratie en de oude migratie corrigeren (die zou falen door de `viewer`-rij).
4. `reiskosten_update_policy.sql` (alleen `editor`/`admin`) sluit al aan op het nieuwe uitgangspunt; SELECT- en INSERT-policies zijn nog niet gecontroleerd.

## Checkbox-fix gedeeld_met_vrienden (test-agent.html)

Alleen `test-agent.html` is aangepast (acceptatie). `index.html` (productie) blijft ongewijzigd: de workflow `sync-test-agent-release.yml` kopieert `test-agent.html` naar `index.html` zodra een wijziging op `main` komt. Test dus eerst op de branch; een merge naar `main` zet de fix live.

- Opslaan: `gedeeld_met_vrienden` = checkbox aangevinkt (was omgekeerd).
- Laden bij bewerken: checkbox = `Boolean(stop.gedeeld_met_vrienden)` (was omgekeerd).
- Label: "Deze stop delen met vrienden" (was "niet delen").
- Nieuwe stop: checkbox standaard aan (gedrag blijft zoals het was: standaard gedeeld).
- Bestaande data hoeft niet gemigreerd te worden: de oude UI was consistent omgekeerd, dus `true` in de database betekende al "gedeeld".

## Leesregels-audit en afsluiten (2026-10-23)

Bron: live `pg_policies` (SELECT-, INSERT- en UPDATE-regels) en kolomlijst, aangeleverd door de Lead-Developer.

### Besluiten van de Lead-Developer
- **Lezen:** alleen leden van de camper (elke rol). Vrienden zien alleen stops met `gedeeld_met_vrienden = true` (plus de reis en foto's die daarbij horen).
- **Toevoegen en wijzigen:** `admin`, `editor` en `lid`. Een `viewer` kijkt alleen.
- **Verwijderen:** alleen `admin` en `editor` (al toegepast in Supabase, zie "Voorgestelde RLS Fixes").
- Hoofdbeheerder: mag verwijderen overal (via `platform_admins`). Lezen/wijzigen over alle campers is nog niet geregeld; open punt.

### Bevindingen (live, vóór de scripts)
1. **Ernstig:** `camper_users` INSERT controleert alleen `user_id = auth.uid()`. Elke ingelogde gebruiker kon zichzelf met elke rol (ook `admin`) aan elke camper koppelen. Camper-nummers zijn oplopende getallen.
2. **Ernstig:** `campers` INSERT had vijf ruime regels, waaronder `test_anon_insert` (niet-ingelogd, `true`).
3. Naast de strenge regels staat op `reizen`, `reis_stops`, `fotos`, `tankbeurten`, `reiskosten` en `personen` een SELECT-regel met `true`: elke ingelogde gebruiker kon alles lezen. De app filtert wel op camper, de database niet.
4. INSERT met `true` op `reizen`, `reis_stops`, `fotos`, `tankbeurten`, `reiskosten`, `personen` en `onderhoud`.
5. UPDATE met `true` op `personen` en `tankbeurten`. Op `reizen` en `reis_stops` mocht elk lid (ook `viewer`) wijzigen. `reiskosten_update` stond op `admin` en `lid` (geen `editor`).
6. `invitations_update`: de uitgenodigde kon zijn eigen uitnodiging wijzigen, ook de rol (en daarmee zichzelf als admin laten koppelen).
7. `invite_codes` INSERT met `true`; `profiles` SELECT met `true` (alle e-mailadressen leesbaar).
8. Geen aanwijzing van misbruik: in `camper_users` heeft elke gebruiker maximaal een koppeling met een logische rol.

### Scripts (volgorde is belangrijk)
1. `assets/meta/security/01_koppelen_afsluiten.sql`: sluit punt 1, 2 en 6. Koppelen mag alleen door een admin van die camper, als eigenaar van een nieuwe camper zonder leden, of met een openstaande uitnodiging op het eigen e-mailadres met precies die rol (oude `camper_invites`: alleen rol `lid` op het eigen e-mailadres; een code zonder e-mailadres geeft geen toegang). Campers aanmaken alleen met jezelf als eigenaar (`owner_id` krijgt al standaard `auth.uid()`). Trigger op `invitations`: een uitgenodigde mag alleen de status op `accepted` zetten.
2. `assets/meta/security/02_gegevens_afsluiten.sql`: sluit punt 3, 4 en 5 volgens de besluiten hierboven. Vervangt alle bestaande SELECT/INSERT/UPDATE-regels op `campers`, `reizen`, `reis_stops`, `fotos`, `tankbeurten`, `reiskosten`, `personen` en `onderhoud` en maakt `onderhoud_delete` aan.
- Beide scripts leggen eerst de bestaande regels vast in `b66_policy_backup` (niet leesbaar via de app), draaien in een transactie, wijzigen geen gegevens en zijn veilig om opnieuw te draaien.
- Getest op een nagebouwde Postgres 16 met alle regels uit de live-lijsten, proefgebruikers in elke rol (admin, editor, lid, viewer, buitenstaander, vriend, uitgenodigde, nieuwe gebruiker, niet-ingelogd): 89 controles, alle goed, ook bij opnieuw draaien. De test kent beperkingen: aannames over regels die niet in de lijsten stonden (`invitations` SELECT, `camper_invites` SELECT) zijn nagebootst.
- **Status:** nog NIET uitgevoerd in Supabase.

### Let op bij uitvoeren
- Draai deel 1, test aanmelden en uitnodigen (nieuwe gebruiker met uitnodiging, nieuwe camper), draai daarna deel 2.
- Na deel 2 zien vrienden alleen gedeelde stops; de reis (inclusief crew-gegevens) is zichtbaar als er minstens een gedeelde stop is.
- Oude camper-links zonder e-mailadres werken niet meer; een admin maakt dan een nieuwe uitnodiging.

### Nog open
- `invitations` SELECT en DELETE, `camper_invites` en `invite_codes` (INSERT `true`): regels niet bekeken/aangepast.
- `profiles` SELECT `true`: alle ingelogde gebruikers kunnen alle e-mailadressen lezen. De app zoekt vrienden op e-mail; aanpassen vraagt een alternatief (bijvoorbeeld een zoekfunctie).
- `camper_users` heeft geen UPDATE- of DELETE-regel: rol wijzigen en leden verwijderen in Leden beheren lukt waarschijnlijk niet.
- Hoofdbeheerder: lezen en wijzigen over alle campers (bijvoorbeeld voor ondersteuning) is niet geregeld; het beheerscherm toont nu alleen eigen gegevens.
- Storage (foto-bestanden): bucket en policies nog niet bekeken.
- `camper_users.role` heeft in de live database geen controleregel; migraties in de repo wijken af van de live database (o.a. `is_head_admin` bestaat daar niet).
- Geen functie om een reis, stop, tankbeurt of kosten te verwijderen in de app (bewust uitgesteld).

## Stand van zaken einde dag (2026-10-23)

**Gedaan**
- Deel 1 (`assets/meta/security/01_koppelen_afsluiten.sql`) is live gedraaid.
- `01b_uitnodiging_fix.sql` is live gedraaid: `invitations_update` gebruikt nu `b66_my_email()` (de oude regel las `auth.users`, dat gaf "permission denied for table users").
- `test-agent.html`: profiel aanmaken telt "bestond al" (code 23505) als gelukt (race tussen registreren en showApp). Moet nog gecommit worden op branch `security/check-rls-status`.
- Testomgeving gecorrigeerd: `authenticated` heeft in Supabase GEEN leesrecht op `auth.users`. Lokale test 89/89.

**Nog te testen (in de testversie)**
1. Uitnodiging afronden als uitgenodigde (viewer) op eigen camper.
2. Registreren via uitnodiging in privévenster met nieuw adres (gebruik `naam+test1@gmail.com`).
3. Inloggen als eigenaar en testgebruiker: alleen eigen data zichtbaar.

**Daarna**
- Back-up in Supabase, dan Deel 2 (`02_gegevens_afsluiten.sql`) draaien en testen met viewer/lid/admin.

**Open punten (volgorde ter bespreking)**
- `invitations_read_by_token` staat op `true`: iedereen kan alle uitnodigingen incl. tokens lezen. Oplossing: alleen opzoeken via functie op exact token.
- `invite_codes` INSERT `true`, `profiles` SELECT `true` (e-mails zichtbaar voor alle ingelogden).
- `camper_users` heeft geen UPDATE/DELETE-regel (rol wijzigen / lid verwijderen).
- Knop om nieuwe camper-eigenaren uit te nodigen bestaat niet (platform-uitnodiging); bouwen na Deel 2.
- Delete-reis functie (door gebruiker uitgesteld), hoofdbeheerder-rechten, storage bucket `fotos`, rol-check constraint, offline PWA, apart testproject, opruimen oude HTML-bestanden, AVG/privacy.
- Testaccounts: wachtwoord zetten via SQL (`extensions.crypt`) of plusadressen gebruiken.
- Onbeantwoord: wie zijn de gebruikers, wat zijn Fieneke en Suus, tijd/budget.

## Visie, doelgroep en werkwijze (2026-10-24)

**Wat de app is**
Een privé-logboek voor camperbezitters: de hele reis van begin tot eind (stops, kosten, tankbeurten, onderhoud) in plaats van het papieren schriftje. Delen met vrienden gebeurt alleen per stop en alleen als de eigenaar dat zelf wil. Er is bewust géén openbaar platform met beoordelingen van onbekenden. Dat is het verschil met grote camperapps.

**Doelgroep**
Camperbezitters en hun vrienden (kleine, vertrouwde kring). Niet bedoeld voor een massa onbekende gebruikers.

**Verdienmodel (nog ideeën, niets besloten)**
Gratis basis plus betaald voor meer opslag/campers/rapporten, of jaarabonnement voor het logboek, of koppeling met camperclub/verhuurder. Eerst valideren met 10 à 20 echte camperbezitters een seizoen lang. Privacy als verkoopargument; voor echte lancering AVG-regels op orde.

**De "agents" (bedoeld als rollen die ik aanstuur)**
- Orchestrator (Claude): overzicht, plan, rapportage aan Mat. Ook de code en beveiliging.
- Fieneke (financieel): als de app live gaat, onderzoeken hoe betalingen werken en wat het kost/oplevert, en dat in gewone taal terugkoppelen. Nog niet gestart.
- Suus (sociaal): de app bekendmaken (Facebook/social media): teksten, ideeën. Nog niet gestart.
Fieneke en Suus zijn nog geen aparte programma's: ze worden pas ingezet als de app klaar is voor gebruikers.

**Tijd**
Gemiddeld ca. 1 uur per dag (vaste baan); in het weekend en op vrije dagen meerdere uren (4 à 6 mogelijk). De orchestrator houdt het kort: elke sessie één duidelijk stapje, één samenvatting, één vraag.

**Volgorde**
1. Veiligheid afmaken (Deel 1 klaar, Deel 2 nog te draaien, uitnodigingen dichtzetten).
2. Testen met enkele echte gebruikers.
3. Pas daarna Fieneke (betalingen/prijs) en Suus (bekendheid).

## Teststatus na Deel 2 (2026-10-24)

**Live gedraaid:** Deel 1, 01b (uitnodiging-fix), Deel 2 (`02_gegevens_afsluiten.sql`, controle: 1 regel per tabel/actie; fotos heeft bewust geen UPDATE, campers geen DELETE).

**Getest in de testversie (https://familie-schils.github.io/b66-making-memories/test-agent.html):**
- Uitnodiging via link als nieuwe gebruiker (viewer, camper 22): gelukt; invitation `accepted`, camper_users viewer, profiel aangemaakt. Geen "permission denied" en geen "duplicate key" meer.
- Admin (camperlogboek) leest alles; maakt uitnodigingen (viewer en editor).
- Viewer: leest, schrijven geweigerd door RLS ("new row violates row-level security policy for table tankbeurten").
- Editor (msc.schils+test3): tankbeurt opslaan lukt; uitnodigingsvak verborgen.
- Vrienden: poging4 (vriend van camperlogboek) ziet precies de 3 gedeelde stops (112,113,114) en niet stop 115 (niet gedeeld); geen data van camper 22.
- Nog niet getest: account zonder camper (piet@), stop wijzigen als editor/viewer.

**Besluit:** de rol `lid` blijft bestaan (oude accounts houden rechten; Deel 2 behandelt lid als schrijver).

**Testrij in camper 22:** tankbeurt "TEST EDITOR mag dit wel" (10 l, EUR 15) mag worden verwijderd door de admin.

**Gewijzigd in test-agent.html:** profiel aanmaken telt duplicate (23505) als gelukt; rolkeuze (Viewer/Editor) in Mijn Camper > Uitnodigen.

**Verbeterpunten / nieuwe taken**
1. Open vriendenverzoek zichtbaar maken op startscherm (ster/badge, evt. teller op Meer).
2. Formulieren verbergen voor viewers; nette melding "Je mag hier alleen meekijken" i.p.v. technische RLS-melding.
3. Uitnodigingslink die de app toont wijst naar productie (`/?invite=`), moet naar de testversie in test (en later naar de juiste versie).
4. Knop voor nieuwe camper-eigenaren (platform-uitnodiging) bestaat niet.
5. Testaccounts: wachtwoord zetten via SQL of plusadressen (`msc.schils+testN@gmail.com`).

**Volgende stap:** `invitations_read_by_token` (SELECT `true`) dichtzetten: iedereen kan nu alle uitnodigingen incl. tokens lezen.

## Live controle Deel 3 en Deel 4 (2026-10-24, 10:30)

Bron: alleen-lezen query in de Supabase SQL Editor (functies, triggers, `b66_policy_backup`, `pg_policies` op `invitations`, `friends`, `friend_requests`, `camper_users`).

**Live gedraaid:** Deel 3 (`03_uitnodigingen_afsluiten.sql`) en Deel 4 (`04_vrienden_en_leden.sql`). Backup-stappen aanwezig: 01 (16), 01b (4), 02 (36), 03 (4), 04 (24).

- **Uitnodigingen:** `invitations_read_by_token` is weg. Lezen mag alleen de admin van de camper of de uitgenodigde zelf (`b66_my_email()`). Opzoeken via exacte code: `b66_get_invitation` (security definer). Trigger `b66_invitations_guard` actief.
- **Vriendenverzoeken:** lezen, wijzigen en verwijderen alleen door afzender of ontvanger. Nieuw verzoek alleen als `pending`, niet aan jezelf. Trigger `b66_friend_requests_guard` actief.
- **Vrienden:** aanmaken alleen vanuit een vriendenverzoek. Beide kanten mogen zien en verwijderen.
- **Camperleden:** leden zien elkaar (en vrienden zien elkaars lidmaatschap). Admin wijzigt rol (alleen viewer/editor/lid) of verwijdert anderen, niet zichzelf (`b66_is_admin`).
- De live regels voor `camper_users` komen overeen met de lokale versie van het script (ook na de wijziging van 10:11). Die wijziging moet nog gecommit worden.

**Vervalt in de open punten:** `invitations_read_by_token`, `camper_users` zonder UPDATE/DELETE.

**Nog open (veiligheid):**
1. `invite_codes` INSERT `true`.
2. `profiles` SELECT `true` (alle e-mailadressen leesbaar voor elke ingelogde gebruiker).
3. Storage-bucket `fotos` (policies).
4. `invitations` heeft geen DELETE-regel (uitnodiging intrekken kan niet).
5. Rol-controleregel op `camper_users.role`; repo-migraties gelijktrekken met live.

**Nog te testen in de testversie:** vriend verwijderen (beide kanten weg, gedeelde stops niet meer zichtbaar), vriendenverzoek accepteren/afwijzen, rol wijzigen en lid verwijderen in Leden beheren.

## Foto-opslag (2026-10-24, ochtend)

**Besluit Lead-Developer:** het origineel van een foto blijft bij de gebruiker (fotogalerij van telefoon/computer). De app bewaart alleen een kleine versie voor het logboek en voor delen met vrienden. Een koppeling met Google Foto's/OneDrive/iCloud is afgeraden: Google beperkt sinds 2025 wat apps in de fotobibliotheek mogen lezen, iCloud heeft geen bruikbare webkoppeling, elke gebruiker moet inloggen bij die dienst en vrienden kunnen er niet bij. Een eigen exemplaar downloaden bestaat al: Reizen > reis bewerken > "PDF downloaden" / "Excel downloaden" (alleen bij een afgesloten reis). De PDF bevat alle foto's per stop (2 per rij); Excel bevat geen foto's.

**Live bevindingen (alleen gelezen):**
- Bucket `fotos`: **openbaar**, geen limiet op grootte of type. 90 bestanden, 160 MB (gemiddeld 1,8 MB, grootste 14 MB). Gratis plan: 1 GB (niet nagekeken).
- Mappen: hoofdmap 78 bestanden (147 MB), `camper-uitleg/` 10, `camper-guides/` 2.
- Gekoppeld: 28 via `fotos.url` (64 MB), 9 via de campergids. **53 bestanden (87 MB) horen nergens bij.**
- Storage-regels: alleen `authenticated-upload 1m4ctr_0` (INSERT, elke ingelogde gebruiker, overal in `fotos`). Geen SELECT-, UPDATE- of DELETE-regel. Supabase blokkeert verwijderen van bestanden met SQL (`protect_objects_delete`).
- Oorzaak van de losse bestanden: (1) er is geen verwijderregel, en (2) de app verwijderde op `fotos.bestandsnaam`, maar daar staat de originele naam (`IMG_0869.jpeg`), niet de naam in de opslag.

### Stap 1 – kleinere foto's (klaar, `test-agent.html`, nog niet gecommit)
- Upload: maximaal 1280 px, doel 400 KB, kwaliteit 0,80 (min. 0,60), kleinste maat 800 px. Was: 2000 px / 3 MB.
- Getest in Chromium: telefoonfoto 4032×3024 (6,3 MB) → 1280×960, 217 KB. Ongeveer 6 tot 8 keer meer foto's in dezelfde ruimte.
- Geldt voor stopfoto's en campergids-foto's (zelfde functie).

### Stap 2 – opslag afsluiten (voorbereid, NIET live gedraaid)
**App (`test-agent.html`, nog niet gecommit):**
- Elke foto-link op het scherm wordt vervangen door een tijdelijke beveiligde link (1 uur), in één aanvraag per scherm; ook de vergrote weergave en het reisrapport (PDF). Lukt dat niet, dan blijft de oude link staan, dus de app werkt vóór en na de SQL-scripts.
- Nieuwe stopfoto's gaan naar `stops/<camper_id>/...` (nodig voor de uploadregel).
- Foto verwijderen: eerst controleren dat de regel in `fotos` echt weg is (RLS kan stil 0 rijen verwijderen), dan het bestand verwijderen op het pad uit de url.
- Getest in Chromium met nagebootste Supabase: syntax goed, links vervangen, terugvallen bij geen recht, mislukt pad blijft zichtbaar.

**SQL:**
1. `assets/meta/security/06a_fotos_regels.sql`: hulpfuncties (`b66_is_head_admin`, `b66_path_camper`, `b66_photo_stop`, `b66_photo_camper`, `b66_photo_visible`), leesregel (leden, vrienden bij gedeelde stop, hoofdbeheerder, eigen upload), verwijderregel (admin/editor van de camper, hoofdbeheerder, eigen upload), bucket max. 5 MB en alleen jpg/png/webp. **Bucket blijft openbaar, de oude app blijft werken.**
2. `assets/meta/security/06b_fotos_prive.sql`: uploaden alleen in `stops/<camper>/` (admin/editor/lid) of `camper-uitleg/<camper>/` (admin of hoofdbeheerder); bucket **privé**; max. 1 MB. Terugdraai-regel staat bovenin het script.
- Getest op lokale Postgres 16 met nagebootste storage-tabellen en proefgebruikers (admin, editor, lid, viewer, andere camper, vriend, buitenstaander, hoofdbeheerder): 45 controles, alle goed, ook bij opnieuw draaien.
- Niet getest: of de SQL Editor in Supabase regels op `storage.objects` mag aanmaken. Geeft het "must be owner", dan de regels via Storage > Policies in het dashboard aanmaken.

**Volgorde (belangrijk):**
1. Committen op `security/check-rls-status`; testversie testen (foto toevoegen, bekijken, vergroten, verwijderen, reisrapport).
2. `06a` draaien. Testen: foto's zichtbaar (nu via beveiligde links), vriend ziet alleen foto's van gedeelde stops, verwijderen van een foto haalt ook het bestand weg.
3. Merge naar `main` (workflow zet `test-agent.html` in `index.html`). Wachten tot productie de nieuwe versie heeft.
4. Pas dan `06b` draaien. Daarna werken oude openbare links niet meer (bewust).
5. Opruimen: lijst met losse bestanden staat onderaan `06a` (alleen lezen). Verwijderen in het dashboard (Storage > fotos), niet met SQL.

**Nog open (foto's):**
- Losse bestanden opruimen (53 stuks, 87 MB).
- Bestaande grote foto's (gemiddeld 1,8 MB) verkleinen kan later met een eenmalig hulpscript; nu niet nodig.
- `camper-guides/` (2 bestanden, oude map?) nagaan.
- Reisrapport (PDF) gebruikt `imageUrlToJpegDataUrl`; die haalt foto's nu via de beveiligde link op, dus het rapport blijft werken na `06b`. Meetesten bij stap 1 van de volgorde.
- Kwaliteit: in de PDF staan nu de kleine versies (max. 1280 px). Prima om te bekijken; voor een gedrukt fotoboek gebruikt de gebruiker zijn originelen.

**Nummering scripts (2026-10-24, 12:10):** `05_profielen_en_platformuitnodigingen.sql` (profielen en `invite_codes`, door een andere sessie gemaakt, nog niet live) is deel 5. De foto-scripts heten nu `06a_fotos_regels.sql` en `06b_fotos_prive.sql` (eerder `05a`/`05b`; die oude bestanden mogen weg). Deel 5 en 6a zijn onafhankelijk; beide maken `b66_is_head_admin()` aan met dezelfde uitkomst, dus de volgorde maakt niet uit.

## Online test na merge (2026-10-24, 12:40)
- Merge staat live (productie = testversie, versie 1.0.38). Nieuwe stopfoto: 106 KB in `stops/22/`, gekoppeld aan stop 116. Tonen werkt (via openbare link, want 06a is nog niet gedraaid).
- De lijst "Stops in deze reis" (actieve reis) liet nooit foto's zien. Toegevoegd in `test-agent.html` (nog niet gecommit): per stop maximaal 4 kleine foto's (56×56) plus "+N"; tik opent de vergrote weergave.
- Opgemerkt: productie toont het label "TESTVERSIE" (de workflow kopieert test-agent.html ongewijzigd naar index.html). Later oplossen.
- Oud probleem opgelost (12:55): na opnieuw openen van de app bleef "Stops in deze reis" verborgen (de lijst werd alleen geladen na opslaan of bewerken van een stop). `loadActiveTrip()` laadt de lijst nu ook.
- Opgemerkt, nog niet onderzocht: in het reisoverzicht (Reis openen > Reislog) van de actieve reis stond alleen de tankbeurt, niet stop "test foto".

## Deel 5 en 6a live (2026-10-24, 12:57)
- Gedraaid door Lead-Developer: `05_profielen_en_platformuitnodigingen.sql` (backup-stap 05) en `06a_fotos_regels.sql` (backup-stap 06a). Regels op storage.objects aanmaken via de SQL Editor werkte.
- Controle live: `profiles` en `invite_codes` hebben nieuwe regels; storage.objects heeft `b66_fotos_select`, `b66_fotos_delete` en (nog) de oude uploadregel; bucket `fotos` openbaar, max. 5 MB, alleen jpg/png/webp.
- App: foto's komen nu via beveiligde links (`/object/sign/`). Als camperlogboek (admin camper 22): alle 29 zichtbare fotoregels krijgen een beveiligde link, 0 fouten; dat zijn 2 eigen foto's (camper 22) en 27 gedeelde foto's van camper 1 (vriendschap).
- **Volgende:** foto verwijderen testen (bestand moet ook uit de opslag verdwijnen), daarna `06b` (privé + uploadregel + 1 MB), daarna 53 losse bestanden opruimen in het dashboard.
- Verwijdertest (13:06): foto bij stop 116 verwijderd in de app. Regel in `fotos` weg én bestand `stops/22/89444b80-...jpg` weg uit de opslag. Verwijderen werkt nu echt. Opslag weer 90 bestanden / 160 MB.

## Deel 6b live (2026-10-24, 13:11)
- `06b_fotos_prive.sql` gedraaid (backup-stap 06b). Bucket `fotos`: **privé**, max. 1 MB. Storage-regels: `b66_fotos_select`, `b66_fotos_insert`, `b66_fotos_delete` (oude uploadregel weg).
- Test: nieuwe foto na 6b geüpload (stop 117) → `stops/22/2722ccb0-...jpg`, 9,5 KB, zichtbaar in de app. Openbare link geeft nu 400 (afgeschermd, zoals bedoeld).
- **Foto-beveiliging is daarmee af.** Nog open: 53 losse bestanden (87 MB) opruimen via Storage > fotos (lijst: query onderaan `06a`).

## Opruimen losse bestanden (2026-10-24, 13:33)
- 47 losse bestanden van m.schils@hotmail.com in één keer verwijderd via console-script (`storage.remove`, eigen uploads). 2 eerder met de hand.
- Opslag nu: 42 bestanden, 80 MB (was 90 / 160 MB). Alle 29 stopfoto's en 9 gidsfoto's hebben nog hun bestand (0 ontbrekend).
- Nog 4 losse bestanden van andere accounts, met de hand weghalen in Storage > fotos: `camper 12.jpg`, `1786897942430_image.jpg`, `bffd20d4-8e7a-458b-b5c5-cdfe3e3d88bf.png`, `cd889ad0-a2cd-46cd-86ac-f61e0d793834.jpeg`.
- Resterende 80 MB zijn foto's in gebruik, van vóór het verkleinen (gemiddeld ca. 2 MB). Eventueel later eenmalig verkleinen.

## Takenlijst (bijgewerkt 2026-10-24, 13:40)
1. **Viewer-melding:** formulieren verbergen voor viewers en een nette melding "Je mag hier alleen meekijken" in plaats van de technische RLS-fout. (Uitgesteld op verzoek, eerst kilometerstand.)
2. Reislog van de actieve reis toonde alleen de tankbeurt, niet de stop: uitzoeken.
3. Label "TESTVERSIE" in productie (workflow kopieert test-agent.html ongewijzigd).
4. Open vriendenverzoek zichtbaar op startscherm; uitnodigingslink naar juiste versie; knop voor nieuwe camper-eigenaren.
5. 4 losse fotobestanden met de hand verwijderen; eventueel oude grote foto's eenmalig verkleinen.
6. Apart testproject (test en productie delen nu dezelfde database en dezelfde code op main).

## Kilometerstand in het reisformulier (2026-10-24, 13:50) – in `test-agent.html`, nog niet gecommit
**Wens Lead-Developer:** km niet bovenaan los van alles, maar logisch per moment: stand bij vertrek bij de start van de reis, en per stop de stand bij aankomst, voorgesteld vanuit de laatste stand in dezelfde reis, aan te passen (verhogen), niet verplicht.
- Blok "Kilometerstand van deze reis" bovenaan is weg.
- "Kilometerstand bij vertrek" staat nu bij **Start van de reis** (verplicht, zoals voorheen).
- Elke stop begint met **"Kilometerstand bij aankomst (optioneel)"**, groot veld bovenaan de stop, met eronder "Laatst bekend in deze reis: X km · stop N, plaats".
  - Eerste stop: volgt de stand bij vertrek zolang je het veld niet zelf aanpast.
  - Volgende stop / app opnieuw openen: vooraf ingevuld met de hoogste bekende stand in deze reis (eerdere stops, anders vertrek).
  - Leeg laten mag. Lager dan de laatst bekende stand wordt geweigerd met een duidelijke melding (bij bewerken: vergeleken met eerdere stops).
- Einde reis: Eind KM vooraf ingevuld met de laatst bekende stand; "KM gereden" staat nu daar.
- Getest: syntax; logica in Chromium met nagebootste stops (voorstel, volgen, niet overschrijven, bewerken, eind-km); weergave op telefoonbreedte.
