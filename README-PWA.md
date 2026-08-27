# Making Memories – PWA Documentatie

## Gewijzigde en nieuwe bestanden

| Bestand | Type | Omschrijving |
|---|---|---|
| `test-agent.html` | Gewijzigd | Manifest-link, iOS-meta-tags en service-worker-registratie toegevoegd |
| `manifest.json` | Nieuw | Web App Manifest voor Android/Chrome install-prompt |
| `sw.js` | Nieuw | Service Worker – offline cache + PWA-vereiste |
| `assets/icons/icon-192.png` | Nieuw | Placeholder app-icoon 192 × 192 px (vervang door echte branding) |
| `assets/icons/icon-512.png` | Nieuw | Placeholder app-icoon 512 × 512 px (vervang door echte branding) |

---

## De app toevoegen op **Android**

1. Open de app in **Chrome** (of een andere Chromium-browser).
2. Wacht een paar seconden; Chrome toont automatisch een banner **"Toevoegen aan startscherm"**  
   *of* tik op de drie puntjes (⋮) rechts bovenaan → **"Aan startscherm toevoegen"**.
3. Geef desgewenst een naam op en tik op **Toevoegen**.
4. Het app-icoon verschijnt op het startscherm; openen start de app in standalone-modus (zonder adresbalk).

---

## De app toevoegen op **iPhone / iPad**

1. Open de app in **Safari** (iOS vereist Safari voor "Zet op beginscherm").
2. Tik op het **Deel-icoon** (vierkantje met pijl omhoog) onderaan de adresbalk.
3. Scroll naar beneden in het deelmenu en tik op **"Zet op beginscherm"**.
4. Pas de naam aan indien gewenst en tik op **"Voeg toe"**.
5. Het icoon verschijnt op het beginscherm; openen start de app fullscreen zonder Safari-interface.

---

## Testscenario's

### TS-01 – Manifest aanwezig en geldig
| Stap | Verwacht resultaat |
|---|---|
| Open DevTools → tabblad *Application* → *Manifest* | Naam "Making Memories", theme-color #2E7D32, beide iconen zichtbaar |

### TS-02 – Android install-prompt (Chrome)
| Stap | Verwacht resultaat |
|---|---|
| Open `test-agent.html` via HTTPS in Chrome Android | Na ~5 s verschijnt de "Toevoegen aan startscherm"-banner |
| Tik op "Toevoegen" | Icoon staat op het startscherm |
| Open via startscherm-icoon | App opent zonder adresbalk (standalone) |

### TS-03 – iOS "Zet op beginscherm" (Safari)
| Stap | Verwacht resultaat |
|---|---|
| Open `test-agent.html` in Safari op iPhone/iPad | Pagina laadt normaal |
| Deel → "Zet op beginscherm" → Voeg toe | Icoon staat op het beginscherm |
| Open via beginscherm-icoon | App opent fullscreen, geen Safari-werkbalk |
| Status-balk kleur | Donker/transparant (black-translucent) |

### TS-04 – Service Worker geregistreerd
| Stap | Verwacht resultaat |
|---|---|
| DevTools → *Application* → *Service Workers* | `sw.js` staat geregistreerd en actief |

### TS-05 – Offline fallback
| Stap | Verwacht resultaat |
|---|---|
| Verbreek internetverbinding na eerste bezoek | `test-agent.html` laadt nog steeds (uit cache) |

### TS-06 – Geen invloed op productie
| Stap | Verwacht resultaat |
|---|---|
| Open `index.html` | Geen manifest-link, geen service worker |
| Open andere versie-HTML-bestanden | Geen PWA-functionaliteit actief |

---

## Iconen vervangen (productie-klaar maken)

Vervang de placeholder-iconen door echte branding-afbeeldingen:

```
assets/icons/icon-192.png   →  192 × 192 px, PNG, transparante achtergrond of #2E7D32
assets/icons/icon-512.png   →  512 × 512 px, PNG, maskable (veilige zone centraal)
```

Gebruik [maskable.app/editor](https://maskable.app/editor) om te controleren of het icoon correct wordt bijgesneden op Android.
