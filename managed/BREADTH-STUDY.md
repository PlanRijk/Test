# Meer observaties met hetzelfde bevroren model

`breadth-study-v1` registreert naast de vaste twintig bevestigingswaarnemingen
alle overige geschikte bedrijf-dagvoorspellingen. Het historische model, zijn
exacte dataset, gewichten, codevingerafdruk en oorspronkelijke toetsgroep blijven
ongewijzigd. De aanvullende gegevens zijn verkennend. Ze zijn geen extra stemmen
in het bevestigingsvak, uitgevoerde referentietrades of brokerorders.

## Volledige dekking waar de data en budgetten dat toelaten

De bestaande dagroutine haalt al alle 150 aandelen en drie indices op. Deze nieuwe
worker doet geen markt- of nieuwsdownloads. Hij leest dezelfde opgeslagen bars,
historische tails, bestaande voorspellingen en bevroren kosten. Alleen bedrijven
binnen het model met geldige, voldoende recente data, gedateerde FX en bekende
invoertijden krijgen een voorspelling. Ontbrekende of toekomstige brondata en
te veel uitschieters worden afzonderlijk geteld. Er worden geen scores verzonnen.

Model/bedrijf/datum is uniek. De twintig reeds vastgelegde referentiegevallen van
die datum worden overgeslagen. De routine wacht tot de referentieronde is voltooid;
een latere referentieronde kan zo geen dubbele gevallen toevoegen. Ook lage
voorspelde kansen krijgen een compact dossier. Selectie gebeurt niet op winst.

Bij het huidige model met 147 ondersteunde bedrijven en voldoende dekking zijn dat
doorgaans maximaal 127 extra gevallen per werkdag, naast de twintig vaste gevallen.
Twintig sessies volgen betekent ongeveer 2.540 extra lopende gevallen plus wachtende
instappen. De capaciteit is 5.000 actieve gevallen. Alle compacte gevallen krijgen
dezelfde hypothetische instap en twintig-sessie-uitkomst, inclusief ontbrekende
uitkomsten, oorspronkelijke EUR-kosten en het vaste Belgische belastingscenario.
Geen achteraf ingevulde instap of gunstig gekozen verkoopdag.

## Compacte gegevens en volledige invoer

Getypeerde kolommen bewaren datum/tijd, bedrijf, sector, beurs, acht kenmerken en
de modelkans. Kostengegevens staan in vaste double-arrays in plaats van duizenden
herhaalde JSON-sleutels. Leescodec van actieve records:

`[symbol, decision_day, decision_ms, known_day, probability, features[8], status, entry, outcome, reason]`

Status 0 wacht op instap, 1 volgt, 2 afgerond, 3 ontbrekend. Entrycodec:

`[open_ms, known_ms, day_ms, close_local, fx, fx_day_ms, price_eur, qty, gross_eur, commission_eur, buy_costs_eur, budget_eur]`

Uitkomstcodec:

`[1, day_ms, known_ms, close_local, fx, fx_day_ms, net_eur, stressed_net_eur, gross_move_pct, exit_costs_eur]`

`[2]` betekent ontbrekend, met een afzonderlijke reden. Bedrag per geval is EUR100.
Kosten en uitkomsten zijn geen optelbare eindige-kapitaalportefeuille. De evaluator
gebruikt dezelfde bronkalender als de vaste dagroute. SQL controleert dat de instap
uit de eerste latere sessie komt en de uitkomst exact twintig bronsessies later ligt.
Een vastgelegde kans, invoer, instap of uitkomst wordt niet herschreven.

Maximaal veertig aanvullende gevallen per werkdag krijgen een uitgebreid
invoerdossier. Een vaste hash van model/bedrijf/datum en spreiding over sectoren
bepalen die subset, onafhankelijk van modelkans en toekomstige uitkomsten.
Die dossiers bevatten de 21 oorspronkelijke aandelenmetingen, zes metingen per
index, bekende invoertijden en relevante historische bronhashes. Ze zijn een subset
van de compacte registratie. Ze worden dus niet als extra onafhankelijke gevallen
geteld. De vaste twintig referentiedossiers blijven daarnaast beschikbaar.

## Gratis budgetten en bewaring

Maximaal 50.000 compacte gevallen. Afgeronde of ontbrekende gevallen blijven
365 dagen. Uitgebreide invoer blijft maximaal 90 dagen en 3.500 dossiers. Kleine
dagtellingen blijven twee jaar. Originele referentiedossiers en historische
trainingsgegevens worden niet door dit onderhoud gewist.

Toelatingsbudget: 32 MB begrote levende gegevens, inclusief geraamde indexruimte
en reservering voor nog te vullen uitkomsten. Fysieke pagina's kunnen na opruimen
worden hergebruikt. Vanaf 24 MB begrote gegevens of 1,2 GB geraamd maandverkeer
daalt nieuwe toelating naar maximaal 75 gevallen en stoppen nieuwe uitgebreide
dossiers. Vanaf 32 MB, 150 MB totale database of 1,5 GB maandverkeer worden alleen
bestaande gevallen afgewerkt. Harde bescherming: 40 MB fysieke eigen tabellen,
180 MB totale database of 1,8 GB maandverkeer. Alle bedragen betreffen de gedeelde
toepassingsteller waar aangegeven; er wordt geen betaald plan ingeschakeld.

De toepassing toont een waarschuwing vanaf 70% van de relevante toelatingsmarges.
Providergebruik door andere projecten en interactieve browserverzoeken zijn niet
volledig in de schatting opgenomen. Dit is een conservatieve toepassingsteller,
geen volledige facturatiemeting. Toestemming voor betaalde uitbreidingen wordt
hiermee niet verleend of verondersteld.

Meer bedrijf-daggevallen verbeteren spreiding. Overlappende twintigdaagse
waarnemingen en dezelfde marktschokken zijn afhankelijk. De vaste zestig nieuwe
toetsdagen, onafhankelijke beoordeling en historische tekortkomingen veranderen
niet. Verkennende gemiddelden zijn geen bewezen extra handelsvoordeel.

## Werking, privacy en oplevering

Cron om 06:25 UTC, met een tweede poging om 06:40 als de eerste niet opgeslagen is.
Eén geslaagde ronde per UTC-datum; nieuwe gevallen uitsluitend op weekdagen.
Weekendrondes kunnen bestaande vrijdaggevallen afwerken. Eigenaar kan de extra
registratie pauzeren; pauzeren maakt een lopende lease ongeldig. Hervatten vult
gemiste sessies niet kunstmatig in.

Privéschema met RLS en uitsluitend server-RPC's. Alle lees-, export- en
pauzeerbediening loopt via de bestaande eigenaar/AAL2/sessiecontrole. Compacte
CSV maximaal 500 gevallen; uitgebreide export maximaal veertig dossiers. Geen
API-sleutels in de browser. Nieuwe routine doet geen betaalde API-aanroepen.

Installatie: eigen codevingerafdruk genereren, uitsluitend migratie 008,
`paper-api` en `paper-breadth` deployen, daarna `breadth-enable`. Bestaande
historische profielen, model of brondata niet opnieuw initialiseren.

Verificatie: pure tests voor brede dekking, codecrondgang, timing, vaste selectie,
budgetreductie en niet-muteren; lokale SQL-test voor 50.000 gesloten gevallen,
vaste invoer en sessiehorizon, toegang, retentie, pauze en ongewijzigde referentie;
browsercontrole met synthetische MFA op werkelijke gepubliceerde assets.
