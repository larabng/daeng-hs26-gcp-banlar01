# Woche 11, Teil 2: Automatisierte Prüfungen

Stand: 24.11.2026, Branch `woche11/pipeline`

**Ziel:** Die Prüfungen aus Abfrage A in `04_checks.sql` sollen ohne feste Sollwerte laufen und ihr Ergebnis in eine Tabelle schreiben, damit sie sich automatisch und wiederholt ausführen lassen.

**Rahmen:** Getestet auf `pizzeria_dwh_test` (Projekt `daeng-banlar01-x4q9`, europe-west6), danach ein Erstlauf auf `pizzeria_dwh` (siehe „Erstlauf auf pizzeria_dwh“). `04_checks.sql` bleibt unverändert.

## Datei: sql/pizzeria_star_schema/05_pruefungen.sql

- **Ablauf:** `DECLARE lauf_zeit`, dann `CREATE TABLE IF NOT EXISTS pizzeria_dwh.pruefergebnisse`, dann `INSERT` mit einer Zeile pro Prüfung. Danach ein `SELECT`, das genau diesen Lauf anzeigt, und zum Schluss die Abschlussprüfung (siehe Abschnitt „Abschlussprüfung“).
- **Tabelle `pruefergebnisse`:** `pruef_zeit TIMESTAMP, nr STRING, pruefung STRING, ergebnis STRING (PASS/FAIL), detail STRING`. Alle Zeilen eines Laufs haben dieselbe `pruef_zeit`.
- **Schreibzugriff:** nur auf `pruefergebnisse`, alle anderen Tabellen werden nur gelesen.
- **Dataset-Name** nur als `pizzeria_dwh.` (17 Zeilen, keine Stelle ohne Punkt). So kann ihn dieselbe `sed`-Ersetzung wie in `scripts/run_pipeline.sh` umstellen.

| Nr | Prüfung | Unterschied zu 04, Abfrage A |
|---|---|---|
| 0 | Staging nicht leer (`zeilen > 0`) | neu |
| 1a | Summe angenommene Bestellungen Fakt = Staging | gleich |
| 1b | Summe Pizzen Fakt = Staging | gleich |
| 2 | Keine doppelten Schlüssel | gleich |
| 3 | Keine verwaisten FKs | gleich |
| 6a | Faktenzeilen = Staging-Zeilen + Staging-Zeilen mit nicht leerem `bestellungen_abgelehnt_app` | statt fest 432 (144/144/144) |
| 6b | Summe App-Absagen in Fakt (`kanal_id = 10, status_id = 5`) = Summe `bestellungen_abgelehnt_app` im Staging | statt fest 9 |
| Z1 | Wetter/Temperatur/Event/Wochentag pro Datum eindeutig | gleich |
| Z2 | Wochentag CSV = berechneter Wochentag in dim_datum | gleich |

Zwei Entscheidungen:

- Summen stehen in `COALESCE(…, 0)`. Ohne das würde `NULL = 0` zu NULL und damit zu FAIL, obwohl beide Seiten nichts enthalten. Ein leeres Staging fängt Prüfung 0 ab.
- Ist eine Bedingung NULL, ergibt das FAIL, weil `IF(NULL, 'PASS', 'FAIL')` den Sonst-Zweig nimmt.

**Ausführen gegen ein anderes Dataset** (so in allen Testläufen):

```bash
sed "s/pizzeria_dwh\./pizzeria_dwh_test./g" sql/pizzeria_star_schema/05_pruefungen.sql \
  | bq query --use_legacy_sql=false --location=europe-west6 --project_id=daeng-banlar01-x4q9 --job_id=<job-id>
```

`scripts/run_pipeline.sh` führt seit diesem Teil auch 05 aus, also 01 bis 05. Getestet mit `scripts/run_pipeline.sh pizzeria_dwh_test`, Lauf-ID `20261124_104013`: 04 und 05 melden alle PASS, und `pruefergebnisse` im Test-Dataset hat danach 45 Zeilen aus 5 Läufen. Seit der Abschlussprüfung bricht das Skript bei einem FAIL in 05 ab (siehe „Abschlussprüfung“).

## Testläufe auf pizzeria_dwh_test

| Lauf | pruef_zeit (UTC) | PASS | FAIL | Zeilen in pruefergebnisse danach |
|---|---|---:|---:|---:|
| Test 1 (legt `pruefergebnisse` an) | 2026-11-24 09:29:43 | 9 | 0 | 9 |
| Test 2 | 2026-11-24 09:29:54 | 9 | 0 | 18 |

Erwartet war: zweimal alle PASS, danach doppelt so viele Zeilen. Beides ist eingetroffen. In Test 1 meldete bq „Created …pruefergebnisse“, in Test 2 wurde nichts neu angelegt. Beide Läufe zeigen dieselben Details, unter anderem 6a „Fakt 432, erwartet 432 (Staging 288 + mit Absage 144)“ und 6b „Fakt 9, Staging 9“.

