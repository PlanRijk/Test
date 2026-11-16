# Doorlopende gratis kwartaalramingen

Versie `quarterly-baseline-v1`. Dit vult de tienbedrijvenpilot aan met automatische
numerieke onderzoekskaarten voor de volledige bestaande catalogus van honderd bedrijven.
Geen nieuwe handelsstrategie, koopgoedkeuring, brokerkoppeling of taalmodel-API.

## Welke bedrijven krijgen een raming?

Iedere catalogusonderneming krijgt een status. Numerieke ramingen worden alleen getoond
wanneer een indicatieve koers in de laatste zeven dagen werkelijk is ontvangen en een
recente officiële onderzoeksbron is bevestigd. Koersen hoeven op een gesloten beurs niet
van dezelfde dag te zijn; dit is geen uitvoerbaar live-bod. De handelsmotor behoudt zijn
veel strengere afzonderlijke versheidscontrole van maximaal 120 seconden.

Een officiële bron betekent: bestaande opgehaalde rapportbronnen plus een bevestigde
publicatiecontrole of primaire bron in de laatste veertien dagen. Een publicatie-index
bewijst niet dat alle documenten inhoudelijk gelezen zijn. Een goede koersbron bewijst
geen goede inhoudelijke bedrijfsbeoordeling. Bedrijven zonder bron of ontvangen koers
blijven zichtbaar met `waiting_official_source` of `waiting_quote`.

## Reproduceerbare rekenregel, geen analistenconsensus

De collector leest gratis `quarterlyTotalRevenue`, `quarterlyNetIncome` en, waar aanwezig,
`quarterlyDilutedEPS` uit de bestaande Yahoo fundamentals-timeseries-bron. Alleen exact
dezelfde ticker, gerapporteerde 3M-perioden, einddatum niet in de toekomst en bekende
rapporteringsvaluta worden verwerkt. Maximaal vijf kwartalen per metriek. EPS wordt niet
uit nettowinst gedeeld door een oud jaarlijks aandelenaantal verzonnen.

De basis voor het volgende nog niet gerapporteerde referentiekwartaal is:

`waarde van hetzelfde kwartaal vorig jaar × (laatste kwartaal / dat kwartaal een jaar eerder)`

Vijf aaneengesloten kwartalen zijn vereist, met tussenpozen 65–115 dagen en een jaarafstand
330–400 dagen. Alleen positieve, eindige vergelijkingswaarden en dezelfde valuta. Bij
negatieve winst, omslagen, halfjaarcijfers of een jaarfactor buiten 0,2–3,0 blijft de
betreffende metriek onbekend. Laatste periode maximaal 160 dagen oud; invoerwaarneming
maximaal veertien dagen oud. Verouderde of ontbrekende invoer trekt de actuele raming in.

De lage/hoge scenario's zijn mechanisch ±20% rond de basis; bij een jaarfactor onder 0,5
of boven 1,5 geldt ±35%. Dit is een **vooraf gekozen illustratieve band**, niet een
gekalibreerd betrouwbaarheidsinterval of bewezen voorspelmodel. De referentieperiode kan
door aggregatornormalisatie afwijken van de echte fiscale kwartaalafsluiting. Gerapporteerde
EPS is niet onafhankelijk op GAAP/non-GAAP of splitbehandeling geverifieerd. Sectorale
bijzonderheden, eenmalige posten, wijzigingen in consolidatie, aankopen, verwatering en
nieuws kunnen de extrapolatie onbruikbaar maken. Geen intrinsieke waarde of koersprognose.

Bedrijfsprognoses (`company_guidance`), analistenconsensus en kwalitatieve beoordeling
blijven aparte velden: respectievelijk `not_verified`, `not_connected`, `not_automated`.
De rekenraming wordt nooit onder een van die namen gepresenteerd. Verwachte cijfers zijn
geen bewijs voor de koersreactie; `stock_direction=not_predicted`, `trade_approval=false`.

## Blijft draaien zonder open chat

