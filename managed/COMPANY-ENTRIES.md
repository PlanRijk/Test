# Vijf bedrijfspijlers en instaproutes

Vanaf 10 november 2026 geldt een afzonderlijke, versiegebonden instapfilter voor
nieuwe aankopen in de actieve €10.000-paperrekening. Alle honderd bedrijven vallen
onder de voorwaarde. Geen volledig actueel bewijs betekent geen nieuwe aankoop.
Dit is een voorlopige onderzoeksstrategie, geen bewezen rendementsverbetering.

De financiële uitvoering, kosten, Belgische proefreserves, kas-/sectorlimieten en
beschermende verkopen gebruiken de bestaande functies. Nieuwe broninformatie is
geen aanleiding om bestaande verliezen, risicostops of kasboeken te resetten.
SQL017 bewaart bij overgang de beginwaardering, overgenomen posities en geannuleerde
oude kooporders. De oude fase is geen onafhankelijke vergelijking met een nieuwe
lege portefeuille. De vaste €500-referentie en bestaande onderzoeken houden hun
bevroren regels; nieuwe actieve aankopen krijgen een aparte company_profile.

## Bronnen en criteria

Een SEC companyfacts-dossier wordt aan CIK, ticker, valuta, gedateerde publicatie,
accession en vergelijkbare verslagperioden gekoppeld. Toekomstige rapporten tellen
niet mee. Jaarvergelijkingen gebruiken dezelfde filing. Broninhoud krijgt hashes;
we bewaren een compacte financiële momentopname en rapportlinks, geen onbeperkt
archief van alle gedownloade jaarverslagen.

1. Omzet: niet-negatieve jaar- en laatste vergelijkbare periodegroei.
2. Winst: positieve jaarwinst, operationele kasstroom en kasstroom na materiële investeringen.
3. Waardering: actuele koers × gerapporteerde aandelen / jaarwinst maximaal 35;
   dezelfde verhouding tegenover vrije kasstroom maximaal 40. Dit zijn vaste
   voorlopige screens, geen intrinsieke waarde, groeiprognose of consensus.
4. Concurrentiepositie: expliciete, gedateerde beoordeling met primaire bron en
   onderbouwing; een bekende merknaam of getal geldt niet automatisch als moat.
5. Risico: actuele onderbouwde beoordeling van schuld, verwatering, geopolitiek en
   technologie; geen kritieke/onzekere thesevlag. Netto-schuld/vrije kasstroom
   maximaal 4 en toename verwaterde aandelen maximaal 5%. Ontbrekende schuld wordt
   niet nul. Een onderbouwde balansbeoordeling kan een conservatief schuldentotaal
   aanleveren, inclusief latere emissies en zonder veronderstelde aflossingen.

Het verslag mag maximaal 145 dagen oud zijn, de jaarinformatie 460 dagen;
broncontrole maximaal acht dagen en kwalitatieve beoordeling zeven dagen.
Een nieuw niet-beoordeeld materieel SEC-document blokkeert risico-goedkeuring.
Banken/vastgoed worden niet met generieke kasstroomcriteria goedgekeurd; zij vragen
nog sectorspecifieke profielen. De huidige automatische SEC/US-GAAP-koppeling is
niet voor alle Europese/IFRS- of buitenlandse ADR-noteringen geschikt.

## Instap na vijf akkoord bevonden pijlers

- Kwaliteitsmomentum: meer dan +0,2% tegenover vijf eerdere vijfminutenmetingen.
- Cijfermomentum: beoordeelde publicatie binnen zeven kalenderdagen, positief
  dag- en kortetermijnmomentum. Geen verzonnen winstverrassing tegenover consensus.
- Herstel na slecht nieuws: minstens 5% onder de hoogste van twintig bekende
  slotkoersen, expliciet beoordeelde tijdelijke oorzaak, minstens 0,3% herstel
  over zes metingen, laatste koers boven de voorgaande en die minstens gelijk aan
  haar voorganger. Onzekere/structureel schadelijke oorzaak blijft geblokkeerd.

Alle routes vragen twintig bruikbare referentiesloten. Bedrijfsacties in het
opgehaalde venster vereisen eerst beoordeling. Deze thresholds zijn vooraf
vastgezet en niet geoptimaliseerd op onze korte rekeningresultaten. Een daling
is een onderzoekskandidaat, geen automatische onderwaardering.

