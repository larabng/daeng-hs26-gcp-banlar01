# Woche 10: Google-Cloud-Workshop, Rollenperspektiven

Stand: 23.11.2026, Branch `woche10/lifecycle-mapping`

**Aufgabe:** Kursunterlage Woche 10, Folie 22, „Google-Cloud-Workshop: Rollenperspektiven prüfen“ (nicht im Repo). Laut Folie soll dabei herauskommen: ein überprüfter Datenfluss, ein dokumentiertes Eignungsrisiko und drei priorisierte Verbesserungen.

| Ergebnis | Wo |
|---|---|
| Überprüfter Datenfluss | Abschnitt „Engineering“ unten; Belege in [lifecycle-mapping.md](lifecycle-mapping.md#job-verlauf) |
| Eignungsrisiko | [eignungsrisiko-verbesserungen.md](eignungsrisiko-verbesserungen.md#eignungsrisiko) |
| Drei priorisierte Verbesserungen | [eignungsrisiko-verbesserungen.md](eignungsrisiko-verbesserungen.md#drei-priorisierte-verbesserungen) |

**Legende:** (b) belegt, (v) vermutet.

## Engineering: Datenfluss von der Quelle bis zum Datensatz

**Stand:** Die Aufgabe verlangt, den Datenfluss tatsächlich auszuführen. Für heute ist das nur durch den Lauf von banlar01 am 12.11.2026 belegt (b). Den eigenen Lauf machen wir in Woche 11 auf `pizzeria_dwh_test`.

```
gs://daeng-banlar01-x4q9-raw/pizzeria/datenausschnitt_v1.csv
  → LOAD DATA (03)   → pizzeria_dwh.stg_datenausschnitt
  → MERGE (03)       → dim_datum, fakt_bestellung_stunde
  feste Werte (02)   → dim_stunde, dim_kanal, dim_bestellstatus
```

So lief es am 12.11. (b). Job-IDs und Teil-Jobs stehen in [lifecycle-mapping.md](lifecycle-mapping.md#job-verlauf).

1. **14:55, `01_ddl.sql`:** 6 Tabellen in `pizzeria_dwh` neu angelegt (`ddlOperationPerformed = CREATE`).
2. **14:55, `02_dimensionen.sql`:** eingefügt wurden `dim_stunde` 12, `dim_kanal` 6 und `dim_bestellstatus` 5 Zeilen.
3. **14:56, `03_elt.sql`, Lauf 1: fehlgeschlagen.** Das `LOAD DATA` ohne Spaltenliste lief durch. Danach brach der MERGE auf `dim_datum` mit `errorResult.reason = invalidQuery` ab (`TRIM` auf DATE). Einzelheiten stehen in [lifecycle-mapping.md](lifecycle-mapping.md#fehler-im-ersten-lauf-von-03).
4. **Fix:** Das `LOAD DATA` bekam eine Spaltenliste, in der alle Spalten STRING sind (`03_elt.sql:8-23`).
5. **14:57, `03_elt.sql`, Lauf 2: SUCCESS.** Aus dem Bucket nach `stg_datenausschnitt` geladen wurde 1 Datei mit 16469 Bytes und 0 fehlerhaften Datensätzen. Danach wurden `dim_datum` 12 und `fakt_bestellung_stunde` 432 Zeilen eingefügt.
6. **14:57, Kontrolle:** Das Staging-Schema wurde über `INFORMATION_SCHEMA.COLUMNS` geprüft.
7. **14:58, `04_checks.sql`: SUCCESS.** Die Ergebnisse sind nicht lesbar.

**Überprüft:** Die Query-Texte der Läufe sind identisch mit 01 bis 04 in Commit `37374fa`. Den Status jedes Jobs und jedes Teil-Jobs habe ich gelesen (b).
**Nicht überprüft:** die PASS/FAIL-Werte von 04, weil sie nicht lesbar sind (b), und wer die Datei in den Bucket hochgeladen hat (offen).

## Science: Welche Analyse möglich ist und welche Annahmen sie braucht

**Möglich**, weil die Daten vorhanden sind (b):
- angenommene Bestellungen und Pizzen pro Stunde (`fakt_bestellung_stunde` mit `status_id` 1, Grain `01_ddl.sql:73`)
- Samstag gegen Sonntag (`dim_datum.wochentag`, je 6 Tage)

**Nötige Annahmen:**
- **Die Kasse liefert nur eine Untergrenze.** Absagen an der Kasse werden nicht erfasst (b, `03_elt.sql:71`, `04_checks.sql:118-119`). Die Nachfrage an der Kasse wird also unterschätzt.
- **Es gibt keine Fertig-Zeit.** `summe_durchlaufzeit_min` ist NULL (b). Über die Küchenzeit lässt sich nichts sagen. Die Auslastung gibt es nur als Anzahl Bestellungen und Pizzen.
- **Es gibt nur 6 Samstage.** Die Ergebnisse gelten für die Samstage vom 19.09. bis 24.10.2026 (b). Ob diese Samstage typisch sind, ist offen.
- **Es gibt keinen Freitag.** Wer etwas über Freitag aussagt, muss annehmen, dass der Freitag wie der Samstag läuft (v).
- **Wetter und Event gelten pro Tag.** `dim_datum` speichert Wetter und Event je Tag (b, `01_ddl.sql:24`, `03_elt.sql:32`). Angenommen wird, dass sie für den ganzen Abend gelten (v). Ob die Werte pro Tag eindeutig sind, prüft Z1 (`04_checks.sql:46-58`). Das Ergebnis von Z1 ist nicht lesbar (b). Gibt es pro Tag mehrere Werte, nimmt `ANY_VALUE` in `03_elt.sql:38-41` ohne Meldung irgendeinen davon (b).

Was das für die Entscheidung bedeutet, steht in [eignungsrisiko-verbesserungen.md](eignungsrisiko-verbesserungen.md#eignungsrisiko).

## Business: Welche Entscheidung der Datensatz unterstützen soll

Die Haupt- und die Nebenentscheidung stehen in [eignungsrisiko-verbesserungen.md](eignungsrisiko-verbesserungen.md#entscheidung). Ihre Quelle sind die System Charter V2 und der BI Mission Brief.
