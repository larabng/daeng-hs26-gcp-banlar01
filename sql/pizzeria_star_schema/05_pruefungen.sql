-- 05_pruefungen.sql
-- Pizzeria Da Luigi, automatisierte Pruefungen (Woche 11)
-- Gleiche Pruefungen wie Abfrage A in 04_checks.sql, aber ohne feste Sollwerte:
--   6a: Faktenzeilen = Staging-Zeilen + Staging-Zeilen mit nicht leerem bestellungen_abgelehnt_app
--   6b: Summe App-Absagen in Fakt = Summe bestellungen_abgelehnt_app im Staging
-- Zusaetzlich Pruefung 0: Staging nicht leer.
-- Das Ergebnis wird an pizzeria_dwh.pruefergebnisse angehaengt: eine Zeile pro Pruefung und Lauf,
-- alle Zeilen eines Laufs haben dieselbe pruef_zeit. Alle anderen Tabellen werden nur gelesen.
-- lauf_zeit wird einmal am Anfang gesetzt und im INSERT, in der Anzeige und in der Abschlusspruefung
-- verwendet.
-- Abschlusspruefung am Ende: Hat dieser Lauf mindestens ein FAIL oder gar keine Zeile, bricht das
-- Skript mit ERROR ab, und der BigQuery-Job scheitert. Die Zeilen des Laufs bleiben trotzdem in
-- pruefergebnisse, weil das INSERT davor schon abgeschlossen ist.
-- Summen stehen in COALESCE(..., 0). Sonst wird NULL = 0 zu NULL und damit zu FAIL, obwohl beide
-- Seiten nichts enthalten. Ein leeres Staging faellt ueber Pruefung 0 auf.
-- Ist eine Bedingung NULL, ergibt das FAIL (IF(NULL, ...) nimmt den Sonst-Zweig).

DECLARE lauf_zeit TIMESTAMP DEFAULT CURRENT_TIMESTAMP();

CREATE TABLE IF NOT EXISTS pizzeria_dwh.pruefergebnisse (
  pruef_zeit TIMESTAMP,
  nr         STRING,
  pruefung   STRING,
  ergebnis   STRING,   -- PASS / FAIL
  detail     STRING
)
OPTIONS (description = 'Ergebnisse von 05_pruefungen.sql, eine Zeile pro Pruefung und Lauf');

