# Woche 10: Eignungsrisiko und Verbesserungen

Stand: 23.11.2026, Branch `woche10/lifecycle-mapping`

**Grundlage:** die Spalte „Lücke“ in [lifecycle-mapping.md](lifecycle-mapping.md). Dort stehen auch die Belege aus dem Repo und dem BigQuery-Job-Verlauf. Neu dazu kommt hier eine Abfrage auf `dim_datum` vom 23.11.2026 (siehe Abschnitt „Beleg Wochentage“).

**Legende:** (b) belegt, (v) vermutet. Wirkung und Aufwand sind Einschätzungen.

## Entscheidung

Quelle: System Charter V2 und BI Mission Brief (nicht im Repo).

- **Hauptentscheidung:** Nimmt der Küchenchef bei hoher Auslastung eine Bestellung noch an? Das betrifft Freitag- und Samstagabend von 18 bis 21 Uhr. Zugesagt sind 45 Minuten bis zur Lieferung, davon rund 35 für die Küche. Heute entscheidet der Küchenchef nach Gefühl, ohne festes Limit.
- **Nebenentscheidung:** Wochenend-Einsatzplan.

## Drei priorisierte Verbesserungen

Die Reihenfolge richtet sich zuerst nach der Wirkung auf die Entscheidung, dann nach dem Aufwand.

### 1. Fertig-Zeit beschaffen (die Durchlaufzeit ist NULL)

- **Beleg:** `01_ddl.sql:81`, `03_elt.sql:108`. Alle 432 Faktenzeilen wurden mit `summe_durchlaufzeit_min = NULL` eingefügt (b).
- **Gap-Typ:** fehlend
- **Betroffene Entscheidung:** die Hauptentscheidung, und zwar direkt. Ohne den Zeitpunkt „fertig“ lässt sich nicht messen, ob eine weitere Bestellung über die 35 Küchenminuten hinausgeht (b).
- **Risiko:** Der Küchenchef entscheidet weiter nach Gefühl, ein festes Limit lässt sich nicht begründen. Auch wenn die Spalte gefüllt ist, liefert `summe_durchlaufzeit_min` pro Stunde nur einen Durchschnitt. Wie viele Bestellungen über 35 Minuten lagen, zeigt sie nicht. Das Design ist belegt (`01_ddl.sql:73`, `01_ddl.sql:81`), die Folge für das Limit ist vermutet (v).
- **Massnahme:** **beschaffen:** den Zeitpunkt „fertig“ pro Bestellung (SP-03, `01_ddl.sql:81`). **Ändern:** zusätzlich pro Stunde die Anzahl der Bestellungen über 35 Minuten speichern (Vorschlag, v).
- **Wirkung / Aufwand:** sehr hoch / gross. Woher die Fertig-Zeit kommt, ist offen.

### 2. Absagen an der Kasse erfassen

- **Beleg:** `03_elt.sql:71`, `04_checks.sql:118-119` (b)
- **Gap-Typ:** fehlend
- **Betroffene Entscheidung:** beide.
  - Hauptentscheidung: Wie oft heute an Kasse und Telefon abgelehnt wird, sieht man nicht.
  - Einsatzplan: Die Nachfrage an der Kasse ist nur eine Untergrenze (b, `04_checks.sql:119`).
- **Risiko:** Das Personal für Freitag und Samstag wird zu knapp geplant (v). Ein Limit lässt sich nicht mit der heutigen Praxis an der Kasse vergleichen (v).
- **Massnahme:** sofort **einschränken:** die Kassen-Nachfrage überall als Untergrenze ausweisen und die Absagequote nur für die App angeben. Danach **beschaffen:** Absagen an Kasse und Telefon zählen.
- **Wirkung / Aufwand:** hoch / klein beim Einschränken, mittel beim Beschaffen

### 3. Absagegrund beschaffen

- **Beleg:** Alle App-Absagen bekommen `status_id` 5 „ohne Angabe“ (`03_elt.sql:69-71`). „Küche ausgelastet“ ist angelegt, bleibt aber leer (`02_dimensionen.sql:53`) (b).
- **Gap-Typ:** fehlend
- **Betroffene Entscheidung:** die Hauptentscheidung. „Küche ausgelastet“ ist genau die Entscheidung, die heute nach Gefühl fällt. Ohne den Grund sieht man nicht, wie oft sie fällt.
- **Risiko:** Ein Limit lässt sich nicht an der heutigen Praxis ausrichten (v).
- **Massnahme:** **beschaffen:** den Grund aus dem Partner-Portal holen. Ob das Portal ihn liefert, ist offen. Sonst **einschränken:** nur die Anzahl der Absagen auswerten.
- **Wirkung / Aufwand:** hoch / mittel

## Weitere Lücken

