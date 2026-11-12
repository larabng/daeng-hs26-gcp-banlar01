-- 04_checks.sql
-- Prueft das Star Schema. Liest nur, aendert nichts.
-- Abfrage A: PASS/FAIL-Uebersicht. Abfragen B-D: Ergebnislisten (Zeilenzahlen, Roll-up, Slice).

-- A) PASS/FAIL-Uebersicht
WITH
stg AS (
  SELECT
    COUNT(*)                                                         AS zeilen,
    SUM(CAST(NULLIF(TRIM(bestellungen_angenommen), '') AS INT64))    AS angenommen,
    SUM(CAST(NULLIF(TRIM(pizzen), '') AS INT64))                     AS pizzen
  FROM pizzeria_dwh.stg_datenausschnitt
),
fakt AS (
  SELECT
    COUNT(*)                                                         AS zeilen,
    SUM(IF(status_id = 1, anzahl_bestellungen, 0))                   AS angenommen,
    SUM(IF(status_id = 1, anzahl_pizzen, 0))                         AS pizzen,
    COUNTIF(kanal_id = 9  AND status_id = 1)                         AS kasse_angenommen,
    COUNTIF(kanal_id = 10 AND status_id = 1)                         AS app_angenommen,
    COUNTIF(kanal_id = 10 AND status_id = 5)                         AS app_abgelehnt,
    COUNTIF(kanal_id = 9  AND status_id <> 1)                        AS kasse_absagezeilen,
    SUM(IF(kanal_id = 10 AND status_id = 5, anzahl_bestellungen, 0)) AS summe_app_absagen
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
  -- Zusatz: Wetter, Temperatur, Event und Wochentag muessen pro Datum eindeutig sein,
  -- sonst gehoeren sie nicht in dim_datum (Annahme hinter der BCNF der Faktentabelle).
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
  -- Zusatz: Wochentag aus der CSV = aus dem Datum berechneter Wochentag in dim_datum
  SELECT COUNT(*) AS abweichungen
  FROM (SELECT DISTINCT TRIM(datum) AS datum, TRIM(wochentag) AS wochentag FROM pizzeria_dwh.stg_datenausschnitt) s
  JOIN pizzeria_dwh.dim_datum d ON d.datum = PARSE_DATE('%Y-%m-%d', s.datum)
  WHERE d.wochentag <> s.wochentag
)
SELECT nr, pruefung, IF(ok, 'PASS', 'FAIL') AS ergebnis, detail FROM (
  SELECT '1a' AS nr, 'Summe angenommene Bestellungen Fakt = Staging' AS pruefung,
         fakt.angenommen = stg.angenommen AS ok,
         FORMAT('Fakt %d, Staging %d', fakt.angenommen, stg.angenommen) AS detail
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
  SELECT '6a', 'Faktenzeilen = 432 (144 Kasse angen. + 144 App angen. + 144 App abgel.)',
         zeilen = 432 AND kasse_angenommen = 144 AND app_angenommen = 144
           AND app_abgelehnt = 144 AND kasse_absagezeilen = 0,
         FORMAT('gesamt %d: Kasse angen. %d, App angen. %d, App abgel. %d, Kasse Absage-Zeilen %d',
                zeilen, kasse_angenommen, app_angenommen, app_abgelehnt, kasse_absagezeilen)
  FROM fakt
  UNION ALL
  SELECT '6b', 'Summe App-Absagen = 9',
         summe_app_absagen = 9, FORMAT('Summe %d', summe_app_absagen)
  FROM fakt
  UNION ALL
  SELECT 'Z1', 'Zusatz: Wetter/Temperatur/Event/Wochentag pro Datum eindeutig',
         n = 0, FORMAT('%d Tage mit widerspruechlichen Werten', n)
  FROM tag_eindeutig
  UNION ALL
  SELECT 'Z2', 'Zusatz: Wochentag CSV = berechneter Wochentag in dim_datum',
         abweichungen = 0, FORMAT('%d Abweichungen', abweichungen)
  FROM wochentag_ok
)
ORDER BY nr;

-- B) Check 1: Zeilenzahl je Tabelle
SELECT 'stg_datenausschnitt' AS tabelle, COUNT(*) AS zeilen FROM pizzeria_dwh.stg_datenausschnitt
UNION ALL SELECT 'dim_datum',              COUNT(*) FROM pizzeria_dwh.dim_datum
UNION ALL SELECT 'dim_stunde',             COUNT(*) FROM pizzeria_dwh.dim_stunde
UNION ALL SELECT 'dim_kanal',              COUNT(*) FROM pizzeria_dwh.dim_kanal
UNION ALL SELECT 'dim_bestellstatus',      COUNT(*) FROM pizzeria_dwh.dim_bestellstatus
UNION ALL SELECT 'fakt_bestellung_stunde', COUNT(*) FROM pizzeria_dwh.fakt_bestellung_stunde
ORDER BY tabelle;

-- C) Check 4: Roll-up. Nachfrage (angenommen + abgelehnt) pro Datum und kanal_gruppe.
-- abgelehnt = NULL heisst unbekannt (Kasse erfasst keine Absagen), nicht 0.
-- nachfrage_bekannt zaehlt nur, was erfasst ist; bei der Kasse ist das eine Untergrenze.
SELECT
  d.datum,
  d.wochentag,
  k.kanal_gruppe,
  SUM(IF(s.status = 'angenommen', f.anzahl_bestellungen, NULL)) AS angenommen,
  SUM(IF(s.status = 'abgelehnt',  f.anzahl_bestellungen, NULL)) AS abgelehnt,
  SUM(f.anzahl_bestellungen)                                    AS nachfrage_bekannt
FROM pizzeria_dwh.fakt_bestellung_stunde f
JOIN pizzeria_dwh.dim_datum         d ON f.datum_id  = d.datum_id
JOIN pizzeria_dwh.dim_kanal         k ON f.kanal_id  = k.kanal_id
JOIN pizzeria_dwh.dim_bestellstatus s ON f.status_id = s.status_id
GROUP BY d.datum, d.wochentag, k.kanal_gruppe
ORDER BY d.datum, k.kanal_gruppe;

-- D) Check 5: Slice. Bestellungen pro Stunde, nur an Regentagen (wetter_ist = 'Regen').
SELECT
  h.stunde_id,
  h.tageszeit,
  COUNT(DISTINCT d.datum_id)                                    AS anzahl_regentage,
  SUM(IF(s.status = 'angenommen', f.anzahl_bestellungen, NULL)) AS angenommen,
  SUM(IF(s.status = 'abgelehnt',  f.anzahl_bestellungen, NULL)) AS abgelehnt_app,
  SUM(IF(s.status = 'angenommen', f.anzahl_pizzen, NULL))       AS pizzen
FROM pizzeria_dwh.fakt_bestellung_stunde f
JOIN pizzeria_dwh.dim_datum         d ON f.datum_id  = d.datum_id
JOIN pizzeria_dwh.dim_stunde        h ON f.stunde_id = h.stunde_id
JOIN pizzeria_dwh.dim_bestellstatus s ON f.status_id = s.status_id
WHERE d.wetter_ist = 'Regen'
GROUP BY h.stunde_id, h.tageszeit
ORDER BY h.stunde_id;
