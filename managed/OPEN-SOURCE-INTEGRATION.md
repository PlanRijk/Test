# Gratis onderzoekswerkbank

De werkbank combineert bruikbare **methodes** uit vijf open source projecten in eigen, kleine Paperlabmodules. De vijf volledige frameworks zijn niet geïnstalleerd, geforkt of als externe service aangesloten. Er is geen code uit die repositories gekopieerd. De werking vereist geen nieuw account, betaalde dataset, model of hostingdienst.

| Referentie | Toegepaste methode | Concrete Paperlabfunctie |
| --- | --- | --- |
| [EdgarTools](https://github.com/dgunning/edgartools) | Primaire SEC-bronnen structureren en bewijs bij cijfers bewaren | Vaste extractieregels op reeds opgeslagen cijferberichten; kwartaal, einddatum, valuta, eenheden en winstdefinitie blijven afzonderlijk |
| [OpenBB](https://github.com/openbq-org/OpenBB) | Een gedeelde gegevenslaag voor onderzoek | Bron-ID, URL, hash, ontvangstmoment, fiscale periode, rapporteringsvaluta en bronstatus in dezelfde onderzoekscontext |
| [TradingAgents](https://github.com/TauricResearch/TradingAgents) | Onderzoek vanuit bedrijf, macro, koers en risico | Vier expliciete perspectieven binnen bestaande dossier- en kwartaalprompts, met tegenbewijs en onbekenden; geen vier onafhankelijke analisten en geen extra modelcalls |
| [AI Hedge Fund](https://github.com/virattt/ai-hedge-fund) | Herleidbare besluiten en reproduceerbare paperproeven | Append-only onderzoekshistoriek met hashketen; bestaande onveranderlijke forecasts blijven behouden |
| [LEAN](https://github.com/QuantConnect/Lean) | Chronologische eventverwerking, latere uitvoering, kosten en benchmark | Een native, begrensde slotkoersdiagnose met twee tijdvensters en vaste parameters; LEAN zelf draait niet en dit is geen volledige replay van de handelsmotor |

De referenties zijn op 26 november 2026 bekeken. Licenties of gratis code geven geen recht op gratis commerciële data. Externe betaalde onderdelen uit de referentieprojecten zijn niet aangesloten.

## Bronextractie zonder taalmodel

`research-core.js` leest expliciete USD-omzetkoppen en expliciet gelabelde GAAP/aangepaste WPA uit opgeslagen SEC-cijferberichten. Het scheidt groepsomzet van segmenten en toekomstverwachtingen en controleert de fiscale periode en letterlijk genoemde einddatum. Een gecombineerd GAAP/non-GAAP-citaat wordt op de juiste waarde en volgorde gekoppeld. Conflicterende primaire lezingen blijven onbevestigd. De voorkeur voor winstbasis volgt de vooraf vastgelegde verwachting.

De rapporteringsvaluta komt uit opgeslagen financiële context of de oorspronkelijke forecast. Dit is expliciet gelabeld, geen onafhankelijke valuta-audit. Andere valuta, onduidelijke tabelindelingen, ontbrekende koppen en onbekende basis vallen buiten deze vaste extractor. Daar blijft de bestaande modelroute beschikbaar zodra het gedeelde gratis quotum dat toelaat.

De wachtrij kan een bestaande bron bij provideruitval of uitgeput modelquotum verwerken. Nul modelcalls wijzigen geen provider-cooldown en verbruiken geen dagaanvraag. De oorspronkelijke bron-, opslag- en dataverkeersgrenzen blijven gelden. Een geslaagde cijferextractie rondt geen callbeoordeling, kwalitatieve handelsreview of echte order af.

## Onderzoekshistoriek

Originele menselijke forecasts worden met hun oorspronkelijke tijdstempel geïmporteerd; het importmoment is afzonderlijk opgeslagen. Nieuwe geslaagde automatische kwartaalbeoordelingen en cijferextracties krijgen een compacte registratie met bron-ID’s en meetwaarden. Eenmalige leases voorkomen dubbele commits. Normale browser- en servicerollen kunnen de tabel niet rechtstreeks wijzigen.

Iedere hash omvat de voorgaande hash, een newline en de PostgreSQL-JSONB-tekst van het record. De eigenaarroute verifieert de volledige keten. Dit detecteert wijzigingen binnen deze database; het is geen onafhankelijk tijdstempel of bescherming tegen een beheerder die de hele database kan herschrijven.

## Gratis strategiediagnose

`paper-free-research` verwerkt één opgeslagen historische bronversie per ronde, maximaal tien bedrijven per UTC-dag. De cron draait op minuut 7 en 37. Per claim wordt conservatief 80 kB gereserveerd binnen dezelfde bestaande 3,5 GB-prioriteitsbegroting; de harde grens van 4 GB blijft behouden. Er zijn geen externe downloads of modelaanvragen. Bij een grens wacht de worker; het dagbudget hervat automatisch en bestaande bronversies worden niet onnodig opnieuw berekend. Er wordt maximaal één compacte diagnose per bedrijf bewaard.

De laatste maximaal 180 beschikbare historische slotkoersen leveren twee chronologische vensters op na een vaste opwarmperiode. Er wordt niets op de uitkomsten geoptimaliseerd. De technische instap gebruikt dezelfde trend-/uitbraakfunctie als de paperstrategie. Uitvoering volgt op een later dagslot. Positiegrootte is 5% van de oorspronkelijke fictieve 10.000 munteenheden; stops, doelen en twintig sessies zijn afzonderlijke diagnostische vereenvoudigingen.

Resultaten bevatten rendement, maximale terugval, aantallen, een koop-en-aanhoudenreferentie met dezelfde initiële allocatie en kostenstress van 0,5% versus 1% **per zijde**. Dit zijn scenario’s, geen geverifieerde IBKR-kosten of persoonlijke Belgische belastingen. Intradagprijzen ontbreken, dus echte stopuitvoering en de volledige handelsmotor kunnen hiermee niet worden gevalideerd. Er is geen historische kwalitatieve goedkeuring gereconstrueerd. Ontbrekende dividend-/FX-verwerking, overlevingsbias en achteraf verkregen historie blijven zichtbaar. Verouderde bronreeksen krijgen een melding. Een positief resultaat geeft geen koopgoedkeuring of bewezen beleggingsvoordeel.

## Installatie en controle

Migratie 045, `python scripts/free_research.py kdyzlbknygeqinqduuic`, bestaande Free-tier-koppelingen en databasecron. Financiële profielen en oorspronkelijke forecasts worden vóór en na installatie vergeleken. Er komen geen extra handelsrechten of nieuwe betaalde diensten bij.

Tests omvatten letterlijke bronpassages, GAAP/non-GAAP-verwisseling, fiscale periode, valuta, segmentomzet, conflicterende bronnen, modelvrije verwerking bij quota-uitval, ongewijzigde cooldown, eenmalige commits, hashketencontrole, RLS, chronologische uitvoering, kostenstress en onbekende bedrijfsacties.
