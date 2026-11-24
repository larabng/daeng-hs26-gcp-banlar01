# Woche 10: Lifecycle-Mapping Pizzeria Da Luigi

Stand: 23.11.2026, Branch `woche10/lifecycle-mapping`

**Quellen:** nur `sql/pizzeria_star_schema/01_ddl.sql` bis `04_checks.sql` (Commit `37374fa`) und der BigQuery-Job-Verlauf des Projekts `daeng-banlar01-x4q9` (`bq ls -j -a`, `bq ls -j --parent_job_id`, `bq show -j --location=europe-west6`, `bq head -j`). Zeilennummern beziehen sich auf Commit `37374fa`. Die Job-IDs sind in der Tabelle gekürzt, vollständig stehen sie unten im Abschnitt „Job-Verlauf“. Zeiten in MEZ.

**offen** heisst: In diesen Quellen gibt es keinen Beleg dafür.

**Zuständigkeit:** „Code“ ist die Person, die die Datei eingecheckt hat (Commit-Autor). „Ausführung“ ist der Kursaccount, unter dem der BigQuery-Job lief.

| Phase | Artefakt | Beleg | Zuständigkeit | Lücke |
|---|---|---|---|---|
| Generation | Quellsysteme Kasse (`SRC-01`, Telefon über Strichliste) und Partner-Portal (`SRC-02`: Just Eat, Uber Eats); daraus der Datenausschnitt mit den Kanalgruppen `Kasse (vor Ort + Telefon)` und `App` | `02_dimensionen.sql:33-38` (Spalten `quellsystem`, `source_id`), `03_elt.sql:80-83` | offen | Wer den Datenausschnitt aus Kasse und Portal erstellt und wie oft: offen. Der Ausschnitt ist schon pro Stunde und Kanalgruppe zusammengefasst. Die Kasse erfasst keine Absagen (`03_elt.sql:71`, `04_checks.sql:118`). Die Fertig-Zeit fehlt, deshalb bleibt `summe_durchlaufzeit_min` NULL (`01_ddl.sql:81`, SP-03). |
| Storage (Rohablage) | `gs://daeng-banlar01-x4q9-raw/pizzeria/datenausschnitt_v1.csv` (CSV, Trennzeichen `;`, UTF-8 mit BOM) | `01_ddl.sql:22`, `03_elt.sql:7`, `03_elt.sql:26`; Teil-Job `script_job_b8d9…_0` (12.11., `LOAD_DATA` aus dieser URI: `inputFiles` 1, `inputFileBytes` 16469, `badRecords` 0, SUCCESS) | Upload der Datei: offen | Wer die Datei hochlädt und wann: offen. Versioniert wird nur über den Dateinamen (`_v1`). |
| Storage (DWH) | Dataset `pizzeria_dwh` mit `stg_datenausschnitt`, `dim_datum`, `dim_stunde`, `dim_kanal`, `dim_bestellstatus`, `fakt_bestellung_stunde` | `01_ddl.sql:9-87`; Job `bqjob_r838f…` (12.11., Skript = `01_ddl.sql`): 6 Teil-Jobs `CREATE_TABLE`, jeder mit `ddlOperationPerformed = CREATE`, SUCCESS | Tabellen: Ausführung: banlar01, Code: larabng. Dataset-Anlage: offen | `CREATE SCHEMA` fehlt in 01. Das Dataset bestand am 12.11. also schon. Wer es angelegt hat: offen. Die Location europe-west6 ist nur über die Job-Location belegt, nicht im Code. PK/FK sind `NOT ENFORCED` (`01_ddl.sql:5`). Keine Partitionierung, kein Ablaufdatum. |
| Ingestion | `LOAD DATA OVERWRITE` vom Bucket nach `stg_datenausschnitt`, alle Spalten STRING | `03_elt.sql:11-30`; Lauf 1 `bqjob_r220e…` (12.11., `errorResult.reason = invalidQuery`, Beleg unten im Abschnitt „Fehler im ersten Lauf von 03“); Lauf 2 `bqjob_r72e4…` (12.11., Skript = `03_elt.sql`), Teil-Job `script_job_b8d9…_0` (`LOAD_DATA`, `ddlOperationPerformed = REPLACE`, SUCCESS); `bqjob_r45b7…` (12.11., Kontrolle des Staging-Schemas über `INFORMATION_SCHEMA.COLUMNS`) | Ausführung: banlar01, Code: larabng | Lauf 1 mit einer Fassung ohne Spaltenliste ist fehlgeschlagen. Die Spaltenliste behebt das (`03_elt.sql:8-9`). Wegen OVERWRITE enthält Staging nur den letzten Stand. Der Dateiname steht fest im Code. Anzahl geladener Zeilen: offen (`loadQueryStatistics` ohne `outputRows`). |
| Transformation | MERGE in `dim_stunde`, `dim_kanal`, `dim_bestellstatus` (feste Werte); MERGE in `dim_datum` und `fakt_bestellung_stunde` aus Staging | `02_dimensionen.sql:7-62`, `03_elt.sql:33-108`; Teil-Jobs von `bqjob_r3d59…` (02) und `bqjob_r72e4…` (03, Lauf 2), alle `MERGE`, SUCCESS. Eingefügte Zeilen laut `dmlStats.insertedRowCount`: `dim_stunde` 12, `dim_kanal` 6, `dim_bestellstatus` 5, `dim_datum` 12, `fakt_bestellung_stunde` 432; jeweils 0 aktualisiert, 0 gelöscht | Ausführung: banlar01, Code: larabng | Die Fakten nutzen nur `kanal_id` 9/10 und `status_id` 1/5. Die Kanäle 1-4 und die Status 2-4 sind angelegt, werden aber nicht befüllt. Der MERGE hat kein `WHEN NOT MATCHED BY SOURCE`: Zeilen, die aus der Quelle verschwinden, bleiben stehen. |
| Serving | Roll-up Nachfrage pro Datum × Kanalgruppe; Slice Bestellungen pro Stunde an Regentagen; Abfrage angenommene Bestellungen pro Stunde | `04_checks.sql:117-148` (Abfragen C, D), gelaufen als Teil-Jobs `script_job_169e…_2` und `script_job_8908…_3` von `bqjob_r4f18…` (12.11., `SELECT`, SUCCESS); Job `bqjob_r2497…` (18.11.); Job `job_-MxP…` (22.11., Tests 4, 5) | Ausführung: banlar01 (12.11., 18.11.), eigener Kursaccount (22.11.). Code 04: larabng | Ergebnisse von C und D: Metadaten vorhanden, Ergebniszeilen nicht lesbar. Views, Dashboard und Abnehmer: offen. |
| Undercurrents | **Data Management:** PASS/FAIL-Prüfung (`04_checks.sql`, Abfrage A) und Zeilenzahlen je Tabelle (Abfrage B); Beschreibung der Staging-Tabelle mit Quell-URI; Spalten `quellsystem` und `source_id`<br>**Security:** offen<br>**DataOps:** wiederholbare Skripte; am 12.11. Fehler, Fix und neuer Lauf<br>**Orchestration:** Reihenfolge 01 → 02 → 03 → 04, über die bq-CLI gestartet<br>**Data Architecture:** Star Schema, Grain Datum × Stunde × Kanal × Status, ELT, `dim_datum` denormalisiert<br>**Software Engineering:** SQL im Git-Repo | **Data Management:** `04_checks.sql:5-115`; Teil-Jobs `script_job_2a6a…_0` (Abfrage A) und `script_job_1b8b…_1` (Abfrage B) von `bqjob_r4f18…` (12.11., `SELECT`, SUCCESS); Jobs `job_cbBF…` und `job_-MxP…` (22.11., Tests 1-6, 8, 9); `01_ddl.sql:22`, `02_dimensionen.sql:32`<br>**Security:** `bq head -j` auf `script_job_2a6a…_0`: `Access Denied: … User does not have permission to access results of another user's job.`<br>**DataOps:** `01_ddl.sql:3-4`, `02_dimensionen.sql:3`, `03_elt.sql:4`; `bqjob_r220e…` (`errorResult.reason = invalidQuery`, 14:56:01), danach `bqjob_r72e4…` (SUCCESS, 14:57:34)<br>**Orchestration:** Startzeiten 12.11. 14:55-14:58 in Dateireihenfolge, Job-Präfix `bqjob_`; `01_ddl.sql:6`, `02_dimensionen.sql:4`<br>**Data Architecture:** `01_ddl.sql:24`, `01_ddl.sql:72-73`, `03_elt.sql:2-3`<br>**Software Engineering:** Commit `37374fa` (12.11. 15:00); Query-Texte der Jobs identisch mit den Dateien | **Data Management:** Code: larabng; Ausführung 04: banlar01; Tests 22.11.: eigener Kursaccount<br>**Security:** offen<br>**DataOps:** Ausführung: banlar01, Code: larabng<br>**Orchestration:** Ausführung: banlar01<br>**Data Architecture:** Code: larabng<br>**Software Engineering:** Code: larabng | **Data Management:** Ergebnisse von 04 (PASS/FAIL, Zeilenzahlen): Metadaten vorhanden, Ergebniszeilen nicht lesbar. Bleibt offen, bis Woche 11 auf dem Testdatensatz läuft. Die 432 eingefügten Faktenzeilen entsprechen der Gesamtzahl im Sollwert 6a; die Teilzahlen von 6a sind damit nicht geprüft. Test 7 taucht im Verlauf nicht auf. Die Sollwerte 432 und 9 (`04_checks.sql:87`, `04_checks.sql:94`) gelten nur für diesen Datenausschnitt. Lineage: offen. Dimensionen und Fakt haben keine Beschreibung.<br>**Security:** Kein GRANT, keine IAM-Regel in 01-04. Jobs laufen unter zwei Kursaccounts, und die Ergebnisse des einen sind für den anderen nicht lesbar. Wer `pizzeria_dwh` lesen oder schreiben darf: offen.<br>**DataOps:** Kein Monitoring, kein Alarm. Der Fehler vom 12.11. ist nur im Job-Verlauf sichtbar.<br>**Orchestration:** Kein Scheduler belegt.<br>**Data Architecture:** Der Kanal ist in den Daten gröber als im Modell (nur 9/10 statt 1-4).<br>**Software Engineering:** Nur ein Commit, eingecheckt nach den Läufen. Die fehlgeschlagene Fassung von 03 ist nur im Job-Verlauf erhalten. Review und automatischer Testlauf: offen. |

