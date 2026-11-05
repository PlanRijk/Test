# Afzonderlijke EUR10.000-paperportefeuille

Op verzoek toegevoegd naast de bestaande EUR500-proef, zonder geld, posities, risicostops, modellen of toetsregels van die referentie te resetten. De nieuwe rekening `capital10k` begint leeg met EUR10.000 virtueel geld. Bekende marktgeschiedenis mag als beslisinvoer worden hergebruikt; eerdere transacties worden niet overgenomen of teruggedateerd.

## Vaste proefinstellingen

Maximaal EUR500 per aankoop, twaalf posities, twee per sector en twaalf aankopen per dag. Minimaal EUR1.000 kas en maximaal 80% blootstelling. Dagverliesgrens EUR200 (2% van het startkapitaal), terugvalgrens EUR500 (5%). Deze drempels garanderen geen maximale schade bij koerssprongen, bronuitval of verouderde koersen. Een hervatknop wist geen risicostops. De bestaande sectoren en 100 intradaybedrijven worden hergebruikt; het bredere dagonderzoek blijft apart.

Dezelfde momentumdrempel, latere verse uitvoeringskoers, beschermende exits, kosten, voorlopige buitenlandse/ADR-reserves, Belgische TOB en meerwaardereserve gelden. Ook gewone winstverkopen houden dezelfde minimum-nettovoorwaarde. Geen brokerverbinding of echte orders. Meer kapitaal lost de beperkte uitvoerbare koersdekking niet op.

De proef verandert tegelijk kapitaal, ordergrootte en spreiding en begint later dan de referentie. Een hoger absoluut euroresultaat bewijst geen beter model of causale meerwaarde. Vergelijk kosten per omzet, rendement, blootstelling en risico. De dossiers zijn een apart onderzoeksbestand; zij vergroten niet automatisch de referentiesteekproef van de bestaande intradaymodellen of de vaste dagmodeltoets.

## Bestaande koersronde en onafhankelijke kasboeken

`paper-tick` hergebruikt één opgehaalde marktbatch voor de bestaande verwerking en de nieuwe rekening. Er zijn geen extra koersdownloads, worker of cronjob. De huidige vijfminutenplanning blijft gelden. Als de hoofdkoersroutine pauzeert of haar budget bereikt, stopt deze uitbreiding mee. Een handmatige koersstap volgt hetzelfde pad.

De nieuwe rekening heeft een eigen lease en revisie. Opslag van haar uitkomst vereist eerst een geslaagde commit van precies de gebruikte hoofdronde. Superseded rondes, verlopen leases en fouten leveren geen nieuwe kapitalentransacties op. Optionele kapitaal-RPC's hebben vijf seconden timeout, zodat bronkoersen en de hoofdlease niet onnodig door de uitbreiding verouderen. Een fout in deze route blijft afzonderlijk en kan een geslaagde hoofdcommit niet terugdraaien.

Een eigen kasboek controleert cashflow, commissies, gerealiseerd resultaat, aankoopmotivatie en risico-overgangen. Alle bewijzen worden opgeslagen in echte euro-/lokale-valutabedragen en hoeveelheden. Lezen, exporteren, bewijzen en pauzeren/hervatten vereisen de eigenaar, MFA en een geldige app-sessie. Browserrollen kunnen de tabellen of beheerroutines niet rechtstreeks lezen.

## Hergebruik van de bevroren rekenregels

De bestaande engine bevat een vaste EUR100-ordergrootte en blijft ongewijzigd. De adapter rekent intern in eenheden van EUR5: EUR100 intern is EUR500 werkelijk. Alle lokale koersbedragen, financiële balansen, vaste commissieminima, ADR-bedragen, geldcaps en minimum-nettowinst worden consequent geschaald; aantallen aandelen, relatieve signalen, percentages, FX-verhoudingen, tijdstempels en basispunten blijven behouden. Ook EUR-quotes blijven aan FX=1 voldoen. Opgeslagen aankoop-/verkoopbewijzen en schermwaarden worden volledig naar werkelijke bedragen omgerekend.

De implementatie en het oorspronkelijke kosten-/risicoprofiel krijgen een fingerprint. Een gewijzigd bronprofiel wordt geweigerd. De installatie via `scripts/capital_study.py configure PROJECT_REF` is herhaalbaar zonder rekeningreset; een andere implementatie wordt vóór het aanpassen van een lopende proef geweigerd. Bestaande historische en kandidaatmodelartefacten en hun fingerprints veranderen niet.

## Gratis gebruik begrenzen

Eigen geraamd dataverkeer: nieuwe aankopen stoppen vanaf 240 MB/maand, alle verwerking pauzeert uiterlijk bij 300 MB. Daarnaast gelden zachte/harde grenzen van 12/20 MB eigen tabellen en indexen, 120/150 MB totale database en 1,2/1,5 GB totaal geraamd workerverkeer. Dit zijn app-ramingen, geen providerfactuur; Render-verkeer en andere providerposten ontbreken. Er wordt geen betaalde uitbreiding aangemaakt.

Vanaf 1.800 handelsacties worden geen nieuwe aankopen toegelaten, zodat ruimte voor beschermende verkopen overblijft; de harde grens is 2.000 bewijzen. Aankoopbewijzen worden behouden. De curve bewaart per uur eerste, laatste, laagste en hoogste werkelijk bevestigde liquidatiewaarde voor maximaal negentig dagen; de website leest de laatste 240 uurpunten. Geen nieuwe curvepunten op rondes zonder verse marktdata. CSV-export is begrensd op de laatste 500 eigen transacties.

Bij zachte grenzen worden bestaande posities nog gevolgd; een harde pauze kan ook de uitkomstopvolging stoppen. De site toont die toestand. Het model krijgt daardoor geen verzonnen uitvoeringen of winstlabels. Langdurig onbeperkt bewijs bewaren en tegelijk eeuwig gratis blijven wordt niet beloofd.

## Validatie

`npm test --prefix managed`: onafhankelijke kasstroomberekeningen voor USD/EUR/GBP/ADR, controle van hoeveelheden en alle getoonde bewijsbedragen, sector-/positielimieten, beschermende exits, verouderde koersen, immutable invoer en de koppeling van hoofd-/kapitaalcommits bij storingen.

`python managed/tests/test_capital_database.py`: tijdelijke lokale database, uitsluitend daar een synthetische klok; kasboekafwijkingen en ontbrekende motivatie worden geweigerd, rolrechten en eigenaar worden getoetst, leases/revisies, herhaalbare installatie, risicostops, export- en verbruiksgrenzen worden gecontroleerd. Synthetische browserchecks testen laptop/gsm, MFA, bewijs, export en bediening. Productiecontroles gebruiken echte bronnen; er worden geen synthetische marktgegevens in productie geplaatst.
