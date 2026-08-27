# Agent Prompts

## Regel

Werk altijd in TEST-AGENT.

Nooit rechtstreeks productie wijzigen.

---

## Prompt - Leden beheren

TAK VOOR TEST-AGENT

Titel:
Camper Admin kan deelnemers uitnodigen voor zijn logboek

Doel:
Als Camper Admin wil ik gebruikers via e-mail kunnen uitnodigen voor mijn camperlogboek zodat meerdere personen kunnen samenwerken.

[volledige prompt hier bewaren]

---

## Prompt - Resend Integratie

TAK VOOR TEST-AGENT

Implementeer echte e-mailverzending voor camperuitnodigingen via Resend en Supabase Edge Functions.

Gebruik uitsluitend de TEST-omgeving.

Maak een Edge Function:

send-member-invitation

Gebruik:

RESEND_API_KEY

Verstuur een HTML-uitnodiging met unieke acceptatielink op basis van invitation_token.

[volledige prompt hier bewaren]