## Fehler im ersten Lauf von 03

Belegt aus `bq ls -j -a` und `bq show -j --location=europe-west6`:

- **Haupt-Job** `bqjob_r220e6f4fc00d6866_000001a1d00b4351_1` (12.11. 14:56:01, Ausführung banlar01). `bq ls -j -a` zeigt den Status `FAILURE`. Laut `bq show` ist `status.state = DONE` und `status.errorResult.reason = invalidQuery`. `status.errorResult.message`:
  ```
  Query error: No matching signature for function TRIM
    Argument types: DATE
    Signature: TRIM(STRING, [STRING])
      Argument 1: Unable to coerce type DATE to expected type STRING
    Signature: TRIM(BYTES, BYTES)
      Signature requires at least 2 arguments, found 1 argument at [5:30] at [19:1]
  ```
- **Teil-Job 0** `script_job_b7aef77e99ecca661951a04c4b1ffac1_0`: `LOAD_DATA` auf `stg_datenausschnitt`, `ddlOperationPerformed = REPLACE`, kein `errorResult`.
- **Teil-Job 1** `script_job_2b8038ea28758741c71658151f6ec784_1`: `MERGE` auf `dim_datum`, `errorResult.reason = invalidQuery`, dieselbe Meldung mit `at [5:30]`.
- **Query-Text des Haupt-Jobs:** `03_elt.sql` ohne Spaltenliste im `LOAD DATA`. Der `diff` gegen Commit `37374fa` zeigt: Die Zeilen 8-23 der Datei fehlen, an ihrer Stelle steht `-- Leere Felder werden als NULL geladen.`.
- **Fehlerstelle:** Zeile 19 des Job-Texts ist `MERGE pizzeria_dwh.dim_datum AS t`. Zeile 5, Spalte 30 dieses Statements ist `TRIM(datum)`. Laut Meldung war `datum` zu diesem Zeitpunkt vom Typ DATE. `03_elt.sql:8-9` beschreibt genau diesen Fall: Ohne Spaltenliste erkennt BigQuery die Typen selbst.

