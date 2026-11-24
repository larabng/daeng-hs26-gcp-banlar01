# Woche 11: Zeitplan für 05_pruefungen.sql

Stand: 24.11.2026, Branch `woche11/pipeline`

**Umgesetzt am 24.11.2026** nach dem freigegebenen Vorschlag (früher `zeitplan-vorschlag.md`).

**Ergebnis:** `sql/pizzeria_star_schema/05_pruefungen.sql` läuft jeden Montag um 06:00 (Europe/Zurich) automatisch gegen `pizzeria_dwh`. Meldet eine Prüfung FAIL, scheitert der Workflow, und die Alarmrichtlinie schickt eine E-Mail. Der erste reguläre Lauf ist am Montag, 30.11.2026, 06:00 (05:00 UTC).

## Ablauf

1. Der Cloud-Scheduler-Job `pizzeria-pruefungen-montag` startet den Workflow `pizzeria-pruefungen` mit dem Argument `{"dataset": "pizzeria_dwh"}`.
2. Der Workflow ruft in BigQuery `CALL pizzeria_dwh.pruefungen()` auf. Die Prozedur enthält den Inhalt von 05.
3. Die Prozedur hängt 9 Zeilen an `pizzeria_dwh.pruefergebnisse` an.
4. **Alles PASS:** BigQuery-Job und Workflow-Execution sind erfolgreich (`SUCCEEDED`).
5. **Mindestens ein FAIL:** Die Abschlussprüfung in 05 lässt den BigQuery-Job scheitern. Die Execution endet mit `FAILED`, die Richtlinie „Pizzeria Workflow fehlgeschlagen“ öffnet einen Vorfall, und es kommt eine E-Mail.

## Angelegte Ressourcen

Projekt `daeng-banlar01-x4q9`, Region europe-west6.

| Was | Name | Quelle im Repo |
|---|---|---|
| BigQuery-Prozedur (Test) | `pizzeria_dwh_test.pruefungen` | `05_pruefungen.sql`, mit `sed` auf `pizzeria_dwh_test.` umgestellt |
| BigQuery-Prozedur | `pizzeria_dwh.pruefungen` | `05_pruefungen.sql`, unverändert |
| Dienstkonto | `pruefungen-sa@daeng-banlar01-x4q9.iam.gserviceaccount.com` | – |
| Rollen auf dem Projekt | `roles/bigquery.jobUser`, `roles/workflows.invoker` für `pruefungen-sa` | – |
| Rollen auf den Datasets | `roles/bigquery.dataEditor` auf `pizzeria_dwh_test` und `pizzeria_dwh` für `pruefungen-sa` | – |
| Workflow | `pizzeria-pruefungen`, Revision `000001-87d`, läuft als `pruefungen-sa` | `pipeline/workflow-pruefungen.yaml` |
| Benachrichtigungskanal | E-Mail-Kanal „Pipeline-Alarm“ (Adresse und Kanal-ID stehen nicht im Repo) | – |
| Alarmrichtlinie | „Pizzeria Workflow fehlgeschlagen“, eine Bedingung: Executions von `pizzeria-pruefungen` mit Status `FAILED` | `pipeline/alert-policy-pruefungen.yaml` (Vorlage, `CHANNEL_ID` als Platzhalter) |
| Scheduler-Job | `pizzeria-pruefungen-montag`, `0 6 * * 1`, Europe/Zurich, POST an die Workflow-Executions-API, Anmeldung als `pruefungen-sa` | – |

## Ausgangslage vor der Umsetzung (nur gelesen, 24.11.2026)

`gcloud services list --enabled --filter="name:(bigquerydatatransfer OR cloudscheduler OR workflows)"`:

```
NAME                                 TITLE
bigquerydatatransfer.googleapis.com  BigQuery Data Transfer API
cloudscheduler.googleapis.com        Cloud Scheduler API
workflows.googleapis.com             Workflows API
```

`gcloud services list --enabled --filter="name:(workflowexecutions OR iam.googleapis.com OR bigquery.googleapis.com OR monitoring OR logging)"`:

```
NAME                               TITLE
bigquery.googleapis.com            BigQuery API
iam.googleapis.com                 Identity and Access Management (IAM) API
logging.googleapis.com             Cloud Logging API
monitoring.googleapis.com          Cloud Monitoring API
workflowexecutions.googleapis.com  Workflow Executions API
```

