# Woche 11, Teil 1: Wiederholbarkeit

Stand: 24.11.2026, Branch `woche11/pipeline`

**Frage:** Liefert die Pipeline `sql/pizzeria_star_schema/01` bis `03` (plus Checks `04`) zweimal hintereinander dasselbe Ergebnis?

**Rahmen:** eigener Testdatensatz `pizzeria_dwh_test` im Projekt `daeng-banlar01-x4q9`, Location europe-west6. `pizzeria_dwh` wird nicht verändert (Gegenprobe siehe unten). Beide Läufe lesen dieselbe Rohdatei `gs://daeng-banlar01-x4q9-raw/pizzeria/datenausschnitt_v1.csv`.

## Vorgehen

1. **Skript** `scripts/run_pipeline.sh <dataset>`: Es kopiert `01_ddl.sql`, `02_dimensionen.sql`, `03_elt.sql` und `04_checks.sql` in einen temporären Ordner. In den Kopien ersetzt es `pizzeria_dwh.` durch `<dataset>.`, nur mit Punkt, damit aus `pizzeria_dwh_test` nicht `pizzeria_dwh_test_test` wird. Dann führt es die Kopien der Reihe nach mit `bq query --use_legacy_sql=false --location=europe-west6` aus.
   - `set -euo pipefail`: Das Skript bricht beim ersten Fehler ab.
   - Die Originaldateien bleiben unverändert.
   - Jeder Schritt bekommt eine feste Job-ID `pipeline_<dataset>_<lauf-id>_<datei>`.
   - Schutz: Das Skript bricht bei `pizzeria_dwh` als Ziel und bei Namen mit anderen Zeichen als `A-Z a-z 0-9 _` ab.
   - Vorab geprüft: 43 Ersetzungen (01: 10, 02: 3, 03: 5, 04: 25), danach kein `pizzeria_dwh.` übrig und kein `_test_test`. Die einzige Stelle ohne Punkt ist ein Kommentar in `01_ddl.sql:3`.
2. **Dataset anlegen** (einmalig).
3. **Lauf 1**, danach Fingerabdruck: Zeilenzahl und Prüfsumme je Tabelle, Prüfsumme der Faktentabelle und Abfrage A aus `04_checks.sql`.
4. **Lauf 2** mit exakt demselben Befehl, danach derselbe Fingerabdruck.
5. **Vergleich** Lauf 1 gegen Lauf 2.
6. **Gegenprobe:** `pizzeria_dwh.__TABLES__` (Zeilenzahl, letzte Änderung) vor Lauf 1 und nach Lauf 2.

## Befehle

```bash
# 2. Dataset anlegen
bq mk --dataset --location=europe-west6 daeng-banlar01-x4q9:pizzeria_dwh_test

# 3. und 4. Lauf 1 und Lauf 2 (identischer Befehl)
scripts/run_pipeline.sh pizzeria_dwh_test
```

Fingerabdruck (nur lesend, nach jedem Lauf):

```sql
-- Zeilenzahl und Prüfsumme je Tabelle (Prüfsumme für die Dimensionen und Staging als Zusatz)
SELECT 'stg_datenausschnitt' AS tabelle, COUNT(*) AS zeilen, BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS pruefsumme FROM pizzeria_dwh_test.stg_datenausschnitt t
UNION ALL SELECT 'dim_datum',              COUNT(*), BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) FROM pizzeria_dwh_test.dim_datum t
UNION ALL SELECT 'dim_stunde',             COUNT(*), BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) FROM pizzeria_dwh_test.dim_stunde t
UNION ALL SELECT 'dim_kanal',              COUNT(*), BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) FROM pizzeria_dwh_test.dim_kanal t
UNION ALL SELECT 'dim_bestellstatus',      COUNT(*), BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) FROM pizzeria_dwh_test.dim_bestellstatus t
UNION ALL SELECT 'fakt_bestellung_stunde', COUNT(*), BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) FROM pizzeria_dwh_test.fakt_bestellung_stunde t
ORDER BY tabelle;

-- Prüfsumme Faktentabelle
SELECT COUNT(*), BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) FROM pizzeria_dwh_test.fakt_bestellung_stunde t;

-- Abfrage A: Abschnitt "-- A)" bis vor "-- B)" aus 04_checks.sql, mit derselben Ersetzung pizzeria_dwh. -> pizzeria_dwh_test.
```

