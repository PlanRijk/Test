# Gratis kwartaalpilot — tien bedrijven

Versie `earnings-pilot-v1`, gestart 12 november 2026. Onderzoeksvoorbereiding en
prospectieve voorspellingen; **geen nieuwe handelsroute** en geen betaalde modelaanvragen.
De bestaande paperstrategie, posities, stops en risicolimieten blijven ongewijzigd.

## Selectie en beschikbare informatie

Apple, Microsoft, Nvidia, Amazon, Alphabet, Meta, Walmart, Costco, Visa, Mastercard.
Selectie op reeds opgehaalde officiële rapporttekst en toegankelijke beleggerspagina's,
niet op geclaimd koersvoordeel. Ieder dossier verwijst naar minstens drie bestaande,
gedateerde bronnen met echte documenthashes. Bronteksten blijven in het bestaande private
onderzoeksarchief. De startcontext gebruikt de bestaande financiële bronkaarten en is geen
volledige nieuwe kwalitatieve kwartaalbeoordeling. Open hiaten blijven expliciet zichtbaar.

Twee volgende publicaties zijn op officiële bronnen bevestigd:

- Nvidia FY2027 Q3: 17 november 2026, publicatie circa 22:20 Belgische tijd,
  call 23:00. [Officiële aankondiging](https://investor.nvidia.com/news/press-release-details/2026/NVIDIA-Sets-Conference-Call-for-Third-Quarter-Financial-Results/default.aspx).
- Walmart FY2027 Q3: 19 november 2026, publicatie circa 13:00 Belgische tijd,
  call 14:00. [Officiële evenementpagina](https://corporate.walmart.com/news/events/fy2027-q3-earnings-release).

De volgende datums van de overige acht bedrijven zijn bij installatie niet officieel
bevestigd in dit project. Er worden geen geschatte datums als bevestigd ingevoerd.
Bereikbare kalenderpagina's bewijzen geen volgende publicatiedatum. Kalenderwijzigingen
worden gemeld voor inhoudelijke bevestiging; de monitor bevestigt geen datum zelfstandig.

## Voorbereide controles

Elke cyclus krijgt acht blijvende taken: eerste dossiercontrole; voorbereiding 21 dagen
vooraf; herbeoordeling zeven dagen vooraf; laatste onderzoek twee dagen vooraf; definitieve
voorspelling uiterlijk 24 uur voor publicatie; cijfers/vooruitzichten een dag achteraf;
call en tegenargumenten zeven dagen achteraf; koersopvolging rond 28 kalenderdagen achteraf.
Voorbereiding en opvolging krijgen 08:05 Belgische tijd op de betreffende kalenderdag;
de bevriezingsgrens is exact 24 uur vóór de geregistreerde publicatietijd. Weekenden worden
niet overgeslagen. Verstreken voorbereidingsmomenten vóór start heten `missed_before_pilot`.
Een nieuwe startcontrole vervangt geen gemiste historische voorspelling.

Taken zonder bevestigde datum blijven `awaiting_date`; eerste dossiercontrole en
kalenderopvolging werken wel. Een gemiste deadline produceert geen voorspelling achteraf.
Notities kunnen via de website met bron en echt opslagtijdstip worden afgerond. De
bronnenmonitor voltooit nooit een inhoudelijke taak en wekt geen menselijk contact op.

## Automatische bronbewaking, geen automatisch taalmodel

Een aparte beschermde Edge Function gebruikt de bestaande Supabase/cron-infrastructuur.
De scheduler controleert dagelijks om **07:05 UTC** of werk vervalt: 08:05 Belgische
wintertijd en 09:05 zomertijd. Per bedrijf normaal wekelijks metadata ophalen; vanaf
21 dagen vóór tot zeven dagen na bevestigde cijfers een beperkte dagelijkse broncontrole.
Dit is geen dagelijkse volledige bedrijfsanalyse. Uitgebreide rapporten/calls beoordelen
we in werksessies. Er worden geen berichten of mails naar anderen gestuurd.

Elke controle leest de officiële kalenderpagina en de bestaande SEC-publicatie-index:
maximaal 400 kB per pagina, vier gelijktijdige bedrijven, maximaal tien per ronde.
Redirects worden geweigerd; vooraf gecontroleerde canonieke adressen zijn opgeslagen.
Fouten, blokkades en te grote bronnen blijven zichtbaar als onbeschikbaar/gedeeltelijk.
Alleen hashes, verwijzingen en controlemetadata worden opgeslagen, niet onbeperkt HTML.

Na publicatie kan dezelfde controle een begrensde Yahoo-dagreeks ophalen voor 1, 5 en
20 daadwerkelijk waargenomen afgesloten sessies. Alleen USD en bevestigde tickeridentiteit;
een split blokkeert de beoordeling tot controle. Basis is het laatste slot vóór publicatie,
met beursafsluiting om 16:00 New York. Bij nabeurspublicatie kan dat het slot van dezelfde
dag zijn; bij voorbeurspublicatie het eerdere slot. Onvolledige huidige sessie uitgesloten.
Koersrichting gebruikt een vooraf vastgelegde neutrale band van −0,5% tot +0,5%; eerste
sessie is de primaire uitkomst, 5/20 sessies aanvullend. Zonder bevroren voorspelling geen
richtingsoordeel. Koersrendement sluit kosten en dividenden uit en is **geen handelswinst**.
Geen gegarandeerde dagelijkse feed/SLA; ontbrekende koersen worden niet ingevuld.

De monitor reserveert conservatief 1,8 MB per bedrijf per controle, zonder terugbetaling
bij mislukking; maximum 160 MB per UTC-maand. Gedeelde verkeers-, database- en
providergrenzen blijven gelden. Budgetuitputting stopt alleen deze pilotcontrole.
Geen nieuw betaald model, abonnement of hostingplan. Bestaande gratis quota blijven een
voorwaarde; absoluut onbeperkt gratis verbruik wordt niet beloofd.

## Voorspelling en resultaat

Het eigenaarsformulier legt omzet (miljoen USD), EPS (USD/aandeel, GAAP of non-GAAP),
pessimistisch/basis/optimistisch scenario, koersrichting of onthouding, onderbouwing,
tegenargumenten en een bekende officiële bron vast. Server controleert eigenaar,
bronidentiteit, getaltypen, scenariovolgorde, datum en deadline. Definitieve voorspellingen
zijn onwijzigbaar. De huidige koopgoedkeuring kan hiermee niet geschreven worden.

Geen aangesloten consensusfeed: `consensus=unknown` wordt door de server afgedwongen.
Eigen verwachting, bedrijfsprognose en analistenconsensus zijn verschillende begrippen.
Een EPS-resultaat op een andere boekhoudkundige basis wordt niet als raak/mis geteld.

Werkelijke cijfers en inhoudelijke beoordeling van de vooruitzichten en call worden
na publicatie apart geregistreerd via de bestaande eigenaar/MFA-API-actie
`earnings-actual` (RPC `paper_earnings_actual`), of in een beheerde werksessie met
dezelfde validatie. Bron-URL en echte documenthash zijn verplicht. Er is geen automatische
rapportinterpretatie of gegarandeerd gratis transcript. De pilot berekent daarna de
ligging binnen onze vooraf vastgelegde ranges; zonder consensus geen consensussurprise.
De volgende kwartaalcyclus registreren we met officiële bron via de private beheerfunctie
`paper_earnings_event_save`; bestaande bevroren kalender niet stilzwijgend wijzigen.

## Installatie, beveiliging en herstel

`python scripts/earnings_pilot.py REF` installeert SQL033, de tien brononderbouwde dossiers,
80 taken en `paper-earnings-pilot`. Hij voegt één begrensde metadatajob toe zonder
bestaande jobs of bevroren handelsprofielen aan te passen. De API blijft achter bestaande
eigenaarslogin en MFA. Databasetabellen privé/RLS; configuratie- en kalenderbeheer zijn
niet voor browser of service-role beschikbaar. De afzonderlijke worker gebruikt alleen
de bestaande cronsecret en geen model- of brokersleutel.

Schema33-herstelkopieën bevatten pilotconfiguratie, voorspellingen en taken. Een oudere
herstelkopie bevat deze pilot niet. Migraties t/m033 na herstel installeren vóór hervatting;
de followup-installer herstelt033 na oudere leesadapters. Nooit bestaande forecasts of
resultaten resetten om opnieuw te testen. De tien dossierkeuzes en startdatums staan
blijvend in GitHub; individuele voorspellingen blijven privé in Supabase.

Validatie: Node bron-/prijs-/authproeven, bestaande suite, geïsoleerde PostgreSQL-tests
voor planning, eigenaar, deadlines, onwijzigbaarheid, getal-/bronvalidatie, vergelijkbaarheid
en koerssessies; Chromium-formulierproef op desktop/mobiel. Geen rendementbewijs.
