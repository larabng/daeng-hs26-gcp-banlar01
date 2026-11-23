# Woche 10: Korrekturen zu Woche 9

Stand: 23.11.2026, Branch `woche10/lifecycle-mapping`

Zu Woche 9 gibt es kein schriftliches Feedback. Die Korrekturen kommen aus der Arbeit in Woche 10 (siehe [lifecycle-mapping.md](lifecycle-mapping.md) und [eignungsrisiko-verbesserungen.md](eignungsrisiko-verbesserungen.md)). Die Dateien von Woche 9 (`sql/pizzeria_star_schema/01_ddl.sql` bis `04_checks.sql`) bleiben unverändert.

Die Abgabe von Woche 9 liegt nicht im Repo. Wo der frühere Wortlaut nur aus dieser Abgabe stammt, steht das dabei.

**Legende:** (b) belegt, (v) vermutet.

## a) Wochentage

- **Was stand:** Woche 9 sprach von Freitag und Samstag. Der Wortlaut ist nicht im Repo.
- **Was stimmt:** Der Datensatz enthält 6 Samstage (19.09. bis 24.10.2026) und 6 Sonntage (20.09. bis 25.10.2026), aber keinen Freitag (b).
- **Beleg:** die Abfrage auf `dim_datum` vom 23.11.2026, siehe [eignungsrisiko-verbesserungen.md](eignungsrisiko-verbesserungen.md#beleg-wochentage).

## b) „Mit den Absagen wäre die Abendspitze höher“

- **Was stand:** „Mit den Absagen wäre die Abendspitze höher.“ Der Wortlaut ist nicht im Repo.
- **Was stimmt:** Die Aussage stammt aus dem Datengenerator, nicht aus einer Messung. Sie ist darum eine **Annahme (v)**. Für die Kasse lässt sie sich mit diesen Daten auch nicht messen, weil die Kasse keine Absagen erfasst (b). Für die App sind die Absagen pro Stunde in der Faktentabelle angelegt (b), aber es gibt keine lesbare Auswertung dazu. Abfrage D in 04 enthält `abgelehnt_app` pro Stunde nur für Regentage, und ihr Ergebnis ist nicht lesbar (b).
- **Beleg:** `03_elt.sql:71` (Kasse ohne Absagen), `03_elt.sql:93-96` (Absage-Zeilen der App pro Stunde), `04_checks.sql:134-148` (Abfrage D), [lifecycle-mapping.md](lifecycle-mapping.md#teil-jobs-der-skripte-vom-1211) (Ergebnisse von 04 nicht lesbar).

## c) Test 8 prüfte nur die Eindeutigkeit von `datum_id`

- **Was stand:** „Test 8: ein Wert pro Datum (erwartet: 0 Zeilen)“ mit der Abfrage `SELECT datum_id, COUNT(*) AS n FROM pizzeria_dwh.dim_datum GROUP BY datum_id HAVING n > 1` (b).
- **Was stimmt:** Test 8 prüft nur, ob `datum_id` in `dim_datum` eindeutig ist. Das stellt `03_elt.sql:43` (`GROUP BY` pro Datum) schon beim Laden sicher (b). Ob Wetter, Temperatur, Event und Wochentag pro Datum eindeutig sind, prüft erst Z1 (b). Diese Prüfung ist wichtig, weil `ANY_VALUE` in `03_elt.sql:38-41` ohne Meldung irgendeinen Wert nimmt, wenn es pro Tag mehrere gibt (b). Das Ergebnis von Z1 ist nicht lesbar (b).
- **Beleg:** der Query-Text von Job `job_-MxPduswR_Cd_DqWQYJfPtnLqhI0` (22.11.2026), `04_checks.sql:46-58` und `04_checks.sql:98-100` (Z1), `03_elt.sql:38-43`.

## d) Kommentar zum Betrachtungsfenster

- **Was stand:** `01_ddl.sql:48`: `im_betrachtungsfenster BOOL, -- 17 bis 22 Uhr`
- **Was stimmt:** Das Flag ist für `stunde_id` 17 bis 22 gesetzt. Weil `stunde_bis = TIME(h + 1, 0, 0)` ist, umfasst es 17:00 bis 23:00 (b).
- **Beleg:** `01_ddl.sql:48`, `02_dimensionen.sql:11-12`, `02_dimensionen.sql:19`
