# Woche 11: Zeitplan-Vorschlag für 05_pruefungen.sql

Stand: 24.11.2026, Branch `woche11/pipeline`

**Nur ein Vorschlag. Nichts davon ist angelegt.**

**Ziel:** `sql/pizzeria_star_schema/05_pruefungen.sql` läuft jeden Montag früh automatisch gegen `pizzeria_dwh`. Meldet eine Prüfung FAIL, erfährt es jemand per E-Mail.

## Ausgangslage (nur gelesen, 24.11.2026)

`gcloud services list --enabled --filter="name:(bigquerydatatransfer OR cloudscheduler OR workflows)"`:

```
NAME                                 TITLE
bigquerydatatransfer.googleapis.com  BigQuery Data Transfer API
cloudscheduler.googleapis.com        Cloud Scheduler API
workflows.googleapis.com             Workflows API
```

Weitere Dienste, die der Vorschlag braucht (`gcloud services list --enabled --filter="name:(workflowexecutions OR iam.googleapis.com OR bigquery.googleapis.com OR monitoring OR logging)"`):

```
NAME                               TITLE
bigquery.googleapis.com            BigQuery API
iam.googleapis.com                 Identity and Access Management (IAM) API
logging.googleapis.com             Cloud Logging API
monitoring.googleapis.com          Cloud Monitoring API
workflowexecutions.googleapis.com  Workflow Executions API
```

Weitere Befunde:

- **`bigquerydatatransfer`:** Der Dienst ist eingeschaltet, steht aber **nicht** auf der Liste der erlaubten APIs in CLAUDE.md. Er wird nicht genutzt und auch nicht abgeschaltet.
- **Scheduler:** In europe-west6 gibt es keine Scheduler-Jobs (`gcloud scheduler jobs list`: 0). Den Job `gtfs-pipeline-schedule` aus `pipeline/README.md` gibt es nicht (`describe`: `NOT_FOUND`).
- **Workflows:** In europe-west6 gibt es keine Workflows (`gcloud workflows list`: leer).
- **Dienstkonten:** Es gibt nur das Standard-Compute-Konto. Das `workflow-sa` aus `pipeline/workflow.yaml` existiert nicht.
- **Alarm:** Es gibt keine Alarmrichtlinien (`gcloud monitoring policies list`: leer). `pipeline/alert-policy.yaml` ist also nicht angelegt. Deren Bedingung „Workflow fehlgeschlagen“ filtert auf alle Workflows im Projekt und würde einen neuen Workflow mit abdecken.
- **05 lässt den Job scheitern:** Seit der Abschlussprüfung scheitert der BigQuery-Job von 05 bei FAIL. Getestet ist das auf `pizzeria_dwh_test`, siehe [automatische-pruefungen.md](automatische-pruefungen.md).

## Varianten

| Variante | Erlaubt nach CLAUDE.md | Bewertung |
|---|---|---|
| Geplante BigQuery-Abfrage (Scheduled Query) | nein, braucht `bigquerydatatransfer` | wäre am einfachsten, fällt aber weg |
| Cloud-Run-Job plus Cloud Scheduler | ja | braucht ein Container-Image mit Cloud Build und Artifact Registry, nur um eine SQL-Datei auszuführen; zu viel Aufwand |
| **Cloud Scheduler → Workflow → BigQuery** | ja (`cloudscheduler`, `workflows`, `workflowexecutions`, `bigquery`, `iam`, `monitoring`) | **Empfehlung:** dasselbe Muster wie `gtfs-pipeline` im Repo, ohne Container |

## Empfehlung: Ablauf

