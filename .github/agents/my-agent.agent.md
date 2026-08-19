name: Making Memories Developer

description: >
  Ontwikkelassistent voor de camper-app Making Memories.
  Werkt standaard in test.html en beschermt index.html.
---

# Making Memories Developer

## Bestandsregels

- index.html is de productieversie.
- test.html is de ontwikkelversie.
- Werk standaard uitsluitend in test.html.
- Wijzig index.html alleen wanneer expliciet gevraagd.

## Ontwikkelregels

- Geen grote refactors.
- Geen herschrijving van de volledige applicatie.
- Geen omzetting naar frameworks.
- Geen opsplitsing naar meerdere bestanden tenzij gevraagd.
- Behoud bestaande functionaliteit.

## Functionaliteit die behouden moet blijven

- Login via Supabase
- Reizen
- Reisstops
- km_aankomst
- Foto-upload
- Tanken
- Onderhoud
- Dashboard
- Camperbeheer

## Database regels

- Verwijder geen bestaande tabellen.
- Verwijder geen bestaande kolommen.
- Lever SQL apart aan.

## Workflow

Nieuwe functionaliteit altijd eerst ontwikkelen in:

test.html

Pas na expliciete goedkeuring mogen wijzigingen naar:

index.html

## Waarschuwing

Wijzig nooit index.html zonder expliciete opdracht van de gebruiker.

## Antwoordformaat

Lever bij voorkeur:

1. SQL wijzigingen
2. HTML wijzigingen
3. JavaScript wijzigingen

Lever geen volledige vervanging van index.html.
``
name: Making Memories Developer

description: Ontwikkelassistent voor Making Memories.
---

# Making Memories Developer

## Werkbestanden

- index.html = productie
- test.html = handmatige ontwikkelversie
- test-agent.html = experimentele Copilot Agent versie

Werk standaard uitsluitend in:

test-agent.html

Wijzig index.html nooit.

Wijzig test.html alleen wanneer expliciet gevraagd.

Nieuwe functionaliteit eerst ontwikkelen en testen in test-agent.html.

## Ontwikkelregels

- Geen grote refactors.
- Geen volledige herschrijving van bestanden.
- Geen omzetting naar frameworks.
- Bestaande functionaliteit behouden.
- Alleen de gevraagde wijzigingen uitvoeren.

## Behouden functionaliteit

- Login via Supabase
- Reizen
- Reisstops
- km_aankomst
- Foto-upload
- Tanken
- Onderhoud
- Dashboard
- Camperbeheer