| Rang | Lücke und Beleg | Gap-Typ | Betroffene Entscheidung | Risiko | Massnahme | Wirkung / Aufwand |
|---|---|---|---|---|---|---|
| 4 | Die Kanäle 1-4 werden nicht befüllt. Angelegt sind sie in `02_dimensionen.sql:33-36`, aber `03_elt.sql:80-83` kennt nur 9 und 10. Lauf 2 fügte 432 Zeilen ohne Abbruch ein, also kam kein anderer Kanal vor (`03_elt.sql:72`) (b) | fehlend | Hauptentscheidung: Die Gruppe „Kasse“ mischt vor Ort und Telefon. Welche Bestellungen die 45-Minuten-Zusage haben, ist unklar (v) | Ein Limit kann nicht zwischen Lieferung und vor Ort unterscheiden (v) | einschränken (nur `kanal_gruppe` auswerten); beschaffen, falls pro Kanal entschieden wird | mittel / mittel |
| 5 | Der MERGE hat kein `WHEN NOT MATCHED BY SOURCE` (`03_elt.sql:74-108`). Bisher gab es einen Lauf, 0 Zeilen gelöscht (b) | widersprüchlich (möglich) | alle, die auf Summen aus der Faktentabelle beruhen | Bei einem anderen Ausschnitt bleiben alte Zeilen stehen (v). 1a/1b in `04_checks.sql:68-76` würden das melden (b) | ändern | niedrig / klein |
| 6 | Es gibt kein Rechtekonzept. 01-04 enthalten keine GRANT- oder IAM-Regel, Jobs laufen unter zwei Kursaccounts, und die Ergebnisse von 04 sind für andere nicht lesbar (Access Denied) (b) | fehlend | indirekt: ob man den Zahlen trauen kann | Den Qualitätsnachweis kann nicht das ganze Team prüfen (b) | ändern (Ergebnisse festhalten), beschaffen (Rollen klären) | niedrig / klein |

## Eignungsrisiko

### Hauptentscheidung

- **Küchenzeit:** Sie fehlt ganz. `summe_durchlaufzeit_min` ist in allen 432 Faktenzeilen NULL (b).
- **Wochentage:** `dim_datum` enthält 6 Samstage (19.09. bis 24.10.2026) und 6 Sonntage (20.09. bis 25.10.2026), aber keinen Freitag (b, siehe Abfrage unten). Für Freitag gibt es also keine Daten. Der Sonntag spielt für die Entscheidung keine Rolle. Nutzbar sind 6 Samstagabende. Für ein Limit ist das eine schmale Basis (v).
- **Zeitfenster:** Die Entscheidung betrifft 18 bis 21 Uhr, das sind `stunde_id` 18, 19 und 20 (b, `02_dimensionen.sql:11-12`: `stunde_von = TIME(h, 0, 0)`, `stunde_bis = TIME(h + 1, 0, 0)`). Das Flag `im_betrachtungsfenster` umfasst dagegen `stunde_id` 17 bis 22 (b, `02_dimensionen.sql:19`), also 17:00 bis 23:00. Der Kommentar in `01_ddl.sql:48` spricht von „17 bis 22 Uhr“, aus dem Code ergibt sich 17:00 bis 23:00 (b). Auswertungen für die Entscheidung müssen deshalb auf `stunde_id` 18 bis 20 filtern, nicht auf das Flag (b).
- **Auslastung:** nur pro Stunde und nur als angenommene Bestellungen und Pizzen (b, Grain `01_ddl.sql:73`).
- **Datenqualität:** nicht nachgewiesen. 04 lief am 12.11. ohne Fehler, aber die PASS/FAIL-Werte sind nicht lesbar (b, siehe lifecycle-mapping.md).
- **Urteil: hoch.** Mit diesen Daten lässt sich kein Limit für die Annahme begründen, weil sowohl die Küchenzeit als auch der Freitag fehlen (b).

### Nebenentscheidung (Wochenend-Einsatzplan)

- Angenommene Bestellungen und Pizzen pro Stunde sind vorhanden (b).
- Die Nachfrage an der Kasse ist nur eine Untergrenze (b).
- Der Freitag fehlt (b).
- **Urteil:** für Freitag **hoch**, weil es keine Daten gibt (b). Für Samstag **mittel**: Die Kasse liefert nur eine Untergrenze, und es gibt nur 6 Samstage (v).

## Hinweis für Woche 11

Die Sollwerte in `04_checks.sql:87-96` sind fest auf diesen Datenausschnitt eingestellt: 432 Faktenzeilen (je 144 für Kasse angenommen, App angenommen und App abgelehnt) und 9 App-Absagen. Auf dem Testdatensatz werden 6a und 6b vermutlich auch dann fehlschlagen, wenn alles richtig läuft (v). Das ist keine Verbesserung, nur ein Hinweis.

## Beleg Wochentage

Ausgeführt am 23.11.2026 unter dem eigenen Kursaccount, nur lesend. Der Dry Run meldete 156 Bytes. Nach dem 12.11. gab es im Job-Verlauf nur noch lesende Jobs. Der Stand entspricht also dem vom 12.11. (b, siehe lifecycle-mapping.md).

```sql
SELECT wochentag, ist_wochenende, COUNT(*) AS tage, MIN(datum) AS von, MAX(datum) AS bis
FROM pizzeria_dwh.dim_datum
GROUP BY 1, 2
ORDER BY MIN(datum)
```

| wochentag | ist_wochenende | tage | von | bis |
|---|---|---|---|---|
| Sa | true | 6 | 2026-09-19 | 2026-10-24 |
| So | true | 6 | 2026-09-20 | 2026-10-25 |
