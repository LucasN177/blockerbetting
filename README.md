# BlockerBetting 🎲

Interne Wettplattform für das Team: Jede Person hat einen eigenen Account, startet mit einem Coin-Guthaben und kann auf verschiedene Events (z. B. „Wer gewinnt das Kicker-Turnier?", „Wird das Release diese Woche fertig?") Coins setzen. Es wird **ausschließlich mit virtuellen Coins** gespielt – kein Echtgeld.

- **Frontend:** Blazor WebAssembly (.NET 10) + [MudBlazor](https://mudblazor.com), installierbar als **PWA**
- **Backend:** [Supabase](https://supabase.com) (Auth, Postgres, Row Level Security, RPC-Funktionen)
- **Hosting:** GitHub Pages, automatisches Deployment per GitHub Actions bei jedem Push auf `main`

---

## Features

| Bereich | Beschreibung |
|---|---|
| Accounts | Registrierung & Login per E-Mail/Passwort über Supabase Auth. Beim Registrieren wird automatisch ein Profil mit **1.000 Start-Coins** angelegt. |
| Events | Events mit beliebig vielen Antwortoptionen, optionalem Wettschluss und Status `open` → `locked` → `resolved` (oder `cancelled`). |
| Wetten | Coins auf eine Option eines offenen Events setzen. Guthaben wird serverseitig atomar geprüft und abgebucht. |
| Quoten | **Feste Quoten**, die Admins pro Option manuell festlegen. Jede Wette speichert die Quote zum Zeitpunkt der Abgabe; spätere Quotenänderungen gelten nur für neue Wetten. Gewinn = `Einsatz × Quote` (abgerundet). |
| Rangliste | Leaderboard aller Spieler nach Coins. |
| Admin | Menüpunkt **„Wetten verwalten“**: Wetten mit Optionen & Quoten anlegen und bearbeiten, schließen/wieder öffnen, Gewinner festlegen und auszahlen oder abbrechen (Abbruch = Rückerstattung). |
| Wett-Anfragen | Jeder Spieler kann unter **„Wette vorschlagen“** eine Wette mit Optionen, Quoten-Vorschlag und Wettschluss einreichen. Admins prüfen sie unter **„Anfragen“**, passen sie bei Bedarf an und genehmigen oder lehnen sie (mit Begründung) ab. |
| Ersteller-Recht | Der Ersteller einer Wette – bei genehmigten Anfragen der Antragsteller – darf sie **nach dem Wettschluss** selbst auflösen und auszahlen. Admins können jederzeit auflösen. |

## Architektur

```
┌──────────────────────────────┐        HTTPS (anon key + JWT)       ┌───────────────────────────┐
│  Blazor WASM PWA (MudBlazor) │  ─────────────────────────────────▶ │  Supabase                 │
│  gehostet auf GitHub Pages   │                                      │  • Auth (E-Mail/Passwort) │
│                              │  ◀───────────────────────────────── │  • Postgres + RLS         │
└──────────────────────────────┘                                      │  • RPCs: place_bet, ...   │
                                                                      └───────────────────────────┘
```

Die App ist rein statisch – es gibt keinen eigenen Server. Sämtliche Geschäftslogik, die Coins verändert (Wetten platzieren, Events auflösen), läuft in **Postgres-Funktionen (`security definer`)**. Clients haben keine direkten Schreibrechte auf `bets`, `events` oder das Coin-Guthaben; Row Level Security verhindert Manipulation aus dem Browser.
---

## Spielregeln (Kurzfassung)

- Jeder startet mit 1.000 Coins. Coins können nicht unter 0 fallen.
- Mehrere Wetten pro Event (auch auf verschiedene Optionen) sind erlaubt.
- Nach Wettschluss bzw. solange ein Admin die Wette geschlossen hat, sind keine Wetten mehr möglich.
- Auszahlung bei Gewinn: `Einsatz × Quote bei Abgabe` (abgerundet). Verlorene Einsätze verfallen.
- Abgebrochene Events werden vollständig erstattet.
- Vorgeschlagene Wetten gehen erst nach Freigabe durch einen Admin online. Der Antragsteller entscheidet sie nach dem Wettschluss.

## Datenbank-Migrationen

Die SQL-Dateien in [`supabase/migrations/`](supabase/migrations/) werden im Supabase SQL Editor **in numerischer Reihenfolge** ausgeführt; bei Updates nur die neuen:

| Datei | Inhalt |
|---|---|
| `001_initial.sql` | Grundschema, RLS, Profile-Trigger |
| `002_fixed_odds.sql` | Feste Quoten |
| `003_bet_requests.sql` | Wett-Anfragen, Auflösen durch den Ersteller |

## Roadmap / Ideen

- Realtime-Updates über Supabase Realtime
- Wöchentlicher Coin-Bonus / Mindestguthaben
- Statistiken & Historie pro Spieler
