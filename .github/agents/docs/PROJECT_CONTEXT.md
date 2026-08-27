# Making Memories - Project Context

## Doel

Making Memories is een camperlogboek-app waarmee campergebruikers hun reizen, documenten, onderhoud, herinneringen en activiteiten kunnen beheren en delen met andere gebruikers.

## Technische Stack

Frontend:
- HTML
- JavaScript
- CSS

Backend:
- Supabase

Services:
- Supabase Auth
- Supabase Database
- Supabase Storage
- Supabase Edge Functions
- Resend (e-mail)

## Belangrijke Regels

- Werk altijd eerst in TEST-AGENT.
- Geen wijzigingen rechtstreeks in productie.
- Nieuwe functionaliteiten eerst testen in TEST.
- Alle grote wijzigingen documenteren.

## Rollen

### Platform Admin

Kan:
- Alles beheren
- Alle campers bekijken
- Alle gebruikers beheren

### Camper Admin

Kan:
- Eigen camper beheren
- Leden beheren
- Rollen wijzigen
- Uitnodigingen versturen

### Editor

Kan:
- Logboeken aanpassen

### Viewer

Kan:
- Alleen bekijken

## Huidige Status

Voltooid:
- Camperbeheer
- Ledenbeheer
- Rollenmodel
- Uitnodigingssysteem
- Resend integratie
- Edge Function send-member-invitation

Open:
- RESEND_API_KEY configureren
- Edge Function deployen
- E-mailflow testen

## Werkwijze Voor AI

Bij iedere wijziging:

1. Analyseer bestaande code.
2. Werk uitsluitend in TEST-AGENT.
3. Lever wijzigingen op met:
   - aangepast bestand
   - reden van wijziging
   - testscenario's
4. Nooit rechtstreeks productie wijzigen.
