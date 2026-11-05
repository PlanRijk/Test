# Afzonderlijke doorlopende kandidaattoetsen

Twee vooraf vastgelegde kandidaatmodellen worden buiten de hoofdportefeuille vergeleken met het bevroren historische dagmodel. `paper-learn` voert de kandidaatroute eerst en onafhankelijk van de bestaande intradayopleiding uit. De bestaande planning van 06:45/22:45 UTC op weekdagen blijft behouden; er zijn geen nieuwe cronjobs, marktbronnen, brokerkoppelingen of betaalde diensten. Bij een afzonderlijke kandidaatfout kan de intradaycontrole doorgaan.

## Training en versies

De database stuurt uitsluitend het oorspronkelijke **trainingsvak** uit de bevroren historische dataset door: besluit en volledig beschikbare uitkomst moeten vóór de oorspronkelijke validatiegrens liggen. De oude validatie- en testvakken komen niet in de opleidingsinvoer. Normalisatie gebruikt alleen deze trainingsvoorbeelden.

Er is één begrensde opleiding, geen continue parameterzoektocht: 100 vaste epochs, stap 0,08, drempel 0,60, twee logistieke varianten. `shrinkage` gebruikt alle acht vaste dagkenmerken met L2=0,1. `context` gebruikt volatiliteit en de drie indexbewegingen met L2=0,01. Dit zijn kandidaten, zonder historische of actuele winstgoedkeuring. Alle bronbeperkingen van de historische dataset blijven gelden, waaronder de huidige bedrijvenselectie, ontbrekende dividendontvangsten en het conservatieve kostenmodel.

Beide modellen krijgen een vaste ID en integriteitshash; gewichten, maskers en normalisatie veranderen niet gedurende de vergelijking. De nieuwe policy heeft een implementatiefingerprint. `python scripts/candidate_study.py configure PROJECT_REF` installeert uitsluitend deze uitbreiding en legt de policy vast; hij importeert/reset geen rekening. Een gewijzigde policy wordt bij een bestaande vergelijking geweigerd. De oorspronkelijke dagmodel-, brede registratie- en intradayregels blijven intact.

## Gedeelde toekomstige gevallen

Na de opleidingsdag legt de ochtendronde twee extra kansen vast bij nieuwe, reeds geregistreerde kern-/brede waarnemingen. Alleen op weekdagen vóór **07:00 UTC**, vóór de toekomstige instap, op reeds bekende kenmerken. De algemene bronkoers-/FX-controles en geschiktheidsselectie komen van de bestaande dagroute. Dit is geen willekeurige steekproef van de hele markt.

Eén databasegeval bevat twee kandidaatkansen en de bestaande referentiekans. Dat verdubbelt het aantal onafhankelijke voorbeelden niet. Er worden geen aanvullende koersen gedownload. De bestaande twintig-sessiewaarneming levert dezelfde instap, kosten, FX en uitkomst. Een gewijzigd invoerhash, te vroege instap, ontbrekende of nog onbekende toekomstige uitkomst kan niet als geslaagde voorspelling worden geboekt. Maximaal 55 kalenderdagen zonder uitkomst wordt als ontbrekend geregistreerd.

Dit zijn onafhankelijke hypothetische EUR100-gevallen; de werkelijke portefeuille, vermogenslimieten en koersrisico's worden hiermee niet nagebootst. Geen echte orders, extra intradayreferentietrades of automatische modelpromotie.

## Beschrijvende updates en één vaste eindtoets

Dagelijkse tussenstanden zijn beschrijvend. Nul uitkomsten betekent **nog niet meetbaar**. Het primaire vak bestaat uit de eerste zestig geregistreerde besluitdagen; alle gevallen op die dagen moeten gesloten/ontbrekend zijn voor één vaste eindtoets. Minstens 300 gemeten gevallen, 100 geselecteerde gevallen per kandidaat, tien bedrijven, vijf sectoren, dertig positieve en dertig niet-positieve uitkomsten, en minimaal 90% dekking zijn vereist. Ontbrekende gevallen blokkeren een automatische positieve onderzoeksconclusie en vereisen beoordeling.

Netto- en gestreste uitkomsten omvatten dezelfde kosten en voorlopige belastingreserves. De vergelijking koppelt kandidaatkansen en referentiekansen aan dezelfde gevallen. Brier meet kanskwaliteit; de daggemiddelde gestreste selectievergelijking is een onderzoeksmaat, geen portefeuillewinst of blootstellingscorrectie. De eenmalige eindtoets gebruikt 20- en 40-dagenblokken vanwege overlappende rendementen, met alpha=0,01/8 voor twee kandidaten × twee maatstaven × twee bloklengtes. Deze controles bewijzen geen causaliteit of gegarandeerde beleggingswinst.

Het eindrapport wordt daarna niet overschreven. Nieuwe gevallen mogen verder worden geregistreerd voor beschrijvende opvolging; zij wijzigen die eerste eindconclusie niet. Een volgende generatie vereist een afzonderlijk vooraf vastgelegd protocol en nieuw bewijs.

## Kosten, opslag en toegang

Maximaal 150 nieuwe gedeelde gevallen/dag, 4.000 lopend en 25.000 opgeslagen. Afgeronde gevallen worden na negentig kalenderdagen opgeruimd; het eerste toetsvak blijft behouden totdat zijn eindrapport bestaat. Modelartefacten en het eindrapport blijven bewaard. Dezelfde bronuitkomst wordt niet apart per model gekopieerd.

De route pauzeert bij 24 MB eigen tabellen/indexen, 120 MB totale database of 1,2 GB geraamd maandverkeer, met een begrensde lease en vooraf gereserveerd transferbudget. Dit zijn conservatieve app-grenzen, geen providerfactuur of onbeperkte gratis garantie. Onvoldoende bronnen of budget kunnen ook de uitkomstopvolging stoppen; de website toont die status. Er is geen betaalde upgrade.

**Leren & aankoopanalyse → Twee kandidaatmodellen naast het vaste dagmodel** toont modellen, status, uitkomsten en bewijsvoorwaarden. Lezen en pauzeren/hervatten vereisen de eigenaar, TOTP en een geldige app-sessie. Browserrollen hebben geen directe toegang tot tabellen, opleidingsinvoer of beheerroutines. `promote` en andere ongeldige acties worden geweigerd.

Validatie: volledige Node-suite, `managed/tests/test_candidate_database.py` met een tijdelijke lokale database en uitsluitend daar een synthetische klok, plus browsercontroles met synthetische MFA op laptop en gsm. Tests controleren trainingsgrenzen, onveranderlijke modellen, toekomstige labels, herziene invoer, pauzes, limieten, retentie en het behoud van de hoofdrekening.