Nieuwe kooporders worden opnieuw getoetst bij uitvoering. Beslisbewijs bevat
vijf pijlers, financiële momentopname, bronlinks, dossier-/review-ID, actuele
waarderingsverhoudingen en instaproute; uitvoering bewaart haar eigen controle.
Het SQL-kasboek weigert ontbrekende/onjuiste pijlerbewijzen en blijft financiële
conservering en tijd-/revisiecontroles toepassen.

## Gratis en begrensd

De bestaande vijfminutencron gebruikt paper-tick-company. Geen extra koersbatch
voor de handel. Per ronde gaan maximaal twintig actuele beoordeelde dossiers mee,
met voorrang voor pending orders en recente positieve bewegingen. Grotere of te
dure payloads blokkeren nieuwe instap; beschermende verkopen blijven mogelijk.

Eén nieuwe broncron, 06:05 en 08:05 UTC op weekdagen, maximaal twee dossiers per dag.
Collectie vraagt companyfacts, recente SEC-meldingen en een klein dagelijks
koersvenster. Maximaal 8 MB gedecodeerde brondata per poging, vooraf 8,5 MB gereserveerd.
Eigen bron-/transportbegroting 60 MB per maand; eigen opslag 8 MB. Gedeelde pauze
vanaf 100 MB database of 1,0 GB geraamd maandverkeer. Een mislukte collectie houdt
haar conservatieve reservering en vervangt het actuele dossier door onbekend.
Dat kan de dekking beperken; er volgt geen betaalde uitbreiding.

Per bedrijf blijven maximaal twee dossiers en twee beoordelingen beschikbaar.
Aankoopbewijzen behouden de relevante beslismomentopname. Kwalitatieve goedkeuring
kan alleen via beheer, niet vanuit een browseractie of de automatische collector.
De collector is geen zelfstandig lezende nieuwsanalist. Er is geen volledige
realtime nieuwsfeed, winstkalender of analistenconsensus aangesloten.

## Eerste toepassing

Apple en Microsoft: financiële gegevens uit actuele SEC-rapporten, kwalitatieve
beoordeling uit jaar-/kwartaalrapporten en de nieuwste 8-K's. De 7,5 miljard USD
Apple-obligaties van 9 november en de 25 miljard USD Microsoft-obligaties van
4 november worden conservatief bij de gerapporteerde schuld opgeteld. Geen tijdelijke
slechte-nieuwskoop is verzonnen uit deze meldingen. Bij de eerste laatst opgeslagen
koersen blokkeren respectievelijk jaar-K/W en koers/vrije kasstroom de aankoop.
Andere bedrijven blijven geblokkeerd zolang hun bewijs niet volledig is.

Lokale controles: company-entry.test.mjs, companies-ui.test.mjs en
 test_company_database.py; deze testen bronidentiteit, datums, ontbrekende pijlers,
waardering, nieuwsherstel, later opnieuw toetsen, behoud van beschermende verkopen,
kasboekconservering, privacy, leases en begrotingen. Browsercontroles gebruiken
synthetische authenticatie en afgevangen API's; geen echte orders.

## Werkelijk bronbereik bij activatie

De eerste twee budgetgebonden bronrondes in Supabase gaven SEC HTTP 403. De
gerichte diagnose bevestigt dat de weigering bij SEC companyfacts optreedt; de
handler ontving wel zijn eigen cron-autorisatie. De automatische broncron is daarom
gepauzeerd, zonder de actieve koopfilter of beschermende verkopen te pauzeren.
De eerste twee dossiers zijn via de cloudwerkruimte uit dezelfde officiële
bronnen gevalideerd en compact ingevoerd. Dit levert geen autonome volledige
nieuwsdekking op. De twee mislukte reserveringen blijven conservatief geteld; ze
zijn geraamd verkeer, geen 17 MB extra opgeslagen bedrijfsdocumenten.

Hervat de broncron pas na een aangetoonde werkende officiële bronverbinding. Geen
netwerkbeperking omzeilen, bronweigering als succes tonen of dagbudget resetten.