1. **Montag 06:00 (Europe/Zurich):** Der Cloud-Scheduler-Job `pizzeria-pruefungen-montag` startet den Workflow `pizzeria-pruefungen` mit dem Argument `{"dataset": "pizzeria_dwh"}`.
2. Der Workflow ruft in BigQuery `CALL pizzeria_dwh.pruefungen()` auf. Die Prozedur enthält den Inhalt von 05.
3. **Alles PASS:** Der Job ist erfolgreich, und die Workflow-Execution endet mit `SUCCEEDED`.
4. **Mindestens ein FAIL:** Die Abschlussprüfung in 05 lässt den BigQuery-Job scheitern. Die Workflow-Execution endet mit `FAILED`, und der Alarm „Workflow fehlgeschlagen“ schickt eine E-Mail. Die Ergebnisse stehen in `pizzeria_dwh.pruefergebnisse`.

**Warum eine Prozedur:**
- Ein Workflow kann keine Dateien aus dem Repo lesen.
- Mit der Prozedur bleibt `05_pruefungen.sql` die einzige Quelle für das SQL.
- Ausrollen ist ein einziger Befehl. Er muss nach jeder Änderung an 05 wiederholt werden.

**Warum das Dataset als Argument:**
- Die ganze Kette lässt sich zuerst auf `pizzeria_dwh_test` testen, auch mit Gegentest, ohne `pizzeria_dwh` anzufassen.
- Weil der Name in die SQL-Anweisung eingesetzt wird, lässt der Workflow nur die zwei bekannten Datasets zu.

**Was schon geprüft ist:** Ein Dry Run von `CREATE OR REPLACE PROCEDURE pizzeria_dwh_test.pruefungen() BEGIN <Inhalt von 05> END;` meldet „Query successfully validated“. 05 lässt sich also so in eine Prozedur einpacken. Ein Dry Run legt nichts an, `bq ls --routines pizzeria_dwh_test` ist danach leer.

## Befehle (nicht ausgeführt)

Die Reihenfolge ist: zuerst die ganze Kette auf `pizzeria_dwh_test` testen, erst danach `pizzeria_dwh` und der Zeitplan. Wer die Befehle ausführt, braucht im Projekt Owner-Rechte oder entsprechende Rollen. Für 5 und 7 braucht man zusätzlich `iam.serviceAccounts.actAs` auf `pruefungen-sa`, zum Beispiel über die Rolle Service Account User.

### 1. Prozedur anlegen

```bash
# Test-Dataset
{ echo 'CREATE OR REPLACE PROCEDURE pizzeria_dwh.pruefungen()'; echo 'BEGIN';
  cat sql/pizzeria_star_schema/05_pruefungen.sql; echo 'END;'; } \
  | sed "s/pizzeria_dwh\./pizzeria_dwh_test./g" \
  | bq query --use_legacy_sql=false --location=europe-west6 --project_id=daeng-banlar01-x4q9

# pizzeria_dwh, erst nach erfolgreichem Test (Schritt 5)
{ echo 'CREATE OR REPLACE PROCEDURE pizzeria_dwh.pruefungen()'; echo 'BEGIN';
  cat sql/pizzeria_star_schema/05_pruefungen.sql; echo 'END;'; } \
  | bq query --use_legacy_sql=false --location=europe-west6 --project_id=daeng-banlar01-x4q9
```

Nach jeder Änderung an 05 muss dieser Schritt wiederholt werden, sonst läuft im Zeitplan die alte Version.

### 2. Dienstkonto

```bash
gcloud iam service-accounts create pruefungen-sa \
  --display-name="Pizzeria Pruefungen (Workflow und Scheduler)"
```

### 3. Rechte

```bash
SA="serviceAccount:pruefungen-sa@daeng-banlar01-x4q9.iam.gserviceaccount.com"
gcloud projects add-iam-policy-binding daeng-banlar01-x4q9 --member="$SA" --role="roles/bigquery.jobUser"
gcloud projects add-iam-policy-binding daeng-banlar01-x4q9 --member="$SA" --role="roles/workflows.invoker"
bq query --use_legacy_sql=false --location=europe-west6 --project_id=daeng-banlar01-x4q9 \
  "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA pizzeria_dwh_test TO \"$SA\""
bq query --use_legacy_sql=false --location=europe-west6 --project_id=daeng-banlar01-x4q9 \
  "GRANT \`roles/bigquery.dataEditor\` ON SCHEMA pizzeria_dwh TO \"$SA\""
```

