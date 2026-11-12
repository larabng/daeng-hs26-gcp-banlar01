-- 02_dimensionen.sql
-- Befuellt die festen Dimensionen (Stunde, Kanal, Bestellstatus) per MERGE.
-- Wiederholbar: bestehende Zeilen werden aktualisiert, fehlende eingefuegt.
-- dim_datum wird aus den Rohdaten abgeleitet und steht deshalb in 03_elt.sql.

-- dim_stunde: 11 bis 22 Uhr
MERGE pizzeria_dwh.dim_stunde AS t
USING (
  SELECT
    h                                    AS stunde_id,
    TIME(h, 0, 0)                        AS stunde_von,
    TIME(h + 1, 0, 0)                    AS stunde_bis,
    CASE
      WHEN h BETWEEN 11 AND 14 THEN 'Mittag'
      WHEN h BETWEEN 15 AND 16 THEN 'Nachmittag'
      WHEN h BETWEEN 17 AND 22 THEN 'Abend'
    END                                  AS tageszeit,
    h IN (19, 20)                        AS ist_spitzenstunde,
    h BETWEEN 17 AND 22                  AS im_betrachtungsfenster
  FROM UNNEST(GENERATE_ARRAY(11, 22)) AS h
) AS s
ON t.stunde_id = s.stunde_id
WHEN MATCHED THEN UPDATE SET
  stunde_von = s.stunde_von, stunde_bis = s.stunde_bis, tageszeit = s.tageszeit,
  ist_spitzenstunde = s.ist_spitzenstunde, im_betrachtungsfenster = s.im_betrachtungsfenster
WHEN NOT MATCHED THEN INSERT ROW;

-- dim_kanal: feste Zeilen
MERGE pizzeria_dwh.dim_kanal AS t
USING (
  SELECT * FROM UNNEST([
    STRUCT<kanal_id INT64, kanal STRING, kanal_gruppe STRING, plattform STRING, quellsystem STRING, source_id STRING>
    ( 1, 'vor Ort',                  'Kasse', NULL,        'Kasse',               'SRC-01'),
    ( 2, 'Telefon',                  'Kasse', NULL,        'Kasse / Strichliste', 'SRC-01'),
    ( 3, 'Just Eat',                 'App',   'Just Eat',  'Partner-Portal',      'SRC-02'),
    ( 4, 'Uber Eats',                'App',   'Uber Eats', 'Partner-Portal',      'SRC-02'),
    ( 9, 'Kasse (nicht aufgeteilt)', 'Kasse', NULL,        'Kasse',               'Datenausschnitt'),
    (10, 'App (nicht aufgeteilt)',   'App',   NULL,        'Partner-Portal',      'Datenausschnitt')
  ])
) AS s
ON t.kanal_id = s.kanal_id
WHEN MATCHED THEN UPDATE SET
  kanal = s.kanal, kanal_gruppe = s.kanal_gruppe, plattform = s.plattform,
  quellsystem = s.quellsystem, source_id = s.source_id
WHEN NOT MATCHED THEN INSERT ROW;

-- dim_bestellstatus: feste Zeilen
MERGE pizzeria_dwh.dim_bestellstatus AS t
USING (
  SELECT * FROM UNNEST([
    STRUCT<status_id INT64, status STRING, absagegrund STRING, grund_kategorie STRING>
    (1, 'angenommen', NULL,                NULL),
    (2, 'abgelehnt',  'Küche ausgelastet', 'Kapazität'),
    (3, 'abgelehnt',  'Teig aus',          'Verfügbarkeit'),
    (4, 'abgelehnt',  'Wartezeit zu lang', 'Kunde verzichtet'),
    (5, 'abgelehnt',  'ohne Angabe',       'unbekannt')
  ])
) AS s
ON t.status_id = s.status_id
WHEN MATCHED THEN UPDATE SET
  status = s.status, absagegrund = s.absagegrund, grund_kategorie = s.grund_kategorie
WHEN NOT MATCHED THEN INSERT ROW;