## Job-Verlauf

Alle Jobs liegen in europe-west6. „identisch“ heisst: Der Query-Text des Jobs stimmt mit der Datei in Commit `37374fa` überein (`diff` ohne Unterschied).

| Start (MEZ) | Job-ID | Ausführung | Inhalt | Status |
|---|---|---|---|---|
| 12.11. 14:55:25 | `bqjob_r838f975bedc7fea_000001a1d00ab707_1` | banlar01 | Skript `01_ddl.sql` (identisch), 6 Teil-Jobs | SUCCESS |
| 12.11. 14:55:47 | `bqjob_r3d599f97e6be5260_000001a1d00b0bd6_1` | banlar01 | Skript `02_dimensionen.sql` (identisch), 3 Teil-Jobs | SUCCESS |
| 12.11. 14:56:01 | `bqjob_r220e6f4fc00d6866_000001a1d00b4351_1` | banlar01 | Skript `03_elt.sql` in einer älteren Fassung ohne Spaltenliste im `LOAD DATA`, 2 Teil-Jobs | FAILURE (`errorResult.reason = invalidQuery`) |
| 12.11. 14:57:34 | `bqjob_r72e4c380f8f84823_000001a1d00cb008_1` | banlar01 | Skript `03_elt.sql` (identisch), 3 Teil-Jobs | SUCCESS |
| 12.11. 14:57:50 | `bqjob_r45b7ad77cc21d830_000001a1d00ce758_1` | banlar01 | SELECT auf `pizzeria_dwh.INFORMATION_SCHEMA.COLUMNS` (`stg_datenausschnitt`) | SUCCESS |
| 12.11. 14:58:00 | `bqjob_r4f1854235f6730d3_000001a1d00d1450_1` | banlar01 | Skript `04_checks.sql` (identisch), 4 Teil-Jobs | SUCCESS |
| 12.11. 14:58:11 | `bqjob_r87ba9599e0a0c1d_000001a1d00d3e72_1` | banlar01 | SELECT auf `dim_bestellstatus` | SUCCESS |
| 18.11. 11:13:00 | `bqjob_r2497ee9badf629a9_000001a1ee253d5b_1` | banlar01 | SELECT angenommene Bestellungen pro Stunde | SUCCESS |
| 22.11. 18:34:51 | `job_cbBFPPh6bv4p8ZSArhbmJ8KQOCJJ` | eigener Kursaccount | Testskript Tests 1, 2, 3, 6, 4 Teil-Jobs | SUCCESS |
| 22.11. 23:14:55 | `job_-MxPduswR_Cd_DqWQYJfPtnLqhI0` | eigener Kursaccount | Testskript Tests 4, 5, 8, 9, 4 Teil-Jobs | SUCCESS |
| 23.11. 21:25:34 | `job_ND7LYok5CwN7czVyV6JArPb_iZJE` | eigener Kursaccount | SELECT auf `pizzeria_dwh.INFORMATION_SCHEMA.TABLES` | SUCCESS |
| 23.11. 21:26:27 | `job_fVF-bUQh-7Hod9C7aHKlUGaqXuSR` | eigener Kursaccount | SELECT auf `INFORMATION_SCHEMA.JOBS_BY_PROJECT` | SUCCESS |

