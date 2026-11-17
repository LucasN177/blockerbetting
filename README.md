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
| Quoten | **Pari-mutuel / Totalisator:** Alle Einsätze eines Events landen in einem Topf. Gewinner teilen sich den gesamten Topf proportional zu ihrem Einsatz. Hat niemand auf die richtige Option gesetzt, werden alle Einsätze erstattet. |
| Rangliste | Leaderboard aller Spieler nach Coins. |
| Admin | Admins können Events anlegen, Wetten schließen, Events auflösen oder abbrechen (Abbruch = Rückerstattung). |

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

### Datenmodell

| Tabelle / View | Inhalt |
|---|---|
| `profiles` | 1:1 zu `auth.users`: `display_name`, `coins`, `is_admin` |
| `events` | Titel, Beschreibung, Status, Wettschluss, Gewinner-Option |
| `event_options` | Antwortoptionen je Event |
| `bets` | Einsatz eines Users auf eine Option inkl. späterer Auszahlung |
| `event_option_pools` (View) | Summe der Einsätze & Anzahl Wetten pro Option (für Quoten) |

RPC-Funktionen: `place_bet`, `create_event`, `lock_event`, `resolve_event`, `cancel_event`.

Das vollständige Schema liegt in [`supabase/schema.sql`](supabase/schema.sql).

## Projektstruktur

```
.
├── .github/workflows/deploy.yml   # Build & Deploy nach GitHub Pages
├── supabase/schema.sql            # Tabellen, RLS, Trigger, RPC-Funktionen
├── BlockerBetting.slnx
└── src/BlockerBetting/            # Blazor WASM PWA
    ├── Models/                    # Postgrest-Modelle
    ├── Services/                  # Supabase-Session, Auth-State, Betting-Service
    ├── Layout/                    # MudBlazor-Layout & Navigation
    ├── Pages/                     # Events, Event-Details, Meine Wetten, Rangliste, Admin, Login
    └── wwwroot/                   # index.html, PWA-Manifest, Service Worker, appsettings.json
```

---

## Einrichtung

### 1. Supabase-Projekt vorbereiten

1. Projekt auf [supabase.com](https://supabase.com) anlegen (oder bestehendes nutzen).
2. Im **SQL Editor** den Inhalt von [`supabase/schema.sql`](supabase/schema.sql) ausführen.
3. Unter **Authentication → URL Configuration**:
   - *Site URL*: `https://<github-user>.github.io/blockerbetting/`
   - *Redirect URLs*: zusätzlich `https://localhost:7174/` bzw. die lokale Dev-URL eintragen.
4. Optional: Unter **Authentication → Providers → Email** „Confirm email" deaktivieren, wenn intern keine Bestätigungsmail nötig ist.
5. Ersten Admin festlegen (nach der Registrierung):
   ```sql
   update public.profiles set is_admin = true where id = (select id from auth.users where email = 'du@firma.de');
   ```

### 2. GitHub konfigurieren

- **Secrets** (*Settings → Secrets and variables → Actions*):
  - `SUPABASE_URL` – z. B. `https://abcdefgh.supabase.co`
  - `SUPABASE_KEY` – der **anon / publishable key**

  > ⚠️ Niemals den `service_role`-Key verwenden! Der Key wird beim Build in die ausgelieferte `appsettings.json` geschrieben und ist damit öffentlich im Browser sichtbar. Das ist beim anon-Key so vorgesehen – die Sicherheit kommt aus Row Level Security.

- **GitHub Pages** (*Settings → Pages*): als Source **„GitHub Actions"** auswählen.

Danach baut und deployt jeder Push auf `main` die App automatisch nach `https://<github-user>.github.io/blockerbetting/`.

### 3. Lokal entwickeln

Voraussetzung: [.NET 10 SDK](https://dotnet.microsoft.com/download).

Lokale Zugangsdaten in `src/BlockerBetting/wwwroot/appsettings.Development.json` ablegen (ist per `.gitignore` ausgeschlossen):

```json
{
  "Supabase": {
    "Url": "https://abcdefgh.supabase.co",
    "Key": "<anon key>"
  }
}
```

Starten:

```bash
dotnet watch --project src/BlockerBetting
```

Release-Build wie in der Pipeline:

```bash
dotnet publish src/BlockerBetting -c Release -o publish
```

## Deployment-Details

Der Workflow [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml):

1. schreibt `SUPABASE_URL` / `SUPABASE_KEY` in `wwwroot/appsettings.json`,
2. setzt `<base href>` auf `/<repo-name>/` (vor dem Publish, damit die Integritäts-Hashes des Service Workers stimmen),
3. führt `dotnet publish` aus,
4. kopiert `index.html` nach `404.html` (SPA-Routing auf GitHub Pages) und legt `.nojekyll` an,
5. deployt das Ergebnis per `actions/deploy-pages`.

## Spielregeln (Kurzfassung)

- Jeder startet mit 1.000 Coins. Coins können nicht unter 0 fallen.
- Mehrere Wetten pro Event (auch auf verschiedene Optionen) sind erlaubt.
- Nach Wettschluss bzw. wenn ein Admin das Event sperrt, sind keine Wetten mehr möglich.
- Auszahlung bei Auflösung: `Einsatz × Gesamttopf ÷ Topf der Gewinner-Option` (abgerundet).
- Abgebrochene Events werden vollständig erstattet.

## Roadmap / Ideen

- Realtime-Updates der Quoten über Supabase Realtime
- Wöchentlicher Coin-Bonus / Mindestguthaben
- Events von allen Usern vorschlagen lassen (mit Admin-Freigabe)
- Statistiken & Historie pro Spieler
