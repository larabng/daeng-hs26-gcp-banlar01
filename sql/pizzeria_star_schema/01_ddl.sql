-- 01_ddl.sql
-- Pizzeria Da Luigi, Star Schema (BI HS2026, Woche 9)
-- Legt die Tabellen in pizzeria_dwh an. CREATE TABLE IF NOT EXISTS: ein zweiter Lauf
-- veraendert nichts an bestehenden Tabellen.
-- PK/FK sind NOT ENFORCED: BigQuery speichert sie als Metadaten, prueft sie aber nicht.
-- Die Pruefung uebernimmt 04_checks.sql.

-- Staging: Rohdaten aus dem Bucket, alle Spalten STRING (ELT: erst laden, dann in BigQuery transformieren)
CREATE TABLE IF NOT EXISTS pizzeria_dwh.stg_datenausschnitt (
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
OPTIONS (description = 'Rohdaten Datenausschnitt Pizzeria Da Luigi, unveraendert aus gs://daeng-banlar01-x4q9-raw/pizzeria/datenausschnitt_v1.csv');

-- Dimension Datum (denormalisiert: Kalender, Wetter und Event pro Tag)
CREATE TABLE IF NOT EXISTS pizzeria_dwh.dim_datum (
  datum_id           INT64 NOT NULL,   -- JJJJMMTT
  datum              DATE,
  wochentag          STRING,           -- Mo..So
  ist_wochenende     BOOL,
  kalenderwoche      INT64,            -- ISO
  monat              INT64,
  jahr               INT64,
  wetter_prognose_do STRING,
  wetter_ist         STRING,
  temperatur_ist_c   INT64,
  event_name         STRING,
  ist_eventtag       BOOL,
  PRIMARY KEY (datum_id) NOT ENFORCED
);

-- Dimension Stunde (volle Stunde 11 bis 22)
CREATE TABLE IF NOT EXISTS pizzeria_dwh.dim_stunde (
  stunde_id              INT64 NOT NULL,
  stunde_von             TIME,
  stunde_bis             TIME,
  tageszeit              STRING,       -- Mittag / Nachmittag / Abend
  ist_spitzenstunde      BOOL,         -- 19 und 20 Uhr
  im_betrachtungsfenster BOOL,         -- 17 bis 22 Uhr
  PRIMARY KEY (stunde_id) NOT ENFORCED
);

-- Dimension Kanal
CREATE TABLE IF NOT EXISTS pizzeria_dwh.dim_kanal (
  kanal_id     INT64 NOT NULL,
  kanal        STRING,
  kanal_gruppe STRING,
  plattform    STRING,
  quellsystem  STRING,
  source_id    STRING,
  PRIMARY KEY (kanal_id) NOT ENFORCED
);

-- Dimension Bestellstatus
CREATE TABLE IF NOT EXISTS pizzeria_dwh.dim_bestellstatus (
  status_id       INT64 NOT NULL,
  status          STRING,
  absagegrund     STRING,
  grund_kategorie STRING,
  PRIMARY KEY (status_id) NOT ENFORCED
);

-- Faktentabelle (BCNF): nur FKs auf die vier Dimensionen plus Kennzahlen.
-- Grain: eine Zeile pro Datum x Stunde x Kanal x Bestellstatus. PK = Kombination der FKs.
CREATE TABLE IF NOT EXISTS pizzeria_dwh.fakt_bestellung_stunde (
  datum_id                INT64 NOT NULL,
  stunde_id               INT64 NOT NULL,
  kanal_id                INT64 NOT NULL,
  status_id               INT64 NOT NULL,
  anzahl_bestellungen     INT64,
  anzahl_pizzen           INT64,        -- NULL, wenn unbekannt
  summe_durchlaufzeit_min INT64,        -- vorerst NULL, kommt spaeter aus der Fertig-Zeit (SP-03)
  PRIMARY KEY (datum_id, stunde_id, kanal_id, status_id) NOT ENFORCED,
  CONSTRAINT fk_datum  FOREIGN KEY (datum_id)  REFERENCES pizzeria_dwh.dim_datum (datum_id)                 NOT ENFORCED,
  CONSTRAINT fk_stunde FOREIGN KEY (stunde_id) REFERENCES pizzeria_dwh.dim_stunde (stunde_id)               NOT ENFORCED,
  CONSTRAINT fk_kanal  FOREIGN KEY (kanal_id)  REFERENCES pizzeria_dwh.dim_kanal (kanal_id)                 NOT ENFORCED,
  CONSTRAINT fk_status FOREIGN KEY (status_id) REFERENCES pizzeria_dwh.dim_bestellstatus (status_id)        NOT ENFORCED
);