## Ergebnis: Lauf 1 gegen Lauf 2

Lauf 1: Lauf-ID `20261124_095116`. Lauf 2: Lauf-ID `20261124_095205`. Beide Zeiten sind Ortszeit.

### Zeilenzahlen und Prüfsummen

| Tabelle | Zeilen Lauf 1 | Zeilen Lauf 2 | Prüfsumme Lauf 1 | Prüfsumme Lauf 2 | gleich |
|---|---:|---:|---:|---:|:---:|
| stg_datenausschnitt | 288 | 288 | -2866223820452786722 | -2866223820452786722 | ja |
| dim_datum | 12 | 12 | 4924310663659963680 | 4924310663659963680 | ja |
| dim_stunde | 12 | 12 | 2421456124061062899 | 2421456124061062899 | ja |
| dim_kanal | 6 | 6 | -3230980446158413867 | -3230980446158413867 | ja |
| dim_bestellstatus | 5 | 5 | 6577766013098485281 | 6577766013098485281 | ja |
| **fakt_bestellung_stunde** | **432** | **432** | **770431044262388904** | **770431044262388904** | **ja** |

### Abfrage A aus 04_checks.sql

| Nr | Prüfung | Lauf 1 | Lauf 2 | Detail (in beiden Läufen gleich) |
|---|---|:---:|:---:|---|
| 1a | Summe angenommene Bestellungen Fakt = Staging | PASS | PASS | Fakt 1294, Staging 1294 |
| 1b | Summe Pizzen Fakt = Staging | PASS | PASS | Fakt 2718, Staging 2718 |
| 2 | Keine doppelten Schlüssel | PASS | PASS | 0 doppelte Schlüssel |
| 3 | Keine verwaisten FKs | PASS | PASS | datum 0, stunde 0, kanal 0, status 0 |
| 6a | Faktenzeilen = 432 | PASS | PASS | gesamt 432: Kasse angen. 144, App angen. 144, App abgel. 144, Kasse Absage-Zeilen 0 |
| 6b | Summe App-Absagen = 9 | PASS | PASS | Summe 9 |
| Z1 | Wetter/Temperatur/Event/Wochentag pro Datum eindeutig | PASS | PASS | 0 Tage mit widersprüchlichen Werten |
| Z2 | Wochentag CSV = berechneter Wochentag | PASS | PASS | 0 Abweichungen |

### Verhalten der einzelnen Schritte

| Schritt | Lauf 1 | Lauf 2 |
|---|---|---|
| 01_ddl (`CREATE TABLE IF NOT EXISTS`) | 6 Tabellen angelegt („Created“) | nichts angelegt, keine Fehler |
| 02_dimensionen (MERGE) | affected rows 12 / 6 / 5 | affected rows 12 / 6 / 5 |
| 03_elt (`LOAD DATA OVERWRITE` + MERGE) | Staging ersetzt, affected rows 12 / 432 | Staging ersetzt, affected rows 12 / 432 |
| 04_checks | alle PASS | alle PASS |
| Skript-Ende | „Fertig“, Exit-Code 0 | „Fertig“, Exit-Code 0 |

„affected rows“ zählt bei MERGE eingefügte und aktualisierte Zeilen zusammen. In Lauf 1 sind es Inserts (leere Tabellen). In Lauf 2 sind es Updates auf dieselben Werte: Die Zeilenzahlen bleiben gleich, und die Prüfsummen sind identisch.

## Gegenprobe: pizzeria_dwh unverändert

`SELECT table_id, row_count, last_modified_time FROM pizzeria_dwh.__TABLES__`, vor Lauf 1 und nach Lauf 2:

