# Woche 10, Nachtrag: End-to-End-Beispiel

Stand: 24.11.2026, Branch `woche11/pipeline`

**Frage:** Kommt ein konkreter Wert aus der Rohdatei unverändert bis in die Faktentabelle und die Prüfungen?

**Beispiel:** Samstag, 19.09.2026, 19 Uhr, Kanal App.

**Rahmen:** Nur gelesen, nichts geändert. Ziel ist das produktive Dataset `pizzeria_dwh` im Projekt `daeng-banlar01-x4q9`, europe-west6. Vor jeder BigQuery-Abfrage lief ein Dry Run (Bytes siehe unten).

## Station 1: Rohdatei

```bash
gcloud storage cat gs://daeng-banlar01-x4q9-raw/pizzeria/datenausschnitt_v1.csv | grep '2026-09-19' | grep 'App' | grep '19:'
```

Die Datei hat 289 Zeilen: eine Kopfzeile und 288 Datenzeilen. Für das Beispiel gibt es genau einen Treffer:

```
2026-09-19;Sa;19:00;App;4;3;9;;sonnig;24;
```

| datum | wochentag | stunde | quelle_kanal | bestellungen_angenommen | bestellungen_abgelehnt_app | pizzen | wetter_prognose_do | wetter_ist | temperatur_ist_c | event |
|---|---|---|---|---:|---:|---:|---|---|---:|---|
| 2026-09-19 | Sa | 19:00 | App | 4 | 3 | 9 | *(leer)* | sonnig | 24 | *(leer)* |

Die Datei beginnt mit einem BOM und hat Windows-Zeilenenden (CRLF). Nach dem letzten Feld `event` steht deshalb noch ein unsichtbares `\r`.

## Station 2: Staging `pizzeria_dwh.stg_datenausschnitt`

| datum | wochentag | stunde | quelle_kanal | bestellungen_angenommen | bestellungen_abgelehnt_app | pizzen | wetter_prognose_do | wetter_ist | temperatur_ist_c | event |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-09-19 | Sa | 19:00 | App | 4 | 3 | 9 | NULL | sonnig | 24 | NULL |

Alle Spalten sind vom Typ STRING, wie in `01_ddl.sql` vorgesehen. `TO_JSON_STRING(STRUCT(wetter_prognose_do, event))` ergibt `{"wetter_prognose_do":null,"event":null}`. Die leeren Felder sind also echtes NULL, kein leerer Text und kein `\r`. BigQuery hat die CRLF-Zeilenenden beim Laden als Zeilenende erkannt.

## Station 3: Dimensionen

**`dim_datum` (datum_id 20260919)**

| datum_id | datum | wochentag | ist_wochenende | kalenderwoche | monat | jahr | wetter_prognose_do | wetter_ist | temperatur_ist_c | event_name | ist_eventtag |
|---|---|---|---|---:|---:|---:|---|---|---:|---|---|
| 20260919 | 2026-09-19 | Sa | true | 38 | 9 | 2026 | NULL | sonnig | 24 | NULL | false |

**`dim_stunde` (stunde_id 19)**

| stunde_id | stunde_von | stunde_bis | tageszeit | ist_spitzenstunde | im_betrachtungsfenster |
|---:|---|---|---|---|---|
| 19 | 19:00:00 | 20:00:00 | Abend | true | true |

**`dim_kanal` (kanal_id 10)**

| kanal_id | kanal | kanal_gruppe | plattform | quellsystem | source_id |
|---:|---|---|---|---|---|
| 10 | App (nicht aufgeteilt) | App | NULL | Partner-Portal | Datenausschnitt |

## Station 4: Fakten `fakt_bestellung_stunde` mit `dim_bestellstatus`

Alle Zeilen mit `datum_id = 20260919`, `stunde_id = 19`, `kanal_id = 10`:

| status_id | status | absagegrund | grund_kategorie | anzahl_bestellungen | anzahl_pizzen | summe_durchlaufzeit_min |
|---:|---|---|---|---:|---:|---|
| 1 | angenommen | NULL | NULL | 4 | 9 | NULL |
| 5 | abgelehnt | ohne Angabe | unbekannt | 3 | NULL | NULL |

Das entspricht der Erwartung: eine Zeile mit Status 1, deren Bestellungen und Pizzen mit der CSV übereinstimmen, und eine Zeile mit Status 5, deren Anzahl gleich `bestellungen_abgelehnt_app` ist und deren Pizzen NULL sind. `summe_durchlaufzeit_min` ist wie bei allen Faktenzeilen NULL, das ist die bekannte Lücke aus Woche 10.

## Station 5: Prüfung, letzter Lauf in `pizzeria_dwh.pruefergebnisse`

Der letzte Lauf ist der Scheduler-Lauf vom 24.11.2026, 10:31:35 UTC (Execution `f2eaba7f-a882-4a3f-898c-d56628c29864`, siehe [zeitplan.md](zeitplan.md)).

