# Historische training combineren met nieuwe papercontrole

Protocol `historical-day-v1` staat los van de oorspronkelijke intradaylearner,
de brede 30/120-minutenstudie en de vaste 1/5/20-dagenstudie. Hun bestaande
trainingslabels, handelsregels en verzegelde toetsvakken blijven intact.
Historische voorbeelden heten `historically_simulated`, nieuwe modelwaarnemingen
`prospective_hypothetical`. Geen van beide is een uitgevoerde referentietrade.

## Gegevens en kosten

Bronnen: Yahoo Finance vanaf 2007-01-01 voor 150 aandelen en drie prijsindices;
ECB gedateerde USD/GBP/CHF/SEK/DKK/NOK-referenties. Geen huidige wisselkoers op oude
prijzen toepassen. Koersdata, volumes, splitsings- en dividendmeldingen worden bij
import bevroren met bronhash en canonieke datasethash. Niet alle bedrijven hebben
historie tot 2007. Ontbrekende bronnen en ongeschikte voorbeelden blijven zichtbaar.

De huidige bedrijvenlijst veroorzaakt survivorship/selectiebias. Yahoo kan oude
prijzen achteraf aanpassen en voor latere splitsingen corrigeren. Dit is geen
gecertificeerd point-in-timearchief of volledige marktpopulatie inclusief failliete
bedrijven. Uitkomsten tonen wat het vaste scenario op de beschikbare geschiedenis
doet; ze bewijzen geen destijds uitvoerbare strategie.

De eerste bar per bedrijf per beursweek vormt een kandidaat. Labelonafhankelijke,
deterministische hashselectie kiest maximaal 48 kandidaten per bedrijf, maximaal
8.000 totaal. De kenmerken gebruiken uitsluitend 21 bekende bars en bekende
indexstanden: 1/5/20-daags rendement, 20-daagse volatiliteit, relatief volume,
vijfdaagse beweging S&P 500/EURO STOXX 50/BEL 20.

Het gesimuleerde besluit ligt de volgende ochtend 06:20 UTC. Instap gebruikt een
latere sessie-opening als tijdscontrole en de slotprijs van die sessie als
hypothetische uitvoer. Uitstap is de slotprijs twintig volgende bronsessies later.
De actuele kosten/TOB/10%-meerwaardereserve worden als bevroren 2026-scenario op
historische prijzen toegepast: geen reconstructie van werkelijk verschuldigde
belasting in 2007. Prijsnadeel 10 bp per zijde; extra stress verdubbelt beide
commissies en voegt nog 10 bp per zijde toe. Dividendontvangsten krijgen nul netto
krediet, een conservatieve prijsstudie. Geen totaalrendement of persoonlijke
belastingaangifte. Splitsingsvensters, sprongen boven 30%, ontbrekende FX en
oncontroleerbare per-share ADR-kosten van TSM/TM worden uitgesloten met reden. Een herstel vóór modelvorming mag afgeleide
voorbeelden opnieuw berekenen; oorspronkelijke bronnen, hashes en datagrens blijven
intact. Zodra een model bestaat, blokkeert een profielwijziging automatisch.

## Model en controles

Eén vooraf vastgelegde L2-logistische classifier, acht kenmerken, honderd vaste
optimalisatiestappen, grens 0,60, geen parameterzoektocht. Minimaal 1.500 bruikbare
voorbeelden, 250 besluitdatums, 40 bedrijven, acht sectoren; minstens 800 training,
150 validatie, 150 test en dertig voorbeelden per klasse in elk vak. Tijdsplitsing
60/20/20 op besluitdatums. Voorbeelden waarvan de uitkomst bij het volgende vak
beschikbaar komt, worden uit het eerdere vak verwijderd. Normering gebruikt alleen
training. Dataset, bronmanifest, modelgewichten en codevingerafdruk blijven bewaard.
Een codewijziging die niet bij het bevroren profiel past, blokkeert de worker.

Brier/logloss tegenover vaste trainingsprior, nettoresultaat bij hogere kosten,
voldoende geselecteerde toetsvoorbeelden, 80% bruikbare kandidaatdekking en
weekblokken van vijf/tien weken bepalen de historische onderzoekstoets. Deze
selectiediagnose is geen eindige-kapitaalportefeuille of automatisch kooprecht.
Ook bij onvoldoende historisch voordeel blijft een getraind model herkenbaar als
diagnostisch model; het wordt nooit als bewezen winnaar weergegeven.

## Prospectief volgen