- `bigquerydatatransfer` ist eingeschaltet, steht aber nicht auf der Liste der erlaubten APIs in CLAUDE.md. Geplante BigQuery-Abfragen (Scheduled Queries) kamen deshalb nicht in Frage. Der Dienst wird nicht genutzt und wurde nicht abgeschaltet.
- Vorher gab es keine Scheduler-Jobs, keine Workflows, keine eigenen Dienstkonten, keine Benachrichtigungskanäle und keine Alarmrichtlinien. Den Job `gtfs-pipeline-schedule` aus `pipeline/README.md` gibt es nicht.
- Cloud Run wäre erlaubt gewesen, hätte aber ein Container-Image gebraucht. Gewählt wurde deshalb Scheduler → Workflow → BigQuery.

## Umsetzung und Tests

In dieser Reihenfolge. Die Tests liefen auf `pizzeria_dwh_test`, erst danach wurde `pizzeria_dwh` angefasst.

1. **Prozedur auf `pizzeria_dwh_test`** (Job `w11_prozedur_test_20261124_111127`). Ein Dry Run hatte vorher bestätigt, dass 05 in `CREATE OR REPLACE PROCEDURE … BEGIN … END;` gültig ist.
2. **Dienstkonto `pruefungen-sa`** angelegt.
3. **Rechte:** `jobUser` und `workflows.invoker` auf dem Projekt. `dataEditor` zunächst **nur** auf `pizzeria_dwh_test` (Job `w11_grant_test_20261124_111205`).
4. **`pipeline/workflow-pruefungen.yaml`** angelegt.
5. **Workflow deployt** (Revision `000001-87d`) und getestet:
   - **5a, erster Versuch:** `FAILED` (Execution `b4d1607f-2ac9-49a5-ada4-68f4a8867677`): „IAM permission denied for service account pruefungen-sa“, Tag `AuthError`, im Schritt `run_checks`. Ursache: Das Dienstkonto war erst rund eine Minute alt, und neue Konten und Rollen brauchen einige Minuten, bis sie überall gelten. Es entstand kein BigQuery-Job.
   - **5a, zweiter Versuch** rund 3 Minuten später, unverändert: `SUCCEEDED` (Execution `b70444c8-38ca-4d0f-8c8e-42b614cc4a66`, BigQuery-Job `job_P8Ef6c-7soxbxUjszd1GHEuVFPP-`). 9 × PASS, pruef_zeit 2026-11-24 10:15:57 UTC.
   - **5b, Gegentest:** Eine Faktenzeile in `pizzeria_dwh_test` gelöscht (Job `w11_wf_5b_delete_20261124_111628`), dann den Workflow gestartet. Ergebnis: `FAILED` (Execution `0707dc74-7a69-49d6-a526-99044cfd5f8b`, BigQuery-Job `job_a7fpmSPFag6-ss_WJtTABtBmhIl7`, als `pruefungen-sa`). Meldung: „Query error: 2 Pruefungen FAIL (6a, 6b), siehe pizzeria_dwh_test.pruefergebnisse, pruef_zeit 2026-11-24 10:16:32.185516+00“. Damit ist bestätigt, dass der BigQuery-Connector auf das Ende des Jobs wartet und den Workflow bei einem gescheiterten Job scheitern lässt.
   - **Wiederherstellen** mit `scripts/run_pipeline.sh pizzeria_dwh_test` (Lauf-ID `20261124_111651`): alle PASS. Die Prüfsumme der Faktentabelle ist wieder `770431044262388904` bei 432 Zeilen (Job `w11_wf_pruefsumme_20261124_111715`).
6. **`pizzeria_dwh`:** Prozedur angelegt (Job `w11_prozedur_prod_20261124_111737`) und `dataEditor` vergeben (Job `w11_grant_prod_20261124_111737`).
7. **Alarm:**
   - E-Mail-Kanal „Pipeline-Alarm“ angelegt.
   - Die Vorlage `pipeline/alert-policy-pruefungen.yaml` liegt im Repo. Die Kopie mit Kanal-ID lag nur im Scratchpad.
   - Die Richtlinie „Pizzeria Workflow fehlgeschlagen“ hat die Person selbst angelegt (`gcloud monitoring policies create --policy-from-file=<kopie>`), weil der Auto-Modus von Claude Code den Befehl blockiert hatte.
   - Kontrolle mit `gcloud monitoring policies list`: aktiv, eine Bedingung mit `resource.label.workflow_id = "pizzeria-pruefungen"` und `metric.labels.status = "FAILED"`, ein Kanal.