## Gegentest

1. **Eine Faktenzeile löschen**, nur in `pizzeria_dwh_test`. Es ist eine App-Absage-Zeile mit 3 Absagen. „Number of affected rows: 1“.

   ```sql
   DELETE FROM pizzeria_dwh_test.fakt_bestellung_stunde
   WHERE datum_id = 20260919 AND stunde_id = 19 AND kanal_id = 10 AND status_id = 5
   ```

   Erwartet: 6a und 6b FAIL, der Rest PASS. Angenommene Bestellungen und Pizzen hängen nur an Zeilen mit `status_id = 1`.

2. **05 ausführen** (pruef_zeit 2026-11-24 09:30:33 UTC):

   | Nr | Ergebnis | Detail |
   |---|---|---|
   | 0, 1a, 1b, 2, 3, Z1, Z2 | PASS | unverändert |
   | 6a | **FAIL** | Fakt 431, erwartet 432 (Staging 288 + mit Absage 144) |
   | 6b | **FAIL** | Fakt 6, Staging 9 |

   Der BigQuery-Job selbst endete trotzdem erfolgreich (Exit-Code 0). Ein FAIL steht nur in `pruefergebnisse` und lässt den Job nicht scheitern. Für einen automatischen Lauf braucht es deshalb eine zusätzliche Schranke, die bei FAIL einen Fehler auslöst. Diese Schranke ist inzwischen eingebaut (siehe „Abschlussprüfung“). Dieser Gegentest lief noch mit der Version ohne sie.

3. **Wiederherstellen** mit `scripts/run_pipeline.sh pizzeria_dwh_test`, Lauf-ID `20261124_103047`. Der MERGE in 03 fügt die fehlende Zeile wieder ein, und 04 zeigt wieder alle PASS. Die Prüfsumme der Faktentabelle ist danach wieder `770431044262388904` bei 432 Zeilen, also identisch mit Teil 1 ([wiederholbarkeit.md](wiederholbarkeit.md)).

4. **05 erneut** (pruef_zeit 2026-11-24 09:31:20 UTC): alle 9 PASS.

**Stand `pruefergebnisse` nach diesen Tests:** 4 Läufe, 36 Zeilen, 34 PASS, 2 FAIL. Die beiden FAIL sind 6a und 6b, beide aus dem Gegentest.

## Erstlauf auf pizzeria_dwh

Ausgeführt am 24.11.2026 nach Freigabe, mit der unveränderten Datei, also ohne Ersetzung. Damals hatte 05 noch keine Abschlussprüfung. Die neue Version ist auf `pizzeria_dwh` noch nicht gelaufen.

```bash
bq query --use_legacy_sql=false --location=europe-west6 --project_id=daeng-banlar01-x4q9 \
  --job_id=pruefungen_pizzeria_dwh_erstlauf_20261124_103920 < sql/pizzeria_star_schema/05_pruefungen.sql
```

1. **Dry Run der ganzen Datei:** „lower bound of 0 bytes“. Bei einem Skript nennt BigQuery nur eine Untergrenze, weil es Anweisungen, die von früheren Anweisungen abhängen, nicht vorab schätzt. Darum ein zweiter Dry Run nur auf den lesenden Teil: `WITH …` bis vor das abschliessende `SELECT`, mit `CURRENT_TIMESTAMP()` statt `lauf_zeit`. Ergebnis: **31 238 Bytes**.
2. **Lauf:** „Created …pizzeria_dwh.pruefergebnisse“, 9 Zeilen, alle PASS (pruef_zeit 2026-11-24 09:39:21 UTC). Die Details sind dieselben wie in den Testläufen, zum Beispiel 6a „Fakt 432, erwartet 432“ und 6b „Fakt 9, Staging 9“.
3. **Bytes laut Job:** verarbeitet 32 052, abgerechnet 83 886 080 (80 MiB). Die abgerechnete Menge ist höher, weil BigQuery pro Abfrage und referenzierter Tabelle mindestens 10 MB abrechnet.
4. **Gegenprobe `pizzeria_dwh.__TABLES__`** direkt vor und nach dem Lauf:

| Tabelle | Zeilen vorher | Zeilen nachher | zuletzt geändert, vorher | zuletzt geändert, nachher |
|---|---:|---:|---|---|
| dim_bestellstatus | 5 | 5 | 2026-11-12 13:55:51 UTC | 2026-11-12 13:55:51 UTC |
| dim_datum | 12 | 12 | 2026-11-12 13:57:36 UTC | 2026-11-12 13:57:36 UTC |
| dim_kanal | 6 | 6 | 2026-11-12 13:55:50 UTC | 2026-11-12 13:55:50 UTC |
| dim_stunde | 12 | 12 | 2026-11-12 13:55:48 UTC | 2026-11-12 13:55:48 UTC |
| fakt_bestellung_stunde | 432 | 432 | 2026-11-12 13:57:38 UTC | 2026-11-12 13:57:38 UTC |
| stg_datenausschnitt | 288 | 288 | 2026-11-12 13:57:35 UTC | 2026-11-12 13:57:35 UTC |
| **pruefergebnisse** | – | **9** | – | **2026-11-24 09:39:22 UTC** |