`paper-quarterly-expectations` draait dagelijks om **07:20 UTC**, dus 08:20 Belgische
wintertijd en 09:20 zomertijd. Maximaal twintig vervallen dossiers per UTC-dag, vier
bedrijven gelijktijdig. Normaal ongeveer wekelijks vernieuwen; bevestigde cijfers binnen
21 dagen krijgen voorrang en dagelijkse controle. Nieuwe bronwijzigingen en voorheen
ontbrekende, nu ontvangen koersen kunnen eerder vernieuwing vragen. Een volledige eerste
netwerkronde kan meerdere dagen duren. Bij installatie worden alle beschikbare bestaande
waarnemingen al verwerkt; niet eerst dagen wachten op een lege registratie.

De officiële publicatiebewaking en bestaande financiële bronmonitor blijven afzonderlijk
lopen. Deze nieuwe routine haalt alleen kleine numerieke kwartaalreeksen op. Hij leest
of interpreteert niet automatisch nieuwe rapporttekst, nieuws of calls. De tienbedrijvenpilot
behoudt de inhoudelijke controletaken en eigenaarsvoorspellingen met hun bestaande deadlines.

Maximaal 100 kB brondata per bedrijf, acht seconden per verzoek en geen redirects.
Een conservatieve reservering van 250 kB per bedrijf omvat bron en transport; maximaal
120 MB per UTC-maand. Gedeelde verkeersgrenzen, 100 MB databasegrens en gratis providerquota
blijven gelden. Mislukte controles behouden hun reservering, zonder onbeperkte herpogingen.
Eigen budget of bronproblemen kunnen verwerking vertragen. Geen nieuw betaald abonnement.

## Bewaren en vergelijken

Actuele ramingen en maximaal vier versies per bedrijf blijven privé in Supabase. Elke
versie bevat vijf invoerpunten per bruikbare metriek, document-/invoerhash, bron-URL,
echte kennisdatum en de rekenmethode. Een bronfout blijft zichtbaar en wordt geen
optimistische vervanging. Opgeslagen bronverwijzingen bevatten geen API-sleutels.

Voor reeds bevestigde kwartaalcycli kan de eerste bruikbare mechanische raming vóór
publicatie minus 24 uur apart worden opgeslagen. Die kopie is onwijzigbaar; nieuwe cijfers
overschrijven haar niet. Zij heet expliciet `human_forecast=false` en
`cycle_match=unverified_reference_period`, omdat fiscale periodekoppeling nog verificatie
vraagt. Zij vult geen menselijke pilotvoorspelling in en wordt niet automatisch als een
juiste voorspelling beoordeeld. Kalender en eigen inhoudelijke voorspelling blijven apart.

## Beheer en herstel

`python scripts/quarterly_expectations.py REF` installeert SQL034, verwerkt de bestaande
honderd bronwaarnemingen en publiceert de begrensde worker. Hij voegt één dagelijkse job toe;
bestaande jobs en bevroren handelsprofielen worden op gelijkheid gecontroleerd. Geen
herstart van posities, balans, risico's of onderzoeksresultaten.

De bestaande eigenaar/MFA-API toont de extra gegevens via de vertrouwde onderzoekspagina.
Tabellen hebben RLS en zijn niet direct voor browser of service-role leesbaar. Configuratie
is privé; workerclaim/commit hebben leases en eenmalige opslag. De bedrijfsnamen en URL's
komen uit de bestaande gecontroleerde catalogus, niet uit anonieme input.

Herstelarchieven vanaf schema34 nemen actuele ramingen, historie en voorpublicatiekopieën
mee. Migraties t/m034 installeren vóór hervatten; de followup-installer herstelt034 als
laatste leesadapter. Oude archieven bevatten deze nieuwe tabellen niet. De bestaande
handelsmotor en eerdere forecasts worden niet met terugwerkende kracht aangepast.

Tests: deterministische waarden, ontbrekende EPS, toekomst-/ouderdomscontrole, halfjaarcijfers,
valutawijziging, negatieve/structurele breuken, bronidentiteit, eigenaar/RLS, begrensde en
herhaalbare verwerking, onwijzigbare eventkopie en desktop/mobiele weergave. Deze tests
bewijzen technische werking; voorspelkracht en winstgevendheid zijn nog niet aangetoond.