### Teil-Jobs der Skripte vom 12.11.

| Skript | Teil-Job | Statement | Ziel | Metadaten |
|---|---|---|---|---|
| 01 | `script_job_e9e4be78f33d11c180bc0145bc90a84d_0` | `CREATE_TABLE` | `stg_datenausschnitt` | `ddlOperationPerformed = CREATE` |
| 01 | `script_job_bfb89ac963d8afe45cbf3579eb4f60ce_1` | `CREATE_TABLE` | `dim_datum` | `ddlOperationPerformed = CREATE` |
| 01 | `script_job_b959a9b18cac61081a7b1d82e7de8f6e_2` | `CREATE_TABLE` | `dim_stunde` | `ddlOperationPerformed = CREATE` |
| 01 | `script_job_3ce230a71a0856f100a4f259412d095d_3` | `CREATE_TABLE` | `dim_kanal` | `ddlOperationPerformed = CREATE` |
| 01 | `script_job_3f60782425db6b7fa14536dded5b4253_4` | `CREATE_TABLE` | `dim_bestellstatus` | `ddlOperationPerformed = CREATE` |
| 01 | `script_job_3699c4192d5131b2d68a2750b6cbdb29_5` | `CREATE_TABLE` | `fakt_bestellung_stunde` | `ddlOperationPerformed = CREATE` |
| 02 | `script_job_9be66a8ead8c0b08c65be8b6b95ebd0a_0` | `MERGE` | `dim_stunde` | eingefügt 12, aktualisiert 0, gelöscht 0 |
| 02 | `script_job_d82549f2217682d1059956f81149e26b_1` | `MERGE` | `dim_kanal` | eingefügt 6, aktualisiert 0, gelöscht 0 |
| 02 | `script_job_e677be6917cdd17fc04306d71c0e0084_2` | `MERGE` | `dim_bestellstatus` | eingefügt 5, aktualisiert 0, gelöscht 0 |
| 03 Lauf 1 | `script_job_b7aef77e99ecca661951a04c4b1ffac1_0` | `LOAD_DATA` | `stg_datenausschnitt` | `ddlOperationPerformed = REPLACE`; `inputFiles` 1, `inputFileBytes` 16469, `badRecords` 0 |
| 03 Lauf 1 | `script_job_2b8038ea28758741c71658151f6ec784_1` | `MERGE` | `dim_datum` | `errorResult.reason = invalidQuery` |
| 03 Lauf 2 | `script_job_b8d961966b3446205117099f140be503_0` | `LOAD_DATA` | `stg_datenausschnitt` | `ddlOperationPerformed = REPLACE`; `inputFiles` 1, `inputFileBytes` 16469, `badRecords` 0 |
| 03 Lauf 2 | `script_job_f5eb9f0b4926e9f18de42c0716b805f4_1` | `MERGE` | `dim_datum` | eingefügt 12, aktualisiert 0, gelöscht 0 |
| 03 Lauf 2 | `script_job_d242901895b3086d95f1115a0ceaadf2_2` | `MERGE` | `fakt_bestellung_stunde` | eingefügt 432, aktualisiert 0, gelöscht 0 |
| 04 | `script_job_2a6ab07177f7fe2d61fd0a544d8f7030_0` | `SELECT` (Abfrage A) | Ergebnis-Dataset `_42c4a…` | Metadaten vorhanden, Ergebniszeilen nicht lesbar (`bq head -j`: Access Denied) |
| 04 | `script_job_1b8b10008ab61131be22cab4834017cd_1` | `SELECT` (Abfrage B) | Ergebnis-Dataset `_42c4a…` | Metadaten vorhanden, Ergebniszeilen nicht lesbar (nach dem Fehler bei `_0` nicht versucht, gleiches Dataset) |
| 04 | `script_job_169e08fb120ca818024e1a16001c627e_2` | `SELECT` (Abfrage C) | Ergebnis-Dataset `_42c4a…` | Metadaten vorhanden, Ergebniszeilen nicht lesbar (nach dem Fehler bei `_0` nicht versucht, gleiches Dataset) |
| 04 | `script_job_8908572529420abd28480beea7945c96_3` | `SELECT` (Abfrage D) | Ergebnis-Dataset `_42c4a…` | Metadaten vorhanden, Ergebniszeilen nicht lesbar (nach dem Fehler bei `_0` nicht versucht, gleiches Dataset) |