| nr | pruefung | ergebnis | detail |
|---|---|---|---|
| 0 | Staging nicht leer | PASS | 288 Zeilen im Staging |
| 1a | Summe angenommene Bestellungen Fakt = Staging | PASS | Fakt 1294, Staging 1294 |
| 1b | Summe Pizzen Fakt = Staging | PASS | Fakt 2718, Staging 2718 |
| 2 | Keine doppelten Schluessel (datum, stunde, kanal, status) | PASS | 0 doppelte Schluessel |
| 3 | Keine verwaisten FKs | PASS | datum 0, stunde 0, kanal 0, status 0 |
| 6a | Faktenzeilen = Staging-Zeilen + Staging-Zeilen mit Absage | PASS | Fakt 432, erwartet 432 (Staging 288 + mit Absage 144) |
| 6b | Summe App-Absagen Fakt = Staging | PASS | Fakt 9, Staging 9 |
| Z1 | Zusatz: Wetter/Temperatur/Event/Wochentag pro Datum eindeutig | PASS | 0 Tage mit widerspruechlichen Werten |
| Z2 | Zusatz: Wochentag CSV = berechneter Wochentag in dim_datum | PASS | 0 Abweichungen |

Das Beispiel steckt in diesen Summen: 4 der 1294 angenommenen Bestellungen (1a), 9 der 2718 Pizzen (1b), 3 der 9 App-Absagen (6b) und 2 der 432 Faktenzeilen (6a).

## Abgleich von Station zu Station

| Wert | Rohdatei | Staging | Dimension / Fakt | stimmt überein |
|---|---|---|---|---|
| **Bestellungen angenommen** | 4 | `4` | Fakt, Status 1: `anzahl_bestellungen` 4 | ja |
| **Pizzen** | 9 | `9` | Fakt, Status 1: `anzahl_pizzen` 9 | ja |
| **Absagen (App)** | 3 | `3` | Fakt, Status 5: `anzahl_bestellungen` 3, `anzahl_pizzen` NULL | ja |
| **Wetter (ist)** | sonnig | `sonnig` | `dim_datum.wetter_ist` sonnig | ja |
| Wetter (Prognose) | leer | NULL | `dim_datum.wetter_prognose_do` NULL | ja |
| Temperatur | 24 | `24` | `dim_datum.temperatur_ist_c` 24 (INT64) | ja |
| **Event** | leer | NULL | `dim_datum.event_name` NULL, `ist_eventtag` false | ja |
| Wochentag | Sa | `Sa` | `dim_datum.wochentag` Sa, `ist_wochenende` true | ja |
| Stunde | 19:00 | `19:00` | `dim_stunde` 19: 19:00 bis 20:00, Abend, Spitzenstunde | ja |
| Kanal | App | `App` | `dim_kanal` 10: App (nicht aufgeteilt), Gruppe App | ja |
| Prüfung | – | – | letzter Lauf: 9 × PASS | ja |

## Job-IDs und Bytes (Beleg)

Die Rohdatei wurde mit `gcloud storage cat` gelesen. Dafür gibt es keinen BigQuery-Job und keine Job-ID.

| Station | Abfrage | Dry Run (Bytes) | Job-ID |
|---|---|---:|---|
| 2 | Staging | 17 854 | `w11_e2e_q2_staging_20261124_124842` |
| 3 | `dim_datum` | 781 | `w11_e2e_q3a_dim_datum_20261124_124842` |
| 3 | `dim_stunde` | 410 | `w11_e2e_q3b_dim_stunde_20261124_124842` |
| 3 | `dim_kanal` | 343 | `w11_e2e_q3c_dim_kanal_20261124_124842` |
| 4 | Fakten mit `dim_bestellstatus` | 19 799 | `w11_e2e_q4_fakt_20261124_124842` |
| 5 | letzter Lauf `pruefergebnisse` | 1 628 | `w11_e2e_q5_pruefung_20261124_124842` |

Ansehen mit `bq show -j --location=europe-west6 <job-id>`.

## Hinweise

- **Gleiche Zeile wie in den Gegentests:** Die Status-5-Zeile dieses Beispiels (20260919, 19, 10, 5) ist genau die Zeile, die in den Gegentests gelöscht wurde. Das geschah aber nur in `pizzeria_dwh_test`, und dort wurde sie danach jedes Mal wiederhergestellt. In `pizzeria_dwh` ist sie unverändert vorhanden.
- **CRLF:** Ein unsichtbares `\r` am Ende der Zeilen würde mit `NULLIF(TRIM(event), '')` vermutlich ohnehin verschwinden. Es kommt aber gar nicht erst ins Staging (siehe Station 2).

## Fazit

Für Samstag, 19.09.2026, 19 Uhr, App stimmen Bestellungen (4), Pizzen (9), Absagen (3), Wetter (sonnig, 24 °C) und Event (keins) von der Rohdatei über Staging und Dimensionen bis in die Faktentabelle überein. Die Absage-Zeile ist wie vorgesehen eine eigene Zeile mit Status 5 und Pizzen NULL, und der letzte Prüflauf auf `pizzeria_dwh` meldet 9 × PASS.
