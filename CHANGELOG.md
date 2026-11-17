# Changelog

Alle wichtigen Änderungen an BlockerBetting. Die Versionsnummer steht unten in der Navigation.
Einträge mit **Datenbank** brauchen eine SQL-Migration aus `supabase/migrations/`.

## 1.8.1 – 17.11.2026

### Neu
- Changelog direkt in der App – erreichbar über die Versionsnummer in der Navigation.

## 1.8.0 – 17.11.2026

### Neu
- **Blackjack** im Spiele-Hub: 6 Decks, Dealer steht ab 17, Blackjack zahlt 3:2, Verdoppeln auf die ersten zwei Karten.
- Animiertes Austeilen, Dealer-Karten werden nacheinander aufgedeckt, Verlauf der letzten Runden.
- Laufende Runden werden nach dem Verlassen der Seite fortgesetzt.

### Sicherheit
- Kartendeck und verdeckte Dealer-Karte bleiben auf dem Server, jeder Zug wird serverseitig geprüft.

**Datenbank:** `007_games_blackjack.sql`

## 1.7.0 – 17.11.2026

### Neu
- Neuer Menüpunkt **Spiele (Beta)** mit **Roulette** (europäisch, eine Null).
- Chips auf Zahlen, Farben, Dutzende, Kolonnen und mehr setzen; Rückgängig, Leeren und Wiederholen.
- Animiertes Rad, Hervorhebung gewinnender Felder, letzte Zahlen.

### Sicherheit
- Die Zahl wird serverseitig mit kryptografischem Zufall gezogen, Einsatz und Gewinn in einem Schritt gebucht.

**Datenbank:** `006_games_roulette.sql`

## 1.6.0 – 17.11.2026

### Neu
- Abgelehnte Vorschläge zeigen alle Details inklusive Begründung.
- **Überarbeiten & neu einreichen:** abgelehnte oder zurückgezogene Vorschläge als neue Anfrage übernehmen und frei anpassen.

## 1.5.1 – 17.11.2026

### Neu
- Bei jeder Wette steht der Ersteller („von Anna“ bzw. „von dir“) – auf den Karten, der Detailseite und in der Admin-Übersicht.

## 1.5.0 – 17.11.2026

### Neu
- **Push-Benachrichtigungen:** Admins bei neuen Wett-Anfragen, Antragsteller bei Annahme oder Ablehnung. Aktivierbar im Profil.

### Behoben
- Anmelden und Registrieren per Enter-Taste funktioniert wieder.
- Absturz des Gewinner-Banners beim schnellen Seitenwechsel.

**Datenbank:** `005_push_notifications.sql` (plus Edge Function `send-push`, siehe README)

## 1.4.1 – 17.11.2026

### Verbessert
- Alle Zeiten werden in deutscher Zeit angezeigt und eingegeben – unabhängig von der Zeitzone des Geräts.

### Behoben
- Wetten galten nach dem Wettschluss noch ein bis zwei Stunden als „Live“; Restzeit und Auflöse-Recht waren entsprechend verschoben.

## 1.4.0 – 17.11.2026

### Neu
- **Wette vorschlagen:** Jeder kann Wetten mit Optionen, Quoten-Vorschlag und Wettschluss einreichen.
- **Anfragen** für Admins: prüfen, anpassen, genehmigen oder mit Begründung ablehnen.
- Der Ersteller einer Wette darf sie nach dem Wettschluss selbst auflösen und auszahlen.
- **Tagesbonus:** Jeden Morgen um 8 Uhr gibt es 20 Coins.

**Datenbank:** `003_bet_requests.sql`, `004_daily_bonus.sql`

## 1.3.0 – 17.11.2026

### Neu
- Laufbanner mit den Gewinnern der zuletzt entschiedenen Wette.

## 1.2.0 – 17.11.2026

### Verbessert
- App-Updates werden sofort übernommen, statt die zwischengespeicherte alte Version weiter anzuzeigen.

## 1.1.0 – 17.11.2026

### Neu
- Eigenes App-Icon, moderner Ladebildschirm, Versionsnummer und Autor in der Navigation.
- Komplett überarbeitetes Design mit hellem und dunklem Modus, neuer Startseite, Wettschein, Rangliste mit Podest und Statistiken.
- Betrieb unter eigener Subdomain.

### Behoben
- „Alle Wetten“ und weitere Links zur Startseite funktionieren wieder.

## 1.0.0 – 17.11.2026

### Neu
- Erste Version: Anmeldung über Supabase, 1.000 Start-Coins, Wetten mit festen Quoten, Meine Wetten, Rangliste, Profil.
- **Wetten verwalten** für Admins: anlegen, bearbeiten, schließen, auflösen und abbrechen.
- Installierbar als App (PWA), Hosting über GitHub Pages.

**Datenbank:** `001_initial.sql`, `002_fixed_odds.sql`