| Rolle | Wo | Wofür |
|---|---|---|
| `roles/bigquery.jobUser` | Projekt | BigQuery-Jobs starten (`CALL …`) |
| `roles/workflows.invoker` | Projekt | Der Scheduler darf den Workflow starten. Dasselbe Dienstkonto dient für beides. |
| `roles/bigquery.dataEditor` | Dataset `pizzeria_dwh_test` bzw. `pizzeria_dwh` | Prozedur aufrufen, Tabellen lesen, `pruefergebnisse` anlegen und beschreiben |

### 4. Workflow-Datei `pipeline/workflow-pruefungen.yaml` (Vorschlag, nicht angelegt)

```yaml
# Workflow pizzeria-pruefungen: führt die Prüfungen aus sql/pizzeria_star_schema/05_pruefungen.sql aus.
#
# Ruft die Prozedur <dataset>.pruefungen() auf, die den Inhalt von 05 enthält. Meldet eine Prüfung
# FAIL, scheitert der BigQuery-Job an der Abschlussprüfung in 05. Damit scheitert dieser Schritt,
# und der Workflow endet mit einem Fehler. Der Alarm in alert-policy.yaml meldet das per E-Mail.
# Argument: {"dataset": "pizzeria_dwh"} im Zeitplan, {"dataset": "pizzeria_dwh_test"} zum Testen.
# Keine Wiederholungen: Ein FAIL soll auffallen und nicht still ein zweites Mal laufen.

main:
  params: [args]
  steps:
    - init:
        assign:
          - project: ${sys.get_env("GOOGLE_CLOUD_PROJECT_ID")}
          - dataset: ${args.dataset}

    - check_dataset:
        # Der Name wird in die SQL-Anweisung eingesetzt, darum nur bekannte Datasets.
        switch:
          - condition: ${not(dataset in ["pizzeria_dwh", "pizzeria_dwh_test"])}
            steps:
              - stop_unknown_dataset:
                  raise: '${"Unbekanntes Dataset " + dataset}'

    - run_checks:
        # Der Connector startet den Job und wartet, bis er fertig ist. Scheitert der Job, wirft der
        # Connector einen Fehler, und der Workflow endet hier (beim Test in Schritt 5 bestätigen).
        call: googleapis.bigquery.v2.jobs.insert
        args:
          projectId: ${project}
          body:
            jobReference:
              location: europe-west6
            configuration:
              query:
                useLegacySql: false
                query: ${"CALL " + dataset + ".pruefungen()"}
        result: job

    - done:
        return:
          dataset: ${dataset}
          bigquery_job: ${job.jobReference.jobId}
```

### 5. Workflow bereitstellen und auf dem Test-Dataset testen

```bash
gcloud workflows deploy pizzeria-pruefungen --location=europe-west6 \
  --source=pipeline/workflow-pruefungen.yaml \
  --service-account=pruefungen-sa@daeng-banlar01-x4q9.iam.gserviceaccount.com

# a) Normaler Lauf. Erwartet: Execution SUCCEEDED
gcloud workflows run pizzeria-pruefungen --location=europe-west6 --data='{"dataset": "pizzeria_dwh_test"}'

# b) Gegentest. Eine Faktenzeile im Test-Dataset löschen (DELETE wie in automatische-pruefungen.md), dann:
gcloud workflows run pizzeria-pruefungen --location=europe-west6 --data='{"dataset": "pizzeria_dwh_test"}'
#    Erwartet: Execution FAILED mit "2 Pruefungen FAIL (6a, 6b)"

# c) Wiederherstellen
scripts/run_pipeline.sh pizzeria_dwh_test
```

### 6. Alarm anlegen