INSERT INTO pizzeria_dwh.pruefergebnisse (pruef_zeit, nr, pruefung, ergebnis, detail)
WITH
stg AS (
  SELECT
    COUNT(*)                                                                      AS zeilen,
    COUNTIF(NULLIF(TRIM(bestellungen_abgelehnt_app), '') IS NOT NULL)             AS zeilen_mit_absage,
    COALESCE(SUM(CAST(NULLIF(TRIM(bestellungen_angenommen), '') AS INT64)), 0)    AS angenommen,
    COALESCE(SUM(CAST(NULLIF(TRIM(pizzen), '') AS INT64)), 0)                     AS pizzen,
    COALESCE(SUM(CAST(NULLIF(TRIM(bestellungen_abgelehnt_app), '') AS INT64)), 0) AS absagen
  FROM pizzeria_dwh.stg_datenausschnitt
),
fakt AS (
  SELECT
    COUNT(*)                                                                      AS zeilen,
    COALESCE(SUM(IF(status_id = 1, anzahl_bestellungen, 0)), 0)                   AS angenommen,
    COALESCE(SUM(IF(status_id = 1, anzahl_pizzen, 0)), 0)                         AS pizzen,
    COALESCE(SUM(IF(kanal_id = 10 AND status_id = 5, anzahl_bestellungen, 0)), 0) AS summe_app_absagen
  FROM pizzeria_dwh.fakt_bestellung_stunde
),
duplikate AS (
  SELECT COUNT(*) AS n FROM (
    SELECT datum_id, stunde_id, kanal_id, status_id
    FROM pizzeria_dwh.fakt_bestellung_stunde
    GROUP BY 1, 2, 3, 4
    HAVING COUNT(*) > 1
  )
),
verwaist AS (
  SELECT
    COUNTIF(d.datum_id  IS NULL) AS datum,
    COUNTIF(h.stunde_id IS NULL) AS stunde,
    COUNTIF(k.kanal_id  IS NULL) AS kanal,
    COUNTIF(s.status_id IS NULL) AS status
  FROM pizzeria_dwh.fakt_bestellung_stunde f
  LEFT JOIN pizzeria_dwh.dim_datum         d ON f.datum_id  = d.datum_id
  LEFT JOIN pizzeria_dwh.dim_stunde        h ON f.stunde_id = h.stunde_id
  LEFT JOIN pizzeria_dwh.dim_kanal         k ON f.kanal_id  = k.kanal_id
  LEFT JOIN pizzeria_dwh.dim_bestellstatus s ON f.status_id = s.status_id
),
tag_eindeutig AS (
  SELECT COUNT(*) AS n FROM (
    SELECT datum
    FROM pizzeria_dwh.stg_datenausschnitt
    GROUP BY datum
    HAVING COUNT(DISTINCT IFNULL(wetter_prognose_do, '~')) > 1
        OR COUNT(DISTINCT IFNULL(wetter_ist, '~')) > 1
        OR COUNT(DISTINCT IFNULL(temperatur_ist_c, '~')) > 1
        OR COUNT(DISTINCT IFNULL(event, '~')) > 1
        OR COUNT(DISTINCT wochentag) > 1
  )
),
wochentag_ok AS (
  SELECT COUNT(*) AS abweichungen
  FROM (SELECT DISTINCT TRIM(datum) AS datum, TRIM(wochentag) AS wochentag FROM pizzeria_dwh.stg_datenausschnitt) s
  JOIN pizzeria_dwh.dim_datum d ON d.datum = PARSE_DATE('%Y-%m-%d', s.datum)
  WHERE d.wochentag <> s.wochentag
)
SELECT lauf_zeit, nr, pruefung, IF(ok, 'PASS', 'FAIL'), detail FROM (
  SELECT '0' AS nr, 'Staging nicht leer' AS pruefung,
         stg.zeilen > 0 AS ok,
         FORMAT('%d Zeilen im Staging', stg.zeilen) AS detail
  FROM stg
  UNION ALL
  SELECT '1a', 'Summe angenommene Bestellungen Fakt = Staging',
         fakt.angenommen = stg.angenommen,
         FORMAT('Fakt %d, Staging %d', fakt.angenommen, stg.angenommen)
  FROM fakt, stg
  UNION ALL
  SELECT '1b', 'Summe Pizzen Fakt = Staging',
         fakt.pizzen = stg.pizzen,
         FORMAT('Fakt %d, Staging %d', fakt.pizzen, stg.pizzen)
  FROM fakt, stg
  UNION ALL
  SELECT '2', 'Keine doppelten Schluessel (datum, stunde, kanal, status)',
         n = 0, FORMAT('%d doppelte Schluessel', n)
  FROM duplikate
  UNION ALL
  SELECT '3', 'Keine verwaisten FKs',
         datum + stunde + kanal + status = 0,
         FORMAT('datum %d, stunde %d, kanal %d, status %d', datum, stunde, kanal, status)
  FROM verwaist
  UNION ALL
  SELECT '6a', 'Faktenzeilen = Staging-Zeilen + Staging-Zeilen mit Absage',
         fakt.zeilen = stg.zeilen + stg.zeilen_mit_absage,
         FORMAT('Fakt %d, erwartet %d (Staging %d + mit Absage %d)',
                fakt.zeilen, stg.zeilen + stg.zeilen_mit_absage, stg.zeilen, stg.zeilen_mit_absage)
  FROM fakt, stg
  UNION ALL
  SELECT '6b', 'Summe App-Absagen Fakt = Staging',
         fakt.summe_app_absagen = stg.absagen,
         FORMAT('Fakt %d, Staging %d', fakt.summe_app_absagen, stg.absagen)
  FROM fakt, stg
  UNION ALL
  SELECT 'Z1', 'Zusatz: Wetter/Temperatur/Event/Wochentag pro Datum eindeutig',
         n = 0, FORMAT('%d Tage mit widerspruechlichen Werten', n)
  FROM tag_eindeutig
  UNION ALL
  SELECT 'Z2', 'Zusatz: Wochentag CSV = berechneter Wochentag in dim_datum',
         abweichungen = 0, FORMAT('%d Abweichungen', abweichungen)
  FROM wochentag_ok
);

-- Ergebnis dieses Laufs anzeigen
SELECT pruef_zeit, nr, pruefung, ergebnis, detail
FROM pizzeria_dwh.pruefergebnisse
WHERE pruef_zeit = lauf_zeit
ORDER BY nr;

-- Abschlusspruefung: laesst den Job scheitern, wenn dieser Lauf mindestens ein FAIL hat
-- oder keine Zeile geschrieben hat. Muss die letzte Anweisung bleiben.
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
