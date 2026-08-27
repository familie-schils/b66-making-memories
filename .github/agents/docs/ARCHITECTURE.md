# Architectuur

## Overzicht

Gebruikers
|
v
Frontend (test-agent.html)
|
v
Supabase
|
+-- Authentication
|
+-- Database
|
+-- Storage
|
+-- Edge Functions
|
v
Resend

## Database

### Users

Authenticatie via Supabase Auth.

### Campers

Campers worden beheerd door Camper Admins.

### Camper Members

Koppelt gebruikers aan campers.

Rollen:

- owner
- editor
- viewer

### Invitations

Tabel:

id
camper_id
email
role
invitation_token
status
expires_at
created_by
created_at

Statussen:

- Pending
- Accepted
- Revoked
- Expired

## Uitnodigingsflow

Camper Admin
↓
Uitnodiging maken
↓
Token genereren
↓
Invitations tabel
↓
Edge Function
↓
Resend
↓
E-mail
↓
Acceptatielink
↓
Koppeling aan camper

## Beveiliging

- RLS actief
- Camper Admin ziet alleen eigen camper
- Tokens verlopen na 7 dagen
- Tokens zijn eenmalig bruikbaar
