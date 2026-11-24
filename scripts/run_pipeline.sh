#!/usr/bin/env bash
# scripts/run_pipeline.sh
# Fuehrt sql/pizzeria_star_schema/01 bis 04 gegen ein frei waehlbares Dataset aus.
#
# Aufruf:  scripts/run_pipeline.sh <dataset>
# Beispiel: scripts/run_pipeline.sh pizzeria_dwh_test
#
# - Die Originaldateien bleiben unveraendert. Das Skript ersetzt "pizzeria_dwh." (nur mit Punkt)
#   durch "<dataset>." in Kopien in einem temporaeren Ordner und fuehrt diese der Reihe nach aus.
# - Bricht beim ersten Fehler ab.
# - Das Dataset muss schon existieren (bq mk --dataset --location=europe-west6 <projekt>:<dataset>).
# - Jeder Schritt bekommt eine feste Job-ID: pipeline_<dataset>_<lauf-id>_<datei>.
# - Der temporaere Ordner wird nicht geloescht, damit man nachsehen kann, was gelaufen ist.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Aufruf: $0 <dataset>   (z. B. $0 pizzeria_dwh_test)" >&2
  exit 1
fi
dataset="$1"

# Nur Buchstaben, Ziffern und _ (gueltige Dataset-Namen). Schuetzt auch die sed-Ersetzung.
if [[ ! "$dataset" =~ ^[A-Za-z0-9_]+$ ]]; then
  echo "Abbruch: ungueltiger Dataset-Name '$dataset'." >&2
  exit 1
fi

# Schutz: pizzeria_dwh ist das produktive Dataset und wird von diesem Skript nicht angefasst.
if [[ "$dataset" == "pizzeria_dwh" ]]; then
  echo "Abbruch: pizzeria_dwh ist das produktive Dataset. Bitte ein Test-Dataset angeben." >&2
  exit 1
fi

projekt="$(gcloud config get-value project 2>/dev/null)"
if [[ -z "$projekt" ]]; then
  echo "Abbruch: kein Standardprojekt gesetzt (gcloud config get-value project ist leer)." >&2
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sql_dir="$repo_root/sql/pizzeria_star_schema"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/run_pipeline.XXXXXX")"
lauf_id="$(date +%Y%m%d_%H%M%S)"

echo "Projekt:      $projekt"
echo "Ziel-Dataset: $dataset"
echo "Lauf-ID:      $lauf_id"
echo "Kopien in:    $tmp_dir"

for name in 01_ddl 02_dimensionen 03_elt 04_checks; do
  sed "s/pizzeria_dwh\./${dataset}./g" "$sql_dir/$name.sql" > "$tmp_dir/$name.sql"
  job_id="pipeline_${dataset}_${lauf_id}_${name}"
  echo
  echo "=== $name  (Job-ID $job_id)"
  bq query \
    --use_legacy_sql=false \
    --location=europe-west6 \
    --project_id="$projekt" \
    --job_id="$job_id" \
    < "$tmp_dir/$name.sql"
done

echo
echo "Fertig: 01 bis 04 ohne Fehler gegen $projekt:$dataset gelaufen (Lauf-ID $lauf_id)."
