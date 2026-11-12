-- 03_elt.sql
-- ELT: (1) Rohdatei aus dem Bucket unveraendert in die Staging-Tabelle laden,
--      (2) in BigQuery per SQL in dim_datum und fakt_bestellung_stunde transformieren.
-- Wiederholbar: Staging wird bei jedem Lauf neu geladen (eigene Tabelle), dim_datum und Fakten per MERGE.

-- (1) Extract/Load: alle Spalten STRING, Trennzeichen ;, Kopfzeile ueberspringen.
-- Die Datei ist UTF-8 mit BOM. Der BOM steht vor der Kopfzeile und faellt mit skip_leading_rows = 1 weg.
-- Die Spaltenliste ist Pflicht: ohne sie erkennt BigQuery die Typen selbst (datum DATE, Zahlen INT64)
-- und ersetzt das STRING-Schema aus 01_ddl.sql.
-- Leere Felder kommen als NULL oder leerer String an; die Transformation behandelt beides mit NULLIF(TRIM(x), '').
LOAD DATA OVERWRITE pizzeria_dwh.stg_datenausschnitt (
  datum                      STRING,
  wochentag                  STRING,
  stunde                     STRING,
  quelle_kanal               STRING,
  bestellungen_angenommen    STRING,
  bestellungen_abgelehnt_app STRING,
  pizzen                     STRING,
  wetter_prognose_do         STRING,
  wetter_ist                 STRING,
  temperatur_ist_c           STRING,
  event                      STRING
)
FROM FILES (
  format            = 'CSV',
  uris              = ['gs://daeng-banlar01-x4q9-raw/pizzeria/datenausschnitt_v1.csv'],
  field_delimiter   = ';',
  skip_leading_rows = 1,
  encoding          = 'UTF8'
);

-- (2a) dim_datum: eine Zeile pro Datum. Wetter und Event gelten pro Tag (BCNF der Faktentabelle).
MERGE pizzeria_dwh.dim_datum AS t
USING (
  WITH tage AS (
    SELECT
      PARSE_DATE('%Y-%m-%d', TRIM(datum))                                   AS datum,
      ANY_VALUE(NULLIF(TRIM(wetter_prognose_do), ''))                       AS wetter_prognose_do,
      ANY_VALUE(NULLIF(TRIM(wetter_ist), ''))                               AS wetter_ist,
      ANY_VALUE(CAST(NULLIF(TRIM(temperatur_ist_c), '') AS INT64))          AS temperatur_ist_c,
      ANY_VALUE(NULLIF(TRIM(event), ''))                                    AS event_name
    FROM pizzeria_dwh.stg_datenausschnitt
    GROUP BY 1
  )
  SELECT
    CAST(FORMAT_DATE('%Y%m%d', datum) AS INT64)                             AS datum_id,
    datum,
    ['So', 'Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa'][OFFSET(EXTRACT(DAYOFWEEK FROM datum) - 1)] AS wochentag,
    EXTRACT(DAYOFWEEK FROM datum) IN (1, 7)                                 AS ist_wochenende,
    EXTRACT(ISOWEEK FROM datum)                                             AS kalenderwoche,
    EXTRACT(MONTH FROM datum)                                               AS monat,
    EXTRACT(YEAR FROM datum)                                                AS jahr,
    wetter_prognose_do,
    wetter_ist,
    temperatur_ist_c,
    event_name,
    event_name IS NOT NULL                                                  AS ist_eventtag
  FROM tage
) AS s
ON t.datum_id = s.datum_id
WHEN MATCHED THEN UPDATE SET
  datum = s.datum, wochentag = s.wochentag, ist_wochenende = s.ist_wochenende,
  kalenderwoche = s.kalenderwoche, monat = s.monat, jahr = s.jahr,
  wetter_prognose_do = s.wetter_prognose_do, wetter_ist = s.wetter_ist,
  temperatur_ist_c = s.temperatur_ist_c, event_name = s.event_name, ist_eventtag = s.ist_eventtag
WHEN NOT MATCHED THEN INSERT ROW;

-- (2b) Faktentabelle.
-- Pro CSV-Zeile eine Zeile mit status_id 1 (angenommen).
-- Nur wenn bestellungen_abgelehnt_app nicht leer ist, zusaetzlich eine Zeile mit status_id 5
-- (abgelehnt, ohne Angabe), anzahl_pizzen = NULL. Leer bei der Kasse = unbekannt, keine Absage-Zeile.
-- Ein unbekannter quelle_kanal ergibt kanal_id NULL, und das Einfuegen bricht wegen NOT NULL ab (gewollt).
-- summe_durchlaufzeit_min wird nur beim Einfuegen auf NULL gesetzt und beim Update nicht angefasst.
MERGE pizzeria_dwh.fakt_bestellung_stunde AS t
USING (
  WITH roh AS (
    SELECT
      CAST(FORMAT_DATE('%Y%m%d', PARSE_DATE('%Y-%m-%d', TRIM(datum))) AS INT64) AS datum_id,
      CAST(SPLIT(TRIM(stunde), ':')[OFFSET(0)] AS INT64)                         AS stunde_id,
      CASE TRIM(quelle_kanal)
        WHEN 'Kasse (vor Ort + Telefon)' THEN 9
        WHEN 'App'                       THEN 10
      END                                                                         AS kanal_id,
      CAST(NULLIF(TRIM(bestellungen_angenommen), '') AS INT64)                   AS angenommen,
      CAST(NULLIF(TRIM(bestellungen_abgelehnt_app), '') AS INT64)                AS abgelehnt,
      CAST(NULLIF(TRIM(pizzen), '') AS INT64)                                    AS pizzen
    FROM pizzeria_dwh.stg_datenausschnitt
  )
  SELECT datum_id, stunde_id, kanal_id, 1 AS status_id,
         angenommen AS anzahl_bestellungen, pizzen AS anzahl_pizzen
  FROM roh
  UNION ALL
  SELECT datum_id, stunde_id, kanal_id, 5 AS status_id,
         abgelehnt AS anzahl_bestellungen, CAST(NULL AS INT64) AS anzahl_pizzen
  FROM roh
  WHERE abgelehnt IS NOT NULL
) AS s
ON  t.datum_id  = s.datum_id
AND t.stunde_id = s.stunde_id
AND t.kanal_id  = s.kanal_id
AND t.status_id = s.status_id
WHEN MATCHED THEN UPDATE SET
  anzahl_bestellungen = s.anzahl_bestellungen,
  anzahl_pizzen       = s.anzahl_pizzen
WHEN NOT MATCHED THEN INSERT
  (datum_id, stunde_id, kanal_id, status_id, anzahl_bestellungen, anzahl_pizzen, summe_durchlaufzeit_min)
VALUES
  (s.datum_id, s.stunde_id, s.kanal_id, s.status_id, s.anzahl_bestellungen, s.anzahl_pizzen, NULL);