Dagelijks 06:20 UTC, na de bestaande dagkoersenroutine. Maximaal twintig nieuwe
controlewaarnemingen op weekdagen, gekozen zonder toekomstige labels en gespreid
over sectoren. Alle krijgen een bevroren voorspelling, ook bij lage kans. Instap
vereist de eerste werkelijke toekomstige sessie uit de volledige bronkalender.
Een gemiste sessie of ontbrekende FX krijgt geen achteraf bedachte uitvoering.
De kalender komt uit de 3-maandenbron, niet uitsluitend uit opgeslagen dagen;
uitval mag niet stilzwijgend twintig sessies in een langere horizon veranderen.
Oude normering/gewichten veranderen niet op basis van nieuwe uitkomsten.

De eerste zestig volledig afgeronde nieuwe besluitdagen vormen één vaste toets,
met minimaal 300 uitkomsten, tien bedrijven, vijf sectoren, 90% dekking, positieve
nettoresultaten en kalibratieverbetering. Afhankelijkheid door de twintigdaagse
looptijd wordt getoetst met blokken van twintig/veertig besluitdagen. Een vroege
onvoltooide dag wordt niet vervangen door een latere gunstige dag. De eerste
beoordeling wordt één keer bevroren. Geen automatische wijziging van de hoofdproef,
ook niet bij gunstige uitkomst: uitvoering, eindig kapitaal, overlevingsbias en
brokerkosten vereisen afzonderlijk bewijs. Nieuwe controlewaarnemingen kunnen
nadien beschikbaar blijven voor vervolgonderzoek.

## Andere partijen

SEC: beperkte, roterende bedrijfs- en bestuurdersmeldingen plus Berkshire 13F.
Publicatietijd en werkelijke broncontrole worden opgeslagen. Form 4 is niet
automatisch een aankoop, 13F betreft vertraagde posities zonder exacte transacties.
Documentmetadata is context; er wordt geen semantisch nieuwsmodel of historische
koopmotivatie gefingeerd. Later bekende meldingen worden geen oude modelkenmerken.

Optionele adapters voor Alpaca Basic/IEX en Alpha Vantage zijn uitsluitend
prijscontroles. Ze maken geen accounts of abonnementen aan. Persoonlijke
`ALPACA_API_KEY`, `ALPACA_API_SECRET` en `ALPHAVANTAGE_API_KEY` ontbreken standaard;
de interface meldt dat expliciet. Zonder sleutels gaat geen verzoek naar die API's.
Andere feeds/venues zijn geen dubbele onafhankelijke trainingsvoorbeelden.
403/404 of een bronlimiet worden gemeld, niet omzeild. Volledige historische
Europese transactietapes en individuele beleggersresultaten worden niet beloofd.

## Gratis en privé

Ophalen in batches van maximaal vijftien instrumenten/vier parallelle aanvragen.
Eén bevroren bronimport; geen herhaalde download van twintig jaar per dag. Afgeleide
voorbeelden worden pas na volledige bronimport in aparte batches berekend, zodat de gratis Edge-worker niet alle
historie opnieuw hoeft te verwerken. Maximaal veertien bronclaims en veertien rekenclaims per UTC-datum;
maximaal één prospectieve ronde per datum. Bootstrapcron stopt met HTTP-aanvragen
zodra het model bestaat of de daggrens is bereikt. Normale cron blijft dagelijks.
Geen betaalde planwijziging, volumes, domeinen, SMS of AI-aanroepen.

Historie, model en toekomstige dossiers pauzeren bij 64 MB eigen tabellen,
180 MB totale database of 2 GB geraamd maandverkeer. Maximaal 500 actieve en
10.000 toekomstige dossiers; voltooide dossiers maximaal 730 dagen en pas na de
vaste beoordeling opruimbaar. Gratis providerquota kunnen ook door andere projecten
worden gebruikt; toepassingstellingen zijn geen volledige facturatiemeting.
Schema is privé met RLS, RPC's uitsluitend voor de server, lees-/exportpaden via
bestaande eigenaar- en AAL2-sessiecontrole. Geen beheersleutels in de browser.

Installatie zonder import/reset: codevingerafdruk genereren, migratie 007,
`paper-api`, `paper-daily`, `paper-history` deployen en `history-enable` uitvoeren.
Daarna begrensde bootstrap rondes volgen tot model en eerste vooruitblik zijn
vastgelegd. Live tests gebruiken echte bronnen; synthetische trainingsfixtures
gaan uitsluitend naar de geïsoleerde lokale testdatabase.