Die sechs bestehenden Tabellen sind unverändert, neu ist nur `pruefergebnisse`.

## Abschlussprüfung (Schranke)

Nach dem Erstlauf ergänzt. Die letzte Anweisung in 05 lässt den Job scheitern, wenn dieser Lauf mindestens ein FAIL hat oder gar keine Zeile geschrieben hat:

```sql
SELECT
  CASE
    WHEN COUNT(*) = 0 THEN ERROR('Keine Pruefergebnisse fuer diesen Lauf gefunden')
    WHEN COUNTIF(ergebnis = 'FAIL') > 0 THEN ERROR(FORMAT(
      '%d Pruefungen FAIL (%s), siehe pizzeria_dwh.pruefergebnisse, pruef_zeit %t',
      COUNTIF(ergebnis = 'FAIL'), STRING_AGG(IF(ergebnis = 'FAIL', nr, NULL), ', ' ORDER BY nr), lauf_zeit))
    ELSE 'alle PASS'
  END AS abschluss
FROM pizzeria_dwh.pruefergebnisse
WHERE pruef_zeit = lauf_zeit;
```

- `lauf_zeit` wird einmal am Anfang gesetzt (`DECLARE`) und im `INSERT`, in der Anzeige und hier verwendet.
- Die Abschlussprüfung steht nach der Anzeige. So ist das Ergebnis bei Erfolg in der Ausgabe zu sehen. Scheitert das Skript, zeigt bq die Tabelle nicht an; das Ergebnis steht dann nur in `pruefergebnisse`.
- Wenn `ERROR` auslöst, ist das `INSERT` schon abgeschlossen. Die Zeilen des Laufs bleiben also gespeichert.
- `scripts/run_pipeline.sh` bricht wegen `set -e` ab, sobald der 05-Job scheitert: Exit-Code ungleich 0, keine „Fertig“-Zeile.

**Tests, nur auf `pizzeria_dwh_test`:**

| Test | Vorgehen | Ergebnis |
|---|---|---|
| Normaler Lauf | `scripts/run_pipeline.sh pizzeria_dwh_test`, Lauf-ID `20261124_105454` | Erfolg: 04 und 05 alle PASS, Abschluss „alle PASS“, „Fertig“-Zeile, Exit-Code 0 |
| Gegentest | dieselbe Faktenzeile gelöscht wie oben (20260919, 19 Uhr, App, abgelehnt), dann 05 einzeln | **Job gescheitert**, bq Exit-Code 1: „Query error: 2 Pruefungen FAIL (6a, 6b), siehe pizzeria_dwh_test.pruefergebnisse, pruef_zeit 2026-11-24 09:55:43.524326+00 at [139:1]“. In `pruefergebnisse` stehen trotzdem 9 Zeilen mit dieser pruef_zeit: 6a FAIL (Fakt 431, erwartet 432), 6b FAIL (Fakt 6, Staging 9), der Rest PASS. |
| Wiederherstellen | `scripts/run_pipeline.sh pizzeria_dwh_test`, Lauf-ID `20261124_105612` | Erfolg: 04 und 05 alle PASS (17 PASS-Zeilen), Exit-Code 0, Prüfsumme der Faktentabelle wieder `770431044262388904` bei 432 Zeilen |

Der Gegentest lief mit 05 einzeln, nicht mit `run_pipeline.sh`: Dessen Schritt 03 würde die gelöschte Zeile per MERGE wieder einfügen, bevor 05 prüft. Dass das Skript bei FAIL abbricht, folgt aus dem gescheiterten 05-Job zusammen mit `set -e`. Einen ganzen Skriptlauf mit FAIL gab es nicht.

**Endstand `pruefergebnisse` im Test-Dataset:** 8 Läufe, 72 Zeilen, 4 FAIL. Das sind je 6a und 6b aus den beiden Gegentests.

## Job-IDs (Beleg)

Projekt `daeng-banlar01-x4q9`, Location europe-west6. Ansehen mit `bq show -j --location=europe-west6 <job-id>`.