8. **Scheduler-Job** angelegt und mit `gcloud scheduler jobs run` einmal sofort ausgelöst (10:30:45 UTC). Der Scheduler hat erst um 10:31:35 UTC aufgerufen, also rund 50 Sekunden später.
   - Execution `f2eaba7f-a882-4a3f-898c-d56628c29864`: `SUCCEEDED`, Argument `{"dataset":"pizzeria_dwh"}`, BigQuery-Job `job_KU309B0CwPxFv9b3dn6_5xOxQRAJ`.
   - In `pizzeria_dwh.pruefergebnisse` stehen 9 × PASS mit pruef_zeit 2026-11-24 10:31:35 UTC. Die Tabelle hat jetzt 18 Zeilen: 9 vom Erstlauf, 9 von diesem Lauf (Job `w11_scheduler_lauf_kontrolle_20261124_113153`).
   - Gegenprobe `pizzeria_dwh.__TABLES__` (Job `gegenprobe_pizzeria_dwh_nach_scheduler_20261124_113203`): Die sechs bestehenden Tabellen sind unverändert (letzte Änderung 2026-11-12), nur `pruefergebnisse` ist gewachsen.
9. **Alarmtest bis zur E-Mail**, nur auf `pizzeria_dwh_test`:
   - Eine Faktenzeile gelöscht (Job `w11_alarmtest_delete_20261124_113957`), dann den Workflow mit `{"dataset": "pizzeria_dwh_test"}` gestartet.
   - Execution `22d5156e-6a9c-4b03-a10f-6b00249293b1`: `FAILED`, BigQuery-Job `job_Ak7LR_p_veKkT5RiXPkoTsVpK0Hl`, Meldung „2 Pruefungen FAIL (6a, 6b)“. Ende 2026-11-24 10:40:05 UTC (11:40:05 Ortszeit).
   - Die **E-Mail der Richtlinie „Pizzeria Workflow fehlgeschlagen“ kam um 11:44 Ortszeit** an, rund 4 Minuten nach dem Fehlschlag. Das hat die Person bestätigt.
   - Wiederherstellen mit `scripts/run_pipeline.sh pizzeria_dwh_test` (Lauf-ID `20261124_114021`): alle PASS. Die Prüfsumme der Faktentabelle ist wieder `770431044262388904` bei 432 Zeilen (Job `w11_alarmtest_pruefsumme_20261124_114044`).

### Workflow-Executions (Beleg)

| Test | Execution | Zustand | BigQuery-Job |
|---|---|---|---|
| 5a, erster Versuch | `b4d1607f-2ac9-49a5-ada4-68f4a8867677` | FAILED (AuthError, Rechte noch nicht verteilt) | – |
| 5a, zweiter Versuch | `b70444c8-38ca-4d0f-8c8e-42b614cc4a66` | SUCCEEDED | `job_P8Ef6c-7soxbxUjszd1GHEuVFPP-` |
| 5b, Gegentest | `0707dc74-7a69-49d6-a526-99044cfd5f8b` | FAILED (2 Pruefungen FAIL: 6a, 6b) | `job_a7fpmSPFag6-ss_WJtTABtBmhIl7` |
| Scheduler, sofort ausgelöst | `f2eaba7f-a882-4a3f-898c-d56628c29864` | SUCCEEDED | `job_KU309B0CwPxFv9b3dn6_5xOxQRAJ` |
| Alarmtest | `22d5156e-6a9c-4b03-a10f-6b00249293b1` | FAILED (2 Pruefungen FAIL: 6a, 6b), Alarm-E-Mail um 11:44 Ortszeit | `job_Ak7LR_p_veKkT5RiXPkoTsVpK0Hl` |

Executions ansehen: Console → Workflows → pizzeria-pruefungen → Executions, oder
`gcloud workflows executions describe <execution> --workflow=pizzeria-pruefungen --location=europe-west6`.

## Bedienung

```bash
# Von Hand starten. Achtung: Der Exit-Code ist auch bei FAILED 0, massgebend ist "state" in der Ausgabe.
gcloud workflows run pizzeria-pruefungen --location=europe-west6 --data='{"dataset": "pizzeria_dwh"}'

# Den Scheduler-Job sofort auslösen. Der Aufruf kommt mit bis zu etwa einer Minute Verzögerung.
gcloud scheduler jobs run pizzeria-pruefungen-montag --location=europe-west6

# Zeitplan anhalten und wieder aufnehmen
gcloud scheduler jobs pause pizzeria-pruefungen-montag --location=europe-west6
gcloud scheduler jobs resume pizzeria-pruefungen-montag --location=europe-west6

# Nach jeder Änderung an 05: Prozedur neu anlegen, sonst läuft im Zeitplan die alte Version
{ echo 'CREATE OR REPLACE PROCEDURE pizzeria_dwh.pruefungen()'; echo 'BEGIN';
  cat sql/pizzeria_star_schema/05_pruefungen.sql; echo 'END;'; } \
  | bq query --use_legacy_sql=false --location=europe-west6 --project_id=daeng-banlar01-x4q9
```

