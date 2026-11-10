# Kostenbewuste nettowinstneming

De actieve €10.000-paperrekening gebruikt een nieuwe, afzonderlijk vastgelegde
exitfase `net-exits-v1`. De bestaande vijfpijlerinstap, financiële rekenhelpers,
controlegroepen, aankoopkosten, belastingreserves, verliesstops en portefeuillerisico's
blijven bewaard. Geen echte brokerorders, betaalde diensten of extra marktvragen.

## Aanleiding en definitie

De vorige regel verlangde minstens 2,5% koersstijging bij het besluit, maar slechts
€0,01 verwachte nettowinst bij de latere uitvoering. De echte Atlas Copco-verkoop
op 10 november 2026 om 09:35 Belgische tijd hield daardoor maar €0,32 over. Het
kostenscenario reserveert onder meer commissie, transactietaks, een conservatieve
meerwaardereserve en bij bepaalde buitenlandse aankopen extra aankoopkosten.
Een bruto koersdoel is dus geen netto rendementsdoel.

Het nieuwe gewone winstdoel is het hoogste van:

- €10 netto;
- 2,5% van de volledige werkelijke aankoopinleg, inclusief aankoopkosten;
- 1,5 maal het geschatte nettoverlies bij de bestaande koersstop.

Voor €500 is de basisgrens €12,50; bij hoge kosten kan de risicotoets een hoger
doel eisen. De stopraming gebruikt de bestaande stopprijs met 0,1% extra
uitvoeringsmarge. Het is een raming: gaps, spreads en valuta kunnen afwijken.
De gewone verkooptoets rekent met de actuele biedprijs en de bestaande 0,05%
uitvoeringsslippage. De volledige doeltoets gebeurt opnieuw op de latere verse
quote. Bij onvoldoende netto opbrengst vervalt de gewone winstorder.

Beschermende orders mogen onder dit doel of met verlies verkopen: bestaande
koersstop, portefeuillebrede risicostop of een eerder vastgelegde beschermende
order. Het doel wordt niet als risicostop vermomd om de nettogrens te omzeilen.
Geen verplichte dagsluiting of verkoop na een bepaald aantal sessies.

## Bewijs en overgang

Iedere nieuwe aankoop bevat een doelraming bij het besluit en de actuele berekening
bij uitvoering. Iedere verkoop bevat het vereiste nettodoel, kostenbasis, geschat
stopverlies, werkelijke netto uitkomst en expliciete beschermingsuitzondering.
De private API toont de actieve regel en de doelen per open positie. De oude
€0,01-parameter blijft uitsluitend onderdeel van de vaste referentieberekening.

De overgang bewaart saldo, posities, betaalde kosten, eerdere resultaten en
risicopauzes. Alleen oude kooporders en gewone winstorders vervallen; beschermende
orders blijven staan. De nulmeting bewaart de oude waardering, laatste transactie
en toestands-hash. Een oude worker kan na activering geen oude winstorder meer
opslaan. Alle normale saldo- en bewijstoetsen blijven nodig voor het nieuwe pad.

## Grenzen van de optimalisatie

Deze parameters vormen een vooraf vastgelegde paperhypothese. Een hogere
gemiddelde winst per geslaagde verkoop bewijst geen hoger totaalrendement:
doelen kunnen minder vaak worden bereikt, kapitaal kan langer vastzitten en
koerswinsten kunnen terugvallen. De huidige kleine steekproef bewijst geen
optimale doelwaarde. De eerdere rekeningfase blijft herkenbaar, maar een simpele
voor/na-vergelijking met overgedragen posities is geen onafhankelijke backtest.
Geen selectie van uitsluitend gunstige verkopen of gegarandeerde dagelijkse winst.

De berekening draait met de bestaande vijfminutenroutine in Supabase. Codex is
niet nodig voor koersrondes of deze verkoopbeslissingen; ontbrekende kwalitatieve
reviews kunnen nieuwe aankopen blijven blokkeren. Hostingquota en bronbeschikbaarheid
blijven bepalend. Geen continu extern OpenAI-model of extra tokenkosten.