`pipeline/alert-policy.yaml` hat `CHANNEL_ID` als Platzhalter. Zuerst braucht es einen E-Mail-Kanal, danach die Richtlinie mit der Kanal-ID. Die ID kommt in eine Kopie der Datei, nicht ins Repo.

```bash
gcloud beta monitoring channels create --display-name="Pipeline-Alarm" --type=email \
  --channel-labels=email_address=<eigene-adresse>
gcloud monitoring policies create --policy-from-file=<kopie-von-alert-policy.yaml>
```

Der Name der Richtlinie lautet „gtfs-pipeline fehlgeschlagen“, sie meldet aber jeden fehlgeschlagenen Workflow. Ein allgemeinerer Name wäre beim Anlegen sinnvoll. Ob `channels create` ohne `beta` geht, ist nicht geprüft.

Den Test aus 5b kann man nach dem Anlegen der Richtlinie wiederholen. Dann sollte die E-Mail kommen.

### 7. Zeitplan

```bash
gcloud scheduler jobs create http pizzeria-pruefungen-montag \
  --location=europe-west6 \
  --schedule="0 6 * * 1" --time-zone="Europe/Zurich" \
  --http-method=POST \
  --uri="https://workflowexecutions.googleapis.com/v1/projects/daeng-banlar01-x4q9/locations/europe-west6/workflows/pizzeria-pruefungen/executions" \
  --message-body='{"argument": "{\"dataset\": \"pizzeria_dwh\"}"}' \
  --oauth-service-account-email=pruefungen-sa@daeng-banlar01-x4q9.iam.gserviceaccount.com

# Einmal sofort auslösen, statt bis Montag zu warten. Das hängt einen Lauf an pizzeria_dwh.pruefergebnisse an.
gcloud scheduler jobs run pizzeria-pruefungen-montag --location=europe-west6
```

## Offen und zu prüfen

- **Connector:** Dass `googleapis.bigquery.v2.jobs.insert` auf das Ende des Jobs wartet und bei einem gescheiterten Job einen Fehler wirft, ist angenommen, nicht geprüft. Test 5b bestätigt oder widerlegt das.
- **Rechte:** `dataEditor` auf dem ganzen Dataset erlaubt `pruefungen-sa`, jede Tabelle in `pizzeria_dwh` zu ändern. Enger wäre: `dataViewer` auf dem Dataset und `dataEditor` nur auf der Tabelle `pruefergebnisse`. Ob `CREATE TABLE IF NOT EXISTS` mit diesen Rechten durchkommt, wenn die Tabelle schon existiert, ist nicht geprüft. Das liesse sich auf `pizzeria_dwh_test` testen.
- **Region:** Dass Cloud Scheduler in europe-west6 verfügbar ist, ist angenommen. Die README nennt europe-west6 für den gtfs-Zeitplan.
- **Gleiche Daten:** Der Montagslauf prüft dieselben Daten, solange 01 bis 03 nicht neu laufen (siehe Grenzen in [automatische-pruefungen.md](automatische-pruefungen.md)). Eine mögliche Erweiterung wäre, im Workflow vorher auch 01 bis 03 laufen zu lassen. Das ist eine eigene Entscheidung.
- **Kosten:** BigQuery hat beim Erstlauf von 05 32 052 Bytes verarbeitet und 80 MiB abgerechnet (Mindestmenge). Für Cloud Scheduler und Workflows gibt es kostenlose Kontingente; deren aktuelle Höhe ist nicht geprüft.

## Rückbau (falls nicht mehr gewünscht)

Nur nach ausdrücklicher Bestätigung und ohne `--quiet`:

```bash
gcloud scheduler jobs delete pizzeria-pruefungen-montag --location=europe-west6
gcloud workflows delete pizzeria-pruefungen --location=europe-west6
bq query --use_legacy_sql=false --location=europe-west6 'DROP PROCEDURE pizzeria_dwh.pruefungen'
gcloud iam service-accounts delete pruefungen-sa@daeng-banlar01-x4q9.iam.gserviceaccount.com
```