Ergebnisse ansehen:

```sql
SELECT pruef_zeit, nr, pruefung, ergebnis, detail
FROM pizzeria_dwh.pruefergebnisse
ORDER BY pruef_zeit DESC, nr;
```

## Grenzen

- **`dataEditor` auf dem ganzen Dataset:** `pruefungen-sa` hat `dataEditor` auf ganz `pizzeria_dwh` und ganz `pizzeria_dwh_test`. Es könnte damit jede Tabelle dort ändern, nicht nur `pruefergebnisse`. Enger wäre `dataViewer` auf dem Dataset und `dataEditor` nur auf der Tabelle `pruefergebnisse`. Ob `CREATE TABLE IF NOT EXISTS` mit diesen Rechten durchkommt, wenn die Tabelle schon existiert, ist nicht getestet.
- **Montagslauf prüft dieselben Daten:** 05 prüft nur den Stand, der gerade in den Tabellen steht. Solange 01 bis 03 nicht neu laufen, prüft der Montagslauf jede Woche dieselben Daten. Er findet dann nur Änderungen, die auf einem anderen Weg in die Tabellen gekommen sind.
- **Prozedur ist eine Kopie:** Die Prozeduren enthalten 05 im Stand vom 24.11.2026. Ändert sich `05_pruefungen.sql`, läuft im Zeitplan die alte Version, bis die Prozedur neu angelegt ist (siehe Bedienung).
- **Alarm kommt mit Verzögerung:** Im Alarmtest (Schritt 9) kam die E-Mail rund 4 Minuten nach dem Fehlschlag. Mit dieser Verzögerung ist auch bei echten Fehlern zu rechnen.
- **Auch Tests lösen den Alarm aus:** Die Bedingung filtert auf den Workflow, nicht auf das Dataset. Ein Gegentest über den Workflow auf `pizzeria_dwh_test` schickt ebenfalls eine E-Mail (so im Alarmtest geschehen).
- **Verzögerungen:** Neue Dienstkonten und Rollen gelten erst nach einigen Minuten (Test 5a, erster Versuch). `gcloud scheduler jobs run` ruft den Workflow mit bis zu etwa einer Minute Verzögerung auf.
- **Kosten:** Ein Lauf von 05 verarbeitet rund 32 KB, abgerechnet werden wegen der Mindestmenge 80 MiB. Für Cloud Scheduler und Workflows gibt es kostenlose Kontingente; deren aktuelle Höhe ist nicht geprüft.

## Rückbau (falls nicht mehr gewünscht)

Nur nach ausdrücklicher Bestätigung und ohne `--quiet`. Die Namen von Richtlinie und Kanal mit ID liefern `gcloud monitoring policies list` und `gcloud beta monitoring channels list`.

```bash
gcloud scheduler jobs delete pizzeria-pruefungen-montag --location=europe-west6
gcloud workflows delete pizzeria-pruefungen --location=europe-west6
gcloud monitoring policies delete <policy-name>
gcloud beta monitoring channels delete <channel-name>
bq query --use_legacy_sql=false --location=europe-west6 'DROP PROCEDURE pizzeria_dwh.pruefungen'
bq query --use_legacy_sql=false --location=europe-west6 'DROP PROCEDURE pizzeria_dwh_test.pruefungen'
bq query --use_legacy_sql=false --location=europe-west6 \
  'REVOKE `roles/bigquery.dataEditor` ON SCHEMA pizzeria_dwh FROM "serviceAccount:pruefungen-sa@daeng-banlar01-x4q9.iam.gserviceaccount.com"'
bq query --use_legacy_sql=false --location=europe-west6 \
  'REVOKE `roles/bigquery.dataEditor` ON SCHEMA pizzeria_dwh_test FROM "serviceAccount:pruefungen-sa@daeng-banlar01-x4q9.iam.gserviceaccount.com"'
gcloud projects remove-iam-policy-binding daeng-banlar01-x4q9 \
  --member="serviceAccount:pruefungen-sa@daeng-banlar01-x4q9.iam.gserviceaccount.com" --role="roles/bigquery.jobUser"
gcloud projects remove-iam-policy-binding daeng-banlar01-x4q9 \
  --member="serviceAccount:pruefungen-sa@daeng-banlar01-x4q9.iam.gserviceaccount.com" --role="roles/workflows.invoker"
gcloud iam service-accounts delete pruefungen-sa@daeng-banlar01-x4q9.iam.gserviceaccount.com
```
