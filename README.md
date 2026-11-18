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
| Wetten kopieren | Über **„Kopieren“** wird eine bestehende Wette zur Vorlage: Titel, Beschreibung, Optionen und Quoten werden übernommen und sind frei anpassbar. Admins legen die Kopie direkt an, Spieler reichen sie als Wett-Anfrage ein. |
| Ersteller-Recht | Der Ersteller einer Wette – bei genehmigten Anfragen der Antragsteller – darf sie **nach dem Wettschluss** selbst auflösen und auszahlen. Admins können jederzeit auflösen. |
| Tagesbonus | Jeden Morgen um **8:00 Uhr** (deutsche Zeit) erhält jeder Spieler **20 Coins** – per `pg_cron`-Job direkt in Supabase, höchstens einmal pro Tag. |
| Push-Benachrichtigungen | Admins erhalten eine Push-Nachricht bei neuen Wett-Anfragen, Antragsteller bei Annahme oder Ablehnung – auch im Browser ohne Installation (iPhone: nur als Home-Bildschirm-App). |
| Spiele (Beta) | Menüpunkt **„Spiele“** mit **Roulette** und **Blackjack** (6 Decks, Dealer steht ab 17, Blackjack 3:2, Verdoppeln) sowie **Poor Mode** (alle 60 s ein Coin zum Einsammeln). Roulette (europäisch, eine Null): Chips auf Zahlen, Farben, Dutzende usw. setzen und das Rad drehen. Die Zahl wird serverseitig zufällig gezogen, Einsatz und Gewinn in derselben Transaktion verbucht. |

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
- Jeden Morgen um 8 Uhr gibt es 20 Coins Tagesbonus.
- Vorgeschlagene Wetten gehen erst nach Freigabe durch einen Admin online. Der Antragsteller entscheidet sie nach dem Wettschluss.

## Changelog und Versionen

Alle Änderungen stehen in [`CHANGELOG.md`](CHANGELOG.md). Die Datei wird beim Build in die App eingebettet und ist dort unter **Navigation → Versionsnummer** (`/changelog`) zu sehen.

Für ein neues Release:
1. `<Version>` in `src/BlockerBetting/BlockerBetting.csproj` erhöhen.
2. Oben in `CHANGELOG.md` einen Abschnitt `## <Version> – <Datum>` mit `### Neu` / `### Verbessert` / `### Behoben` ergänzen (bei SQL-Änderungen eine Zeile `**Datenbank:** ...`).

## Datenbank-Migrationen

Die SQL-Dateien in [`supabase/migrations/`](supabase/migrations/) werden im Supabase SQL Editor **in numerischer Reihenfolge** ausgeführt; bei Updates nur die neuen:

| Datei | Inhalt |
|---|---|
| `001_initial.sql` | Grundschema, RLS, Profile-Trigger |
| `002_fixed_odds.sql` | Feste Quoten |
| `003_bet_requests.sql` | Wett-Anfragen, Auflösen durch den Ersteller |
| `004_daily_bonus.sql` | Täglicher Coin-Bonus um 8 Uhr (benötigt die Erweiterung `pg_cron`) |
| `005_push_notifications.sql` | Push-Abos und Benachrichtigungen bei Wett-Anfragen (benötigt `pg_net` und Vault) |
| `006_games_roulette.sql` | Spiele (Beta): Roulette mit serverseitiger Ziehung |
| `007_games_blackjack.sql` | Spiele (Beta): Blackjack – Deck und Spielstand nur serverseitig |
| `008_poor_mode.sql` | Poor Mode: eingesammelte Coins gutschreiben (1 Coin pro Klick) |

## Push-Benachrichtigungen

Admins werden bei **neuen Wett-Anfragen** benachrichtigt, Antragsteller, sobald ihre Anfrage **angenommen oder abgelehnt** wurde. Jeder aktiviert Push selbst unter **Profil → Push-Benachrichtigungen** (pro Gerät/Browser).

```
App (Service Worker) ──Abo──▶ push_subscriptions ◀── Edge Function send-push ◀── pg_net-Trigger auf bet_requests
                     ◀──────────── Web Push (VAPID) ──────────┘
```

| Plattform | Unterstützung |
|---|---|
| Android, Windows, macOS (Chrome, Edge, Firefox, Safari) | auch ohne Installation im Browser |
| iPhone / iPad | nur, wenn die App über „Teilen → Zum Home-Bildschirm“ installiert ist (ab iOS 16.4) |

**Einrichtung (einmalig):**

1. **VAPID-Schlüssel erzeugen** (lokal, Node.js):
   ```bash
   npx web-push generate-vapid-keys
   ```
2. **GitHub-Secrets** anlegen (*Settings → Secrets and variables → Actions*):
   - `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`
   - `VAPID_SUBJECT` – z. B. `mailto:du@firma.de`
   - `PUSH_WEBHOOK_SECRET` – ein langes zufälliges Geheimnis, z. B. aus `openssl rand -hex 32`
   - `SUPABASE_ACCESS_TOKEN` (supabase.com → Account → Access Tokens) und `SUPABASE_PROJECT_REF` (der Teil `abcdefgh` aus `https://abcdefgh.supabase.co`)
3. **Edge Function deployen:** Workflow *Deploy Supabase Edge Functions* unter *Actions* manuell starten. Er setzt die Function-Secrets und deployt `send-push`. Alternativ lokal per CLI:
   ```bash
   supabase secrets set --project-ref <ref> VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... VAPID_SUBJECT=... PUSH_WEBHOOK_SECRET=...
   supabase functions deploy send-push --project-ref <ref> --no-verify-jwt
   ```
4. **Vault-Werte** im Supabase SQL Editor anlegen (damit die Datenbank die Function aufrufen darf):
   ```sql
   select vault.create_secret('https://abcdefgh.supabase.co', 'project_url');
   select vault.create_secret('<gleicher Wert wie PUSH_WEBHOOK_SECRET>', 'push_webhook_secret');
   ```
5. **Migration** `005_push_notifications.sql` ausführen und die App neu deployen (Push auf `main` bzw. *Deploy to GitHub Pages* neu starten), damit der öffentliche VAPID-Schlüssel in der App landet.

Fehlersuche: Aufrufe der Datenbank stehen in `select * from net._http_response order by created desc;`, Logs der Function im Supabase-Dashboard unter *Edge Functions → send-push → Logs*.

## Roadmap / Ideen

- Realtime-Updates über Supabase Realtime
- Mindestguthaben / Comeback-Bonus
- Statistiken & Historie pro Spieler
