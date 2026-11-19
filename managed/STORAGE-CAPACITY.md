# Database, bestandsopslag en compressie

De eigenaar bevestigde op 19 november 2026 via het Supabase Free-gebruiksscherm:

- Database: 0,5 GB inbegrepen; dit is een andere meter dan bestandsopslag.
- Bestandsopslag: 1 GB inbegrepen.
- Ongecachet verkeer: 5 GB per maand, apart van 5 GB gecachet verkeer.

De app blijft gratis en houdt reserves. Het providerdashboard is geen live API-meting in Paperlab. Een dashboardwaarde kan later worden bijgewerkt of een andere meetbasis gebruiken. De bestaande conservatieve verkeersraming wordt niet op basis van een screenshot teruggezet.

## Gemeenschappelijke grenzen (migratie 040)

| Meter | Waarschuwing | Nieuwe bronopslag remmen | Harde interne grens | Providerplan |
|---|---:|---:|---:|---:|
| Database | 350 MB | 400 MB | 450 MB | 500 MB |
| Private bestandsopslag | 600 MB | — | 800 MB | 1.000 MB |

De grenswaarden gebruiken decimale bytes en zijn dus voorzichtig tegenover eventuele binaire providerquota. Afgeronde/nieuwe modeltaken mogen tot de harde databasegrens door; nieuwe bronteksten tot 400 MB. Andere bestaande eigen deelbudgetten blijven bestaan. De gedeelde oude globale databasegrenzen van circa 97–300 MB zijn vervangen door de centrale opslagbewaking. Een bewust lager ingesteld maandmaximum blijft behouden. Financiële beleidsobjecten, handelsprofielen, posities, schedules en model-/verkeerstelstanden wijzigen niet.

De overlay vervangt alleen exact bekende databaseguard-uitdrukkingen, met aantallencontrole en hashes. PostgreSQL-functie-OIDs, ACLs, eigenaars en lokale settings blijven behouden. Bij opnieuw toepassen van oudere bronmigraties moet 040 **daarna** opnieuw worden uitgevoerd. De bekende installers doen dit. Per-studie tabelruimte, maandverkeer, invoeromvang en vastgelegde onderzoeksregels blijven begrensd.

## Drie opslagcompartimenten

1. **Actieve database:** actuele bronteksten, bronidentiteiten en hashes, onderzoekstaken, claims, rapporten, handelsbewijs en instellingen. PostgreSQL gebruikt al verliesloze TOAST-compressie voor grote teksten; geen samenvatting vervangt het bronbewijs.
2. **Historisch bronarchief:** alleen vervangen, inactieve documentversies mogen naar private Storage. De hele tekst en bronmetadata worden met gzip gecomprimeerd en met AES-256-GCM versleuteld. De worker downloadt het opgeslagen bestand opnieuw, ontsleutelt het, vergelijkt de volledige originele tekst en SHA-256, en geeft pas daarna de oude database-body vrij. IDs, bronhashes, URL, metadata, claims en werkhistoriek blijven in de database.
3. **Applicatieherstelkopieën:** de bestaande versleutelde snapshots blijven apart. Grote tekstcaches zitten niet in de gewone app-snapshot. De bronarchieven en hun sleutel zijn dus ook nodig voor volledig bronherstel. Dit blijft geen volledige Auth/provider-accountbackup.

Dit is verliesloze compressie: tabellen, voetnoten en formuleringen in de eerder geëxtraheerde tekst blijven exact bewaard. Het archief bevat de volledige **tekstextractie**, niet automatisch de oorspronkelijke PDF/HTML-binaire bestanden. Of de extractie zelf alle informatie uit afbeeldingen en tabellen bevatte, blijft een afzonderlijke kwaliteitsvraag.

## Automatisering en herstel

De bestaande dagelijkse opvolgfunctie voert voortaan eerst maximaal één archivering uit. Actieve of geleasede bronnen zijn uitgesloten. Bij ontbrekende sleutel, mislukte upload, download of integriteitscontrole blijft de originele tekst staan. Een afzonderlijke lease voorkomt dubbel archiveren. Er is een eigen conservatief archieftransferbudget van 100 MB per kalendermaand, naast het bestaande gezamenlijke verkeersbudget. Er worden geen archieven automatisch verwijderd.

- Installeren: `python scripts/storage_capacity.py kdyzlbknygeqinqduuic`.
- Archief controleren, zonder databasewijziging: `python scripts/restore_cold_source.py REF DOCUMENT_ID`.
- Exacte tekst terugplaatsen: dezelfde opdracht met `--restore`. Alleen een inactieve lege cache met overeenkomende bronidentiteit/hash wordt gevuld. Geen handelsreset en geen automatische activatie van een oude bron.

De private downloadroute blijft eigenaarlogin, MFA en een geldige sessie vereisen. De archiefsleutel en servicecredentials blijven serverzijde.

Een vrijgegeven tekst-body kan door PostgreSQL later als vrije ruimte worden hergebruikt. De fysieke databasebestanden worden daardoor niet noodzakelijk meteen kleiner. De app rapporteert daarom zowel de actuele databaseomvang als de afzonderlijke bestandsopslag; geen schijnbesparing door alleen bestanden te verplaatsen.

## Verificatie

Isolatietests controleren de 350/400/450 MB-grenzen, lagere aangepaste maxima, privacy, functie-ACL/OID-behoud, ongewijzigde verkeersmeters, uitsluiting van actieve/geleasede bronnen, en het behouden van originelen bij foutieve archieven. Verliesloze compressie wordt getest met Unicode, eurotekens en nieuwe regels. De productiecontrole herleest gecomprimeerde archieven en verifieert oorspronkelijke teksthashes.
