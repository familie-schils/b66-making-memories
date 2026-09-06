# B66 – Making Memories

De actieve applicatie-entrypoint is `/home/runner/work/b66-making-memories/b66-making-memories/index.html`.

## Structuur

- `/home/runner/work/b66-making-memories/b66-making-memories/index.html` — hoofdscherm en HTML-structuur
- `/home/runner/work/b66-making-memories/b66-making-memories/assets/css/app.css` — centrale styling
- `/home/runner/work/b66-making-memories/b66-making-memories/assets/js/main.js` — app-initialisatie en navigatie
- `/home/runner/work/b66-making-memories/b66-making-memories/assets/js/features/` — opgesplitste logica per domein
- `/home/runner/work/b66-making-memories/b66-making-memories/assets/js/api.js` — Supabase-datatoegang

## Opmerking over de versie-HTML-bestanden

De bestanden zoals `B66_Making_Memories_v0.8.5_eindkm_opslaan.html` en vergelijkbare versies blijven in de repository als historische snapshots. Ze zijn niet langer de primaire bron; verdere ontwikkeling gebeurt vanuit `index.html` en de assets-map.


## Versiebeheer en updates

- De app probeert eerst `/home/runner/work/b66-making-memories/b66-making-memories/assets/meta/sync-releases.json` te laden en valt alleen terug op `/home/runner/work/b66-making-memories/b66-making-memories/assets/meta/releases.json` als de sync-metadata nog ontbreekt.
- `.github/workflows/sync-test-agent-release.yml` synchroniseert op `main` automatisch `test-agent.html` naar `index.html`, verhoogt het patchversienummer en schrijft commit-onderwerpen weg naar de changelog.
- In de app worden deze gegevens getoond in de header (`Versie`) en in het scherm `Wat is nieuw?` (laatste 5 versies).