| Tabelle | Zeilen vorher | Zeilen nachher | zuletzt geändert, vorher | zuletzt geändert, nachher |
|---|---:|---:|---|---|
| dim_bestellstatus | 5 | 5 | 2026-11-12 13:55:51 UTC | 2026-11-12 13:55:51 UTC |
| dim_datum | 12 | 12 | 2026-11-12 13:57:36 UTC | 2026-11-12 13:57:36 UTC |
| dim_kanal | 6 | 6 | 2026-11-12 13:55:50 UTC | 2026-11-12 13:55:50 UTC |
| dim_stunde | 12 | 12 | 2026-11-12 13:55:48 UTC | 2026-11-12 13:55:48 UTC |
| fakt_bestellung_stunde | 432 | 432 | 2026-11-12 13:57:38 UTC | 2026-11-12 13:57:38 UTC |
| stg_datenausschnitt | 288 | 288 | 2026-11-12 13:57:35 UTC | 2026-11-12 13:57:35 UTC |

## Job-IDs (Beleg)

Projekt `daeng-banlar01-x4q9`, Location europe-west6. Ansehen mit `bq show -j --location=europe-west6 <job-id>`.

| Zweck | Lauf 1 | Lauf 2 |
|---|---|---|
| 01_ddl | `pipeline_pizzeria_dwh_test_20261124_095116_01_ddl` | `pipeline_pizzeria_dwh_test_20261124_095205_01_ddl` |
| 02_dimensionen | `pipeline_pizzeria_dwh_test_20261124_095116_02_dimensionen` | `pipeline_pizzeria_dwh_test_20261124_095205_02_dimensionen` |
| 03_elt | `pipeline_pizzeria_dwh_test_20261124_095116_03_elt` | `pipeline_pizzeria_dwh_test_20261124_095205_03_elt` |
| 04_checks | `pipeline_pizzeria_dwh_test_20261124_095116_04_checks` | `pipeline_pizzeria_dwh_test_20261124_095205_04_checks` |
| Fingerabdruck Zeilen | `fingerprint_pizzeria_dwh_test_lauf1_20261124_095150_zeilen` | `fingerprint_pizzeria_dwh_test_lauf2_20261124_095241_zeilen` |
| Fingerabdruck Fakt | `fingerprint_pizzeria_dwh_test_lauf1_20261124_095150_fakt` | `fingerprint_pizzeria_dwh_test_lauf2_20261124_095241_fakt` |
| Fingerabdruck Abfrage A | `fingerprint_pizzeria_dwh_test_lauf1_20261124_095150_checkA` | `fingerprint_pizzeria_dwh_test_lauf2_20261124_095241_checkA` |

Gegenprobe `pizzeria_dwh` vorher: `bqjob_r5154b031f23ef573_000001a20cbfdcd7_1`. Die Job-ID der Gegenprobe nachher wurde nicht festgehalten.

## Grenzen

- **Prüfsumme und Duplikate:** `BIT_XOR` hängt nicht von der Reihenfolge der Zeilen ab, also ist es egal, in welcher Reihenfolge `LOAD DATA` die Zeilen schreibt. Dafür heben sich zwei identische Zeilen gegenseitig auf. Duplikate erkennt die Prüfsumme deshalb allein nicht. Das übernehmen `COUNT(*)` (432) und Check 2 (0 doppelte Schlüssel).
- **Gleiche Eingabe:** Getestet ist die Wiederholung mit unveränderter Rohdatei. Fallen in einer neuen CSV-Version Zeilen weg, bleiben sie in `dim_datum` und `fakt_bestellung_stunde` stehen, weil die MERGEs kein `WHEN NOT MATCHED BY SOURCE THEN DELETE` haben (`03_elt.sql:33`, `03_elt.sql:74`). Das ist aus dem Code abgeleitet, nicht getestet.
- **Nicht aufgeräumt:** Das Test-Dataset `pizzeria_dwh_test` und die temporären Kopien unter `$TMPDIR/run_pipeline.*` bestehen weiter.

## Fazit

Zwei Läufe von `scripts/run_pipeline.sh pizzeria_dwh_test` hintereinander liefern identische Zeilenzahlen (fakt = 432), identische Prüfsummen für alle sechs Tabellen, keine Duplikate und in beiden Läufen alle 8 Checks PASS. Die Pipeline 01 bis 03 ist damit bei gleicher Rohdatei wiederholbar, und `pizzeria_dwh` blieb dabei nachweislich unverändert.