| Zweck | Job-ID |
|---|---|
| 05, Test 1 | `pruefungen_pizzeria_dwh_test_test1_20261124_102941` |
| 05, Test 2 | `pruefungen_pizzeria_dwh_test_test2_20261124_102953` |
| Zählung `pruefergebnisse` nach Test 2 | `w11_pruefergebnisse_nach_test2_20261124_103006` |
| Auswahl der zu löschenden Zeile | `w11_kandidaten_gegentest_20261124_103006` |
| Gegentest: DELETE einer Faktenzeile | `w11_gegentest_delete_20261124_103023` |
| 05, Gegentest | `pruefungen_pizzeria_dwh_test_gegentest_20261124_103033` |
| Wiederherstellen 01_ddl | `pipeline_pizzeria_dwh_test_20261124_103047_01_ddl` |
| Wiederherstellen 02_dimensionen | `pipeline_pizzeria_dwh_test_20261124_103047_02_dimensionen` |
| Wiederherstellen 03_elt | `pipeline_pizzeria_dwh_test_20261124_103047_03_elt` |
| Wiederherstellen 04_checks | `pipeline_pizzeria_dwh_test_20261124_103047_04_checks` |
| Prüfsumme Fakt nach Wiederherstellen | `w11_pruefsumme_fakt_wiederhergestellt_20261124_103118` |
| 05, nach Wiederherstellen | `pruefungen_pizzeria_dwh_test_wiederhergestellt_20261124_103118` |
| Endstand `pruefergebnisse` | `w11_pruefergebnisse_endstand_20261124_103326` |
| Gegenprobe `pizzeria_dwh` vor dem Erstlauf | `gegenprobe_pizzeria_dwh_vor05_20261124_103904` |
| 05, Erstlauf auf `pizzeria_dwh` | `pruefungen_pizzeria_dwh_erstlauf_20261124_103920` |
| Gegenprobe `pizzeria_dwh` nach dem Erstlauf | `gegenprobe_pizzeria_dwh_nach05_20261124_103934` |
| `run_pipeline.sh` mit 05, Schritt 05 (01 bis 04 entsprechend `…_104013_01_ddl` usw.) | `pipeline_pizzeria_dwh_test_20261124_104013_05_pruefungen` |
| Zählung `pruefergebnisse` im Test-Dataset danach | `w11_pruefergebnisse_test_nach_skript_20261124_104047` |
| Abschlussprüfung, normaler Lauf: `run_pipeline.sh`, Schritt 05 | `pipeline_pizzeria_dwh_test_20261124_105454_05_pruefungen` |
| Abschlussprüfung, Gegentest: DELETE | `w11_schranke_delete_20261124_105540` |
| Abschlussprüfung, Gegentest: 05 (gescheitert) | `pruefungen_pizzeria_dwh_test_schranke_gegentest_20261124_105540` |
| Abschlussprüfung, Gegentest: gespeicherte Zeilen | `w11_schranke_pruefergebnisse_20261124_105557` |
| Abschlussprüfung, Wiederherstellen: `run_pipeline.sh`, Schritt 05 | `pipeline_pizzeria_dwh_test_20261124_105612_05_pruefungen` |
| Prüfsumme Fakt nach dem Wiederherstellen | `w11_schranke_pruefsumme_20261124_105634` |
| Endstand `pruefergebnisse` im Test-Dataset | `w11_schranke_endstand_20261124_105657` |

Die Dry Runs erzeugen keinen Job und haben deshalb keine Job-ID.

Die Zeitstempel in den Job-IDs sind Ortszeit (UTC+1), `pruef_zeit` ist UTC.

## Grenzen

- **Gleiche Daten bei jedem Lauf:** 05 prüft nur den Stand, der gerade in den Tabellen steht. Ein Montagslauf prüft deshalb jede Woche dieselben Daten, solange 01 bis 03 nicht neu laufen. Er findet dann nur Änderungen, die auf einem anderen Weg in die Tabellen gekommen sind.
- **Scheitern ist noch nicht Melden:** Seit der Abschlussprüfung scheitert der Job bei FAIL. Bemerkt wird das aber nur, wenn jemand den Fehler sieht: von Hand am Exit-Code, im Zeitplan über einen Alarm. Seit dem 24.11.2026 gibt es dafür die Alarmrichtlinie „Pizzeria Workflow fehlgeschlagen“ (siehe [zeitplan.md](zeitplan.md)).
- **Reihenfolge:** Die Abschlussprüfung muss die letzte Anweisung in 05 bleiben. Was danach steht, läuft bei FAIL nicht mehr.

## Zeitplan

Seit dem 24.11.2026 läuft 05 jeden Montag um 06:00 (Europe/Zurich) automatisch gegen `pizzeria_dwh`, über Cloud Scheduler → Workflow `pizzeria-pruefungen` → Prozedur `pizzeria_dwh.pruefungen`. Bei FAIL scheitert der Workflow, und die Alarmrichtlinie „Pizzeria Workflow fehlgeschlagen“ meldet es per E-Mail. Umsetzung, Tests und IDs stehen in [zeitplan.md](zeitplan.md).
